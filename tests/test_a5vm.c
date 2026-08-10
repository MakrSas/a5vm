#include <stdio.h>

#include "a5vm/cpu8086.h"
#include "a5vm/floppy.h"
#include "a5vm/keyboard.h"
#include "a5vm/machine.h"
#include "a5vm/pic8259.h"
#include "a5vm/pit8253.h"
#include "a5vm/vga_text.h"

static int failures;

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #condition); \
        failures++; \
    } \
} while (0)

static void test_memory_wrap(void) {
    a5vm_memory memory;
    a5vm_memory_init(&memory);
    a5vm_memory_write16(&memory, 0xFFFFF, 0xBEEF);
    CHECK(a5vm_memory_read8(&memory, 0xFFFFF) == 0xEF);
    CHECK(a5vm_memory_read8(&memory, 0x100000) == 0xBE);
    CHECK(a5vm_memory_read16(&memory, 0xFFFFF) == 0xBEEF);
}

static void run_program(const uint8_t *program, size_t length,
                        a5vm_cpu8086 *cpu, a5vm_memory *memory) {
    a5vm_memory_init(memory);
    a5vm_memory_load(memory, 0x200, program, length);
    a5vm_cpu8086_init(cpu, memory);
    cpu->segs[A5VM_SEG_CS] = 0;
    cpu->ip = 0x200;
    cpu->regs[A5VM_REG_SP] = 0x8000;
    (void)a5vm_cpu8086_run(cpu, 1000);
}

static void test_arithmetic_and_branch(void) {
    static const uint8_t program[] = {
        0xB8, 0x02, 0x00,       /* mov ax, 2 */
        0x05, 0x03, 0x00,       /* add ax, 3 */
        0x3D, 0x05, 0x00,       /* cmp ax, 5 */
        0x74, 0x03,             /* jz +3 */
        0xB9, 0xAD, 0xDE,       /* mov cx, dead (must be skipped) */
        0xF4                    /* hlt */
    };
    a5vm_memory memory;
    a5vm_cpu8086 cpu;
    run_program(program, sizeof(program), &cpu, &memory);
    CHECK(cpu.status == A5VM_CPU_HALTED);
    CHECK(cpu.regs[A5VM_REG_AX] == 5);
    CHECK(cpu.regs[A5VM_REG_CX] == 0);
    CHECK((cpu.flags & A5VM_FLAG_ZF) != 0);
}

static void test_stack(void) {
    static const uint8_t program[] = {
        0xB8, 0x34, 0x12,       /* mov ax, 1234 */
        0x50,                   /* push ax */
        0xB8, 0, 0,             /* mov ax, 0 */
        0x58,                   /* pop ax */
        0xF4                    /* hlt */
    };
    a5vm_memory memory;
    a5vm_cpu8086 cpu;
    run_program(program, sizeof(program), &cpu, &memory);
    CHECK(cpu.status == A5VM_CPU_HALTED);
    CHECK(cpu.regs[A5VM_REG_AX] == 0x1234);
    CHECK(cpu.regs[A5VM_REG_SP] == 0x8000);
}

static void test_vga_text(void) {
    a5vm_vga_text vga;
    a5vm_vga_text_init(&vga);
    a5vm_vga_text_write(&vga, "A5VM");
    CHECK(vga.cells[0] == 'A');
    CHECK(vga.cells[2] == '5');
    CHECK(vga.cursor_column == 4);
    a5vm_vga_text_write(&vga, "\nREADY");
    CHECK(vga.cells[A5VM_VGA_TEXT_COLUMNS * 2u] == 'R');
    CHECK(vga.cells[A5VM_VGA_TEXT_COLUMNS * 2u + 2u] == 'E');

    {
        unsigned line;
        for (line = 0; line < A5VM_VGA_TEXT_ROWS; ++line) {
            a5vm_vga_text_putc(&vga, '\n');
        }
    }
    CHECK(vga.cursor_row == A5VM_VGA_TEXT_ROWS - 1u);
}

static void test_keyboard(void) {
    a5vm_keyboard keyboard;
    uint8_t value = 0;
    unsigned index;
    a5vm_keyboard_init(&keyboard);
    CHECK(a5vm_keyboard_empty(&keyboard));
    CHECK(a5vm_keyboard_push(&keyboard, 'A'));
    CHECK(a5vm_keyboard_push(&keyboard, 'B'));
    CHECK(a5vm_keyboard_pop(&keyboard, &value) && value == 'A');
    CHECK(a5vm_keyboard_pop(&keyboard, &value) && value == 'B');
    CHECK(a5vm_keyboard_empty(&keyboard));
    for (index = 0; index < A5VM_KEYBOARD_CAPACITY; ++index) {
        CHECK(a5vm_keyboard_push(&keyboard, (uint8_t)index));
    }
    CHECK(!a5vm_keyboard_push(&keyboard, 0xFF));
}

static void test_pic_and_pit(void) {
    a5vm_pic8259 pic;
    a5vm_pit8253 pit;
    uint8_t vector = 0;

    a5vm_pic8259_init(&pic, 0x08);
    a5vm_pic8259_raise(&pic, 0);
    CHECK(!a5vm_pic8259_has_pending(&pic));
    a5vm_pic8259_set_mask(&pic, 0, 1);
    CHECK(a5vm_pic8259_has_pending(&pic));
    CHECK(a5vm_pic8259_acknowledge(&pic, &vector) && vector == 0x08);
    CHECK(!a5vm_pic8259_has_pending(&pic));
    CHECK(!a5vm_pic8259_acknowledge(&pic, &vector));

    a5vm_pit8253_init(&pit, 3);
    CHECK(a5vm_pit8253_tick(&pit, 2) == 0);
    CHECK(a5vm_pit8253_tick(&pit, 1) == 1);
    CHECK(a5vm_pit8253_tick(&pit, 7) == 2);
    CHECK(pit.ticks == 3);
}

static void test_hardware_interrupt_delivery(void) {
    a5vm_machine machine;
    static const uint8_t program[] = { 0xFB, 0x90, 0xF4 };
    static const uint8_t handler[] = { 0xB8, 0x34, 0x12, 0xF4 };
    CHECK(a5vm_machine_init(&machine));
    a5vm_memory_write16(&machine.memory, 0x20, 0x3000);
    a5vm_memory_write16(&machine.memory, 0x22, 0x0000);
    a5vm_memory_load(&machine.memory, 0x1000, program, sizeof(program));
    a5vm_memory_load(&machine.memory, 0x3000, handler, sizeof(handler));
    machine.cpu.segs[A5VM_SEG_CS] = 0;
    machine.cpu.segs[A5VM_SEG_SS] = 0;
    machine.cpu.ip = 0x1000;
    machine.cpu.regs[A5VM_REG_SP] = 0x8000;
    a5vm_pit8253_init(&machine.pit, 1);
    a5vm_pic8259_set_mask(&machine.pic, 0, 1);
    CHECK(a5vm_machine_run(&machine, 20) == A5VM_CPU_HALTED);
    CHECK(machine.cpu.regs[A5VM_REG_AX] == 0x1234);
    CHECK(machine.cpu.segs[A5VM_SEG_CS] == 0);
    a5vm_machine_deinit(&machine);
}

static void test_floppy_and_boot(void) {
    a5vm_floppy floppy;
    a5vm_machine machine;
    uint8_t sector[A5VM_FLOPPY_SECTOR_SIZE];
    a5vm_cpu_status status;

    CHECK(a5vm_floppy_init(&floppy, 0));
    a5vm_floppy_create_demo(&floppy);
    CHECK(a5vm_floppy_read_sector(&floppy, 0, sector));
    CHECK(sector[0] == 0xB4 && sector[1] == 0x0E);
    CHECK(sector[510] == 0x55 && sector[511] == 0xAA);
    CHECK(!a5vm_floppy_read_sector(&floppy, A5VM_FLOPPY_SECTOR_COUNT, sector));
    a5vm_floppy_deinit(&floppy);

    CHECK(a5vm_machine_init(&machine));
    status = a5vm_machine_boot(&machine, 100);
    CHECK(status == A5VM_CPU_HALTED);
    CHECK(machine.cpu.regs[A5VM_REG_AX] == 5);
    CHECK(machine.cpu.regs[A5VM_REG_BX] == 3);
    CHECK(machine.cpu.ip > A5VM_BOOT_ADDRESS);
    CHECK(machine.vga.cells[0] == 'A');
    CHECK(machine.vga.cells[2] == '5');
    CHECK(machine.vga.cells[4] == 'V');
    CHECK(machine.vga.cells[6] == 'M');
    a5vm_pic8259_set_mask(&machine.pic, 0, 1);
    a5vm_machine_tick(&machine, 65536);
    CHECK(machine.pit.ticks == 1);
    CHECK(a5vm_pic8259_has_pending(&machine.pic));
    CHECK(a5vm_pic8259_acknowledge(&machine.pic, &sector[0]) && sector[0] == 0x08);

    {
        static const uint8_t disk_read_program[] = {
            0xB8, 0x01, 0x02,       /* mov ax, 0201h: read one sector */
            0xB9, 0x01, 0x00,       /* mov cx, 0001h: cylinder 0, sector 1 */
            0xBA, 0x00, 0x00,       /* mov dx, 0000h: drive 0, head 0 */
            0xBB, 0x00, 0x80,       /* mov bx, 8000h */
            0xCD, 0x13,
            0xF4
        };
        a5vm_machine_reset(&machine);
        a5vm_memory_load(&machine.memory, 0x1000,
                         disk_read_program, sizeof(disk_read_program));
        machine.cpu.segs[A5VM_SEG_CS] = 0;
        machine.cpu.segs[A5VM_SEG_ES] = 0;
        machine.cpu.ip = 0x1000;
        status = a5vm_cpu8086_run(&machine.cpu, 100);
        CHECK(status == A5VM_CPU_HALTED);
        CHECK(a5vm_memory_read8(&machine.memory, 0x8000) == 0xB4);
        CHECK((machine.cpu.flags & A5VM_FLAG_CF) == 0);
    }

    {
        static const uint8_t hard_disk_read_program[] = {
            0xB8, 0x01, 0x02,       /* mov ax, 0201h: read one sector */
            0xB9, 0x01, 0x00,       /* mov cx, 0001h */
            0xBA, 0x80, 0x00,       /* mov dx, 0080h: first hard disk */
            0xBB, 0x00, 0x90,       /* mov bx, 9000h */
            0xCD, 0x13,
            0xF4
        };
        uint8_t hard_disk_sector[A5VM_DISK_SECTOR_SIZE] = { 0 };
        hard_disk_sector[0] = 0xDE;
        hard_disk_sector[1] = 0xAD;
        CHECK(a5vm_disk_write_sector(&machine.disk, 0, hard_disk_sector));
        a5vm_machine_reset(&machine);
        a5vm_memory_load(&machine.memory, 0x1100,
                         hard_disk_read_program,
                         sizeof(hard_disk_read_program));
        machine.cpu.segs[A5VM_SEG_CS] = 0;
        machine.cpu.segs[A5VM_SEG_ES] = 0;
        machine.cpu.ip = 0x1100;
        status = a5vm_cpu8086_run(&machine.cpu, 100);
        CHECK(status == A5VM_CPU_HALTED);
        CHECK(a5vm_memory_read8(&machine.memory, 0x9000) == 0xDE);
        CHECK(a5vm_memory_read8(&machine.memory, 0x9001) == 0xAD);
        CHECK((machine.cpu.flags & A5VM_FLAG_CF) == 0);
    }

    {
        static const uint8_t ide_pio_program[] = {
            0xBA, 0xF2, 0x01,       /* mov dx, 01F2h: sector count */
            0xB0, 0x01, 0xEE,       /* mov al, 1; out dx, al */
            0xBA, 0xF3, 0x01,       /* LBA low */
            0xB0, 0x00, 0xEE,
            0xBA, 0xF4, 0x01,       /* LBA mid */
            0xB0, 0x00, 0xEE,
            0xBA, 0xF5, 0x01,       /* LBA high */
            0xB0, 0x00, 0xEE,
            0xBA, 0xF6, 0x01,       /* master drive, LBA mode */
            0xB0, 0xE0, 0xEE,
            0xBA, 0xF7, 0x01,       /* READ SECTORS */
            0xB0, 0x20, 0xEE,
            0xBA, 0xF0, 0x01,       /* data port */
            0xED,                   /* in ax, dx: DE AD */
            0xBB, 0x00, 0x90,
            0x89, 0x07,             /* mov [bx], ax */
            0xBA, 0xF3, 0x01,       /* select LBA 1 */
            0xB0, 0x01, 0xEE,
            0xBA, 0xF7, 0x01,       /* WRITE SECTORS */
            0xB0, 0x30, 0xEE,
            0xBA, 0xF0, 0x01,
            0xB8, 0xDE, 0xAD,       /* data word */
            0xB9, 0x00, 0x01,       /* 256 words = one sector */
            0xEF,
            0x49,
            0x75, 0xFC,             /* loop until CX == 0 */
            0xF4
        };
        uint8_t written[A5VM_DISK_SECTOR_SIZE] = { 0 };
        a5vm_machine_reset(&machine);
        a5vm_memory_load(&machine.memory, 0x1200,
                         ide_pio_program, sizeof(ide_pio_program));
        machine.cpu.segs[A5VM_SEG_CS] = 0;
        machine.cpu.ip = 0x1200;
        status = a5vm_cpu8086_run(&machine.cpu, 1000);
        CHECK(status == A5VM_CPU_HALTED);
        CHECK(a5vm_memory_read8(&machine.memory, 0x9000) == 0xDE);
        CHECK(a5vm_memory_read8(&machine.memory, 0x9001) == 0xAD);
        CHECK(a5vm_disk_read_sector(&machine.disk, 1, written));
        CHECK(written[0] == 0xDE && written[1] == 0xAD);
    }
    a5vm_machine_deinit(&machine);
}

int main(void) {
    test_memory_wrap();
    test_arithmetic_and_branch();
    test_stack();
    test_vga_text();
    test_keyboard();
    test_pic_and_pit();
    test_hardware_interrupt_delivery();
    test_floppy_and_boot();
    if (failures != 0) {
        fprintf(stderr, "%d test(s) failed\n", failures);
        return 1;
    }
    puts("a5vm-tests: all tests passed");
    return 0;
}

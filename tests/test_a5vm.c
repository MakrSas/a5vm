#include <stdio.h>

#include "a5vm/cpu8086.h"
#include "a5vm/floppy.h"
#include "a5vm/keyboard.h"
#include "a5vm/machine.h"
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

static void test_floppy_and_boot(void) {
    a5vm_floppy floppy;
    a5vm_machine machine;
    uint8_t sector[A5VM_FLOPPY_SECTOR_SIZE];
    a5vm_cpu_status status;

    CHECK(a5vm_floppy_init(&floppy, 0));
    a5vm_floppy_create_demo(&floppy);
    CHECK(a5vm_floppy_read_sector(&floppy, 0, sector));
    CHECK(sector[0] == 0xB8);
    CHECK(sector[510] == 0x55 && sector[511] == 0xAA);
    CHECK(!a5vm_floppy_read_sector(&floppy, A5VM_FLOPPY_SECTOR_COUNT, sector));
    a5vm_floppy_deinit(&floppy);

    CHECK(a5vm_machine_init(&machine));
    status = a5vm_machine_boot(&machine, 100);
    CHECK(status == A5VM_CPU_HALTED);
    CHECK(machine.cpu.regs[A5VM_REG_AX] == 5);
    CHECK(machine.cpu.regs[A5VM_REG_BX] == 3);
    CHECK(machine.cpu.ip == A5VM_BOOT_ADDRESS + 9u);
    a5vm_machine_deinit(&machine);
}

int main(void) {
    test_memory_wrap();
    test_arithmetic_and_branch();
    test_stack();
    test_vga_text();
    test_keyboard();
    test_floppy_and_boot();
    if (failures != 0) {
        fprintf(stderr, "%d test(s) failed\n", failures);
        return 1;
    }
    puts("a5vm-tests: all tests passed");
    return 0;
}

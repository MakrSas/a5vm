#include "a5vm/bios.h"

#include "a5vm/floppy.h"
#include "a5vm/machine.h"
#include "a5vm/vga_text.h"

static uint8_t low_byte(uint16_t value) {
    return (uint8_t)value;
}

static uint8_t high_byte(uint16_t value) {
    return (uint8_t)(value >> 8);
}

static void set_low_byte(uint16_t *value, uint8_t byte) {
    *value = (uint16_t)((*value & 0xFF00u) | byte);
}

static void set_high_byte(uint16_t *value, uint8_t byte) {
    *value = (uint16_t)((*value & 0x00FFu) | ((uint16_t)byte << 8));
}

static void set_carry(a5vm_cpu8086 *cpu, int value) {
    if (value) cpu->flags |= A5VM_FLAG_CF;
    else cpu->flags &= (uint16_t)~A5VM_FLAG_CF;
}

static int bios_video(a5vm_cpu8086 *cpu, a5vm_machine *machine) {
    uint8_t ah = high_byte(cpu->regs[A5VM_REG_AX]);
    uint8_t al = low_byte(cpu->regs[A5VM_REG_AX]);
    if (ah == 0x00) {
        a5vm_vga_text_clear(&machine->vga);
        return 1;
    }
    if (ah == 0x0E) {
        a5vm_vga_text_putc(&machine->vga, al);
        return 1;
    }
    return 0;
}

static int bios_disk(a5vm_cpu8086 *cpu, a5vm_machine *machine) {
    uint8_t ah = high_byte(cpu->regs[A5VM_REG_AX]);
    uint8_t count = low_byte(cpu->regs[A5VM_REG_AX]);
    uint8_t cylinder = high_byte(cpu->regs[A5VM_REG_CX]);
    uint8_t sector = low_byte(cpu->regs[A5VM_REG_CX]) & 0x3Fu;
    uint8_t head = high_byte(cpu->regs[A5VM_REG_DX]);
    uint8_t drive = low_byte(cpu->regs[A5VM_REG_DX]);
    uint8_t buffer[A5VM_FLOPPY_SECTOR_SIZE];
    unsigned lba;

    if (ah != 0x02) return 0;
    if (count != 1 || drive != 0 || cylinder >= 80 || head >= 2 ||
        sector == 0 || sector > 18) {
        set_carry(cpu, 1);
        set_high_byte(&cpu->regs[A5VM_REG_AX], 0x01);
        return 1;
    }
    lba = ((unsigned)cylinder * 2u + head) * 18u + (sector - 1u);
    if (!a5vm_floppy_read_sector(&machine->floppy, lba, buffer)) {
        set_carry(cpu, 1);
        set_high_byte(&cpu->regs[A5VM_REG_AX], 0x20);
        return 1;
    }
    a5vm_memory_load(cpu->memory,
                     a5vm_cpu8086_linear_address(cpu,
                                                 cpu->segs[A5VM_SEG_ES],
                                                 cpu->regs[A5VM_REG_BX]),
                     buffer, sizeof(buffer));
    set_carry(cpu, 0);
    set_high_byte(&cpu->regs[A5VM_REG_AX], 0x00);
    return 1;
}

static int bios_keyboard(a5vm_cpu8086 *cpu, a5vm_machine *machine) {
    uint8_t ah = high_byte(cpu->regs[A5VM_REG_AX]);
    uint8_t value;
    if (ah != 0x00) return 0;
    if (!a5vm_keyboard_pop(&machine->keyboard, &value)) {
        cpu->flags |= A5VM_FLAG_ZF;
        return 1;
    }
    set_low_byte(&cpu->regs[A5VM_REG_AX], value);
    set_high_byte(&cpu->regs[A5VM_REG_AX], 0);
    cpu->flags &= (uint16_t)~A5VM_FLAG_ZF;
    return 1;
}

int a5vm_bios_handle_interrupt(a5vm_cpu8086 *cpu, uint8_t vector,
                               void *context) {
    a5vm_machine *machine = (a5vm_machine *)context;
    switch (vector) {
        case 0x10: return bios_video(cpu, machine);
        case 0x13: return bios_disk(cpu, machine);
        case 0x16: return bios_keyboard(cpu, machine);
        default: return 0;
    }
}

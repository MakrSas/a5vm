#include "a5vm/bios.h"

#include "a5vm/disk.h"
#include "a5vm/floppy.h"
#include "a5vm/machine.h"
#include "a5vm/vga_text.h"

static uint8_t low_byte(uint32_t value) {
    return (uint8_t)value;
}

static uint8_t high_byte(uint32_t value) {
    return (uint8_t)(value >> 8);
}

static void set_low_byte(uint32_t *value, uint8_t byte) {
    *value = (*value & 0xFFFFFF00u) | byte;
}

static void set_high_byte(uint32_t *value, uint8_t byte) {
    *value = (*value & 0xFFFF00FFu) | ((uint32_t)byte << 8);
}

static void set_carry(a5vm_cpu386 *cpu, int value) {
    if (value) cpu->eflags |= A5VM_FLAG_CF;
    else cpu->eflags &= ~((uint32_t)A5VM_FLAG_CF);
}

static int bios386_video(a5vm_cpu386 *cpu, a5vm_machine *machine) {
    uint8_t ah = high_byte(cpu->regs[A5VM_CPU386_REG_EAX]);
    uint8_t al = low_byte(cpu->regs[A5VM_CPU386_REG_EAX]);
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

static int bios386_disk(a5vm_cpu386 *cpu, a5vm_machine *machine) {
    uint8_t ah = high_byte(cpu->regs[A5VM_CPU386_REG_EAX]);
    uint8_t count = low_byte(cpu->regs[A5VM_CPU386_REG_EAX]);
    unsigned cylinder = high_byte(cpu->regs[A5VM_CPU386_REG_ECX]) |
        ((unsigned)(low_byte(cpu->regs[A5VM_CPU386_REG_ECX]) & 0xC0u) << 2);
    uint8_t sector = low_byte(cpu->regs[A5VM_CPU386_REG_ECX]) & 0x3Fu;
    uint8_t head = high_byte(cpu->regs[A5VM_CPU386_REG_EDX]);
    uint8_t drive = low_byte(cpu->regs[A5VM_CPU386_REG_EDX]);
    uint8_t buffer[A5VM_FLOPPY_SECTOR_SIZE];
    uint32_t lba;
    uint32_t address;
    unsigned heads;
    unsigned sectors_per_track;
    int use_hard_disk;
    unsigned index;

    if (ah != 0x02 && ah != 0x03) return 0;
    use_hard_disk = drive == 0x80;
    if (drive == 0) {
        heads = 2;
        sectors_per_track = 18;
    } else if (use_hard_disk) {
        heads = 16;
        sectors_per_track = 63;
    } else {
        set_carry(cpu, 1);
        set_high_byte(&cpu->regs[A5VM_CPU386_REG_EAX], 0x01);
        return 1;
    }
    if (count != 1 || head >= heads || sector == 0 ||
        sector > sectors_per_track || (!use_hard_disk && cylinder >= 80)) {
        set_carry(cpu, 1);
        set_high_byte(&cpu->regs[A5VM_CPU386_REG_EAX], 0x01);
        return 1;
    }
    lba = ((uint32_t)cylinder * heads + head) * sectors_per_track +
          (sector - 1u);
    address = a5vm_cpu386_linear_address(cpu, A5VM_CPU386_SEG_ES,
                                         cpu->regs[A5VM_CPU386_REG_EBX]);
    if (ah == 0x02) {
        if (use_hard_disk) {
            if (!a5vm_disk_read_sector(&machine->disk, lba, buffer)) {
                set_carry(cpu, 1);
                set_high_byte(&cpu->regs[A5VM_CPU386_REG_EAX], 0x04);
                return 1;
            }
        } else if (!a5vm_floppy_read_sector(&machine->floppy, lba, buffer)) {
            set_carry(cpu, 1);
            set_high_byte(&cpu->regs[A5VM_CPU386_REG_EAX], 0x20);
            return 1;
        }
        a5vm_memory_load(cpu->memory, address, buffer, sizeof(buffer));
    } else {
        for (index = 0; index < A5VM_FLOPPY_SECTOR_SIZE; ++index) {
            buffer[index] = a5vm_memory_read8(cpu->memory, address + index);
        }
        if (use_hard_disk) {
            if (!a5vm_disk_write_sector(&machine->disk, lba, buffer)) {
                set_carry(cpu, 1);
                set_high_byte(&cpu->regs[A5VM_CPU386_REG_EAX], 0x04);
                return 1;
            }
        } else if (!a5vm_floppy_write_sector(&machine->floppy, lba, buffer)) {
            set_carry(cpu, 1);
            set_high_byte(&cpu->regs[A5VM_CPU386_REG_EAX], 0x20);
            return 1;
        }
    }
    set_carry(cpu, 0);
    set_high_byte(&cpu->regs[A5VM_CPU386_REG_EAX], 0x00);
    return 1;
}

static int bios386_keyboard(a5vm_cpu386 *cpu, a5vm_machine *machine) {
    uint8_t ah = high_byte(cpu->regs[A5VM_CPU386_REG_EAX]);
    uint8_t value;
    if (ah != 0x00) return 0;
    if (!a5vm_keyboard_pop(&machine->keyboard, &value)) {
        cpu->eflags |= A5VM_FLAG_ZF;
        return 1;
    }
    set_low_byte(&cpu->regs[A5VM_CPU386_REG_EAX], value);
    set_high_byte(&cpu->regs[A5VM_CPU386_REG_EAX], 0);
    cpu->eflags &= ~((uint32_t)A5VM_FLAG_ZF);
    return 1;
}

int a5vm_bios386_handle_interrupt(a5vm_cpu386 *cpu, uint8_t vector,
                                  void *context) {
    a5vm_machine *machine = (a5vm_machine *)context;
    switch (vector) {
        case 0x10: return bios386_video(cpu, machine);
        case 0x13: return bios386_disk(cpu, machine);
        case 0x16: return bios386_keyboard(cpu, machine);
        default: return 0;
    }
}

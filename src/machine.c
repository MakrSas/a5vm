#include "a5vm/machine.h"
#include "a5vm/bios.h"

#include <string.h>

static uint8_t machine_io_read8(a5vm_cpu8086 *cpu, uint16_t port,
                                void *context) {
    a5vm_machine *machine = (a5vm_machine *)context;
    uint8_t value = 0xFF;
    (void)cpu;
    (void)a5vm_ide_read8(&machine->ide, port, &value);
    return value;
}

static void machine_io_write8(a5vm_cpu8086 *cpu, uint16_t port,
                              uint8_t value, void *context) {
    a5vm_machine *machine = (a5vm_machine *)context;
    (void)cpu;
    (void)a5vm_ide_write8(&machine->ide, port, value);
}

static uint8_t machine_io_read8_386(a5vm_cpu386 *cpu, uint16_t port,
                                    void *context) {
    a5vm_machine *machine = (a5vm_machine *)context;
    uint8_t value = 0xFF;
    (void)cpu;
    (void)a5vm_ide_read8(&machine->ide, port, &value);
    return value;
}

static void machine_io_write8_386(a5vm_cpu386 *cpu, uint16_t port,
                                  uint8_t value, void *context) {
    a5vm_machine *machine = (a5vm_machine *)context;
    (void)cpu;
    (void)a5vm_ide_write8(&machine->ide, port, value);
}

int a5vm_machine_init(a5vm_machine *machine) {
    memset(machine, 0, sizeof(*machine));
    if (!a5vm_floppy_init(&machine->floppy, 0)) return 0;
    if (!a5vm_disk_init(&machine->disk, 0)) {
        a5vm_floppy_deinit(&machine->floppy);
        return 0;
    }
    a5vm_ide_init(&machine->ide, &machine->disk);
    a5vm_floppy_create_demo(&machine->floppy);
    a5vm_machine_reset(machine);
    return 1;
}

void a5vm_machine_deinit(a5vm_machine *machine) {
    a5vm_disk_deinit(&machine->disk);
    a5vm_floppy_deinit(&machine->floppy);
}

void a5vm_machine_reset(a5vm_machine *machine) {
    a5vm_memory_init(&machine->memory);
    a5vm_cpu8086_init(&machine->cpu, &machine->memory);
    a5vm_cpu8086_set_interrupt_handler(&machine->cpu,
                                       a5vm_bios_handle_interrupt, machine);
    a5vm_ide_reset(&machine->ide);
    a5vm_cpu8086_set_io_handlers(&machine->cpu, machine_io_read8,
                                 machine_io_write8, machine);
    a5vm_cpu386_init(&machine->cpu386, &machine->memory);
    a5vm_cpu386_set_interrupt_handler(&machine->cpu386,
                                      a5vm_bios386_handle_interrupt, machine);
    a5vm_cpu386_set_io_handlers(&machine->cpu386, machine_io_read8_386,
                                machine_io_write8_386, machine);
    a5vm_keyboard_init(&machine->keyboard);
    a5vm_vga_text_init(&machine->vga);
    a5vm_pic8259_init(&machine->pic, 0x08);
    a5vm_pit8253_init(&machine->pit, 65536);
}

void a5vm_machine_tick(a5vm_machine *machine, uint32_t cycles) {
    uint32_t pulses = a5vm_pit8253_tick(&machine->pit, cycles);
    while (pulses-- != 0) {
        a5vm_pic8259_raise(&machine->pic, 0);
    }
}

a5vm_cpu_status a5vm_machine_run(a5vm_machine *machine,
                                  uint64_t max_steps) {
    uint64_t steps = 0;
    while (machine->cpu.status == A5VM_CPU_RUNNING && steps < max_steps) {
        uint8_t vector;
        if ((machine->cpu.flags & A5VM_FLAG_IF) != 0 &&
            a5vm_pic8259_acknowledge(&machine->pic, &vector)) {
            a5vm_cpu8086_deliver_interrupt(&machine->cpu, vector);
            continue;
        }
        a5vm_cpu8086_step(&machine->cpu);
        a5vm_machine_tick(machine, 1);
        steps++;
    }
    return machine->cpu.status;
}

a5vm_cpu_status a5vm_machine_boot(a5vm_machine *machine,
                                   uint64_t max_steps) {
    uint8_t boot_sector[A5VM_FLOPPY_SECTOR_SIZE];
    if (!a5vm_floppy_read_sector(&machine->floppy, 0, boot_sector)) {
        machine->cpu.status = A5VM_CPU_FAULT;
        strcpy(machine->cpu.fault, "unable to read floppy boot sector");
        return machine->cpu.status;
    }

    a5vm_machine_reset(machine);
    a5vm_memory_load(&machine->memory, A5VM_BOOT_ADDRESS,
                     boot_sector, sizeof(boot_sector));
    machine->cpu.segs[A5VM_SEG_CS] = 0;
    machine->cpu.segs[A5VM_SEG_SS] = 0;
    machine->cpu.ip = A5VM_BOOT_ADDRESS;
    machine->cpu.regs[A5VM_REG_SP] = 0xFFFE;
    return a5vm_machine_run(machine, max_steps);
}

a5vm_cpu_status a5vm_machine_run386(a5vm_machine *machine,
                                     uint64_t max_steps) {
    return a5vm_cpu386_run(&machine->cpu386, max_steps);
}

a5vm_cpu_status a5vm_machine_boot386(a5vm_machine *machine,
                                      uint64_t max_steps) {
    uint8_t boot_sector[A5VM_FLOPPY_SECTOR_SIZE];
    if (!a5vm_floppy_read_sector(&machine->floppy, 0, boot_sector)) {
        machine->cpu386.status = A5VM_CPU_FAULT;
        strcpy(machine->cpu386.fault, "unable to read floppy boot sector");
        return machine->cpu386.status;
    }

    a5vm_machine_reset(machine);
    a5vm_memory_load(&machine->memory, A5VM_BOOT_ADDRESS,
                     boot_sector, sizeof(boot_sector));
    machine->cpu386.segs[A5VM_CPU386_SEG_CS] = 0;
    machine->cpu386.segs[A5VM_CPU386_SEG_SS] = 0;
    machine->cpu386.segs[A5VM_CPU386_SEG_DS] = 0;
    machine->cpu386.segs[A5VM_CPU386_SEG_ES] = 0;
    machine->cpu386.eip = A5VM_BOOT_ADDRESS;
    machine->cpu386.regs[A5VM_CPU386_REG_ESP] = 0xFFFE;
    return a5vm_machine_run386(machine, max_steps);
}

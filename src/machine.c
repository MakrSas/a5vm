#include "a5vm/machine.h"

#include <string.h>

int a5vm_machine_init(a5vm_machine *machine) {
    memset(machine, 0, sizeof(*machine));
    if (!a5vm_floppy_init(&machine->floppy, 0)) return 0;
    a5vm_floppy_create_demo(&machine->floppy);
    a5vm_machine_reset(machine);
    return 1;
}

void a5vm_machine_deinit(a5vm_machine *machine) {
    a5vm_floppy_deinit(&machine->floppy);
}

void a5vm_machine_reset(a5vm_machine *machine) {
    a5vm_memory_init(&machine->memory);
    a5vm_cpu8086_init(&machine->cpu, &machine->memory);
    a5vm_keyboard_init(&machine->keyboard);
    a5vm_vga_text_init(&machine->vga);
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
    return a5vm_cpu8086_run(&machine->cpu, max_steps);
}

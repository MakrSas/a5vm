#ifndef A5VM_MACHINE_H
#define A5VM_MACHINE_H

#include "a5vm/cpu8086.h"
#include "a5vm/cpu386.h"
#include "a5vm/disk.h"
#include "a5vm/floppy.h"
#include "a5vm/ide.h"
#include "a5vm/keyboard.h"
#include "a5vm/pic8259.h"
#include "a5vm/pit8253.h"
#include "a5vm/vga_text.h"

#define A5VM_BOOT_ADDRESS 0x7C00u

typedef struct a5vm_machine {
    a5vm_memory memory;
    a5vm_cpu8086 cpu;
    a5vm_cpu386 cpu386;
    a5vm_keyboard keyboard;
    a5vm_vga_text vga;
    a5vm_floppy floppy;
    a5vm_disk disk;
    a5vm_ide ide;
    a5vm_pic8259 pic;
    a5vm_pit8253 pit;
} a5vm_machine;

int a5vm_machine_init(a5vm_machine *machine);
void a5vm_machine_deinit(a5vm_machine *machine);
void a5vm_machine_reset(a5vm_machine *machine);
a5vm_cpu_status a5vm_machine_run(a5vm_machine *machine,
                                  uint64_t max_steps);
a5vm_cpu_status a5vm_machine_run386(a5vm_machine *machine,
                                    uint64_t max_steps);
void a5vm_machine_tick(a5vm_machine *machine, uint32_t cycles);
a5vm_cpu_status a5vm_machine_boot(a5vm_machine *machine,
                                   uint64_t max_steps);
a5vm_cpu_status a5vm_machine_prepare_boot(a5vm_machine *machine);
a5vm_cpu_status a5vm_machine_boot386(a5vm_machine *machine,
                                     uint64_t max_steps);
a5vm_cpu_status a5vm_machine_prepare_boot386(a5vm_machine *machine);

#endif

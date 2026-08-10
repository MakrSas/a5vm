#ifndef A5VM_BIOS_H
#define A5VM_BIOS_H

#include "a5vm/cpu8086.h"
#include "a5vm/cpu386.h"

struct a5vm_machine;

int a5vm_bios_handle_interrupt(a5vm_cpu8086 *cpu, uint8_t vector,
                               void *context);
int a5vm_bios386_handle_interrupt(a5vm_cpu386 *cpu, uint8_t vector,
                                  void *context);

#endif

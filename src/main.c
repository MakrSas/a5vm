#include <stdio.h>

#include "a5vm/machine.h"

int main(void) {
    static a5vm_machine machine;
    a5vm_cpu_status status;

    if (!a5vm_machine_init(&machine)) {
        fprintf(stderr, "A5VM could not allocate floppy image\n");
        return 1;
    }
    status = a5vm_machine_boot(&machine, 100);

    if (status != A5VM_CPU_HALTED) {
        fprintf(stderr, "A5VM stopped with status %d: %s\n", status,
                a5vm_cpu8086_fault(&machine.cpu));
        a5vm_machine_deinit(&machine);
        return 1;
    }
    printf("A5VM 8086 demo: AX=%04X BX=%04X steps=%llu\n",
           machine.cpu.regs[A5VM_REG_AX], machine.cpu.regs[A5VM_REG_BX],
           (unsigned long long)machine.cpu.steps);
    status = machine.cpu.regs[A5VM_REG_AX] == 5 ? A5VM_CPU_HALTED : A5VM_CPU_FAULT;
    a5vm_machine_deinit(&machine);
    return status == A5VM_CPU_HALTED ? 0 : 1;
}

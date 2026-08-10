#include "a5vm/cpu8086.h"

int a5vm_ios_main(void) {
    static const uint8_t program[] = {
        0xB8, 0x02, 0x00,       /* mov ax, 2 */
        0xBB, 0x03, 0x00,       /* mov bx, 3 */
        0x01, 0xD8,             /* add ax, bx */
        0xF4                    /* hlt */
    };
    a5vm_memory memory;
    a5vm_cpu8086 cpu;

    a5vm_memory_init(&memory);
    a5vm_memory_load(&memory, 0x1000, program, sizeof(program));
    a5vm_cpu8086_init(&cpu, &memory);
    cpu.segs[A5VM_SEG_CS] = 0;
    cpu.ip = 0x1000;
    cpu.regs[A5VM_REG_SP] = 0xFFFE;
    (void)a5vm_cpu8086_run(&cpu, 100);
    return cpu.status == A5VM_CPU_HALTED && cpu.regs[A5VM_REG_AX] == 5 ? 0 : 1;
}

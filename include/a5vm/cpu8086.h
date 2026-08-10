#ifndef A5VM_CPU8086_H
#define A5VM_CPU8086_H

#include <stdint.h>

#include "a5vm/memory.h"

enum {
    A5VM_REG_AX, A5VM_REG_CX, A5VM_REG_DX, A5VM_REG_BX,
    A5VM_REG_SP, A5VM_REG_BP, A5VM_REG_SI, A5VM_REG_DI,
    A5VM_REG_COUNT
};

enum {
    A5VM_SEG_ES, A5VM_SEG_CS, A5VM_SEG_SS, A5VM_SEG_DS,
    A5VM_SEG_COUNT
};

enum {
    A5VM_FLAG_CF = 0x0001, A5VM_FLAG_PF = 0x0004,
    A5VM_FLAG_AF = 0x0010, A5VM_FLAG_ZF = 0x0040,
    A5VM_FLAG_SF = 0x0080, A5VM_FLAG_TF = 0x0100,
    A5VM_FLAG_IF = 0x0200, A5VM_FLAG_DF = 0x0400,
    A5VM_FLAG_OF = 0x0800
};

typedef enum {
    A5VM_CPU_RUNNING = 0,
    A5VM_CPU_HALTED = 1,
    A5VM_CPU_FAULT = 2,
    A5VM_CPU_UNIMPLEMENTED = 3
} a5vm_cpu_status;

typedef struct {
    uint16_t regs[A5VM_REG_COUNT];
    uint16_t segs[A5VM_SEG_COUNT];
    uint16_t ip;
    uint16_t flags;
    uint64_t steps;
    a5vm_cpu_status status;
    char fault[128];
    a5vm_memory *memory;
} a5vm_cpu8086;

void a5vm_cpu8086_init(a5vm_cpu8086 *cpu, a5vm_memory *memory);
void a5vm_cpu8086_reset(a5vm_cpu8086 *cpu);
a5vm_cpu_status a5vm_cpu8086_step(a5vm_cpu8086 *cpu);
a5vm_cpu_status a5vm_cpu8086_run(a5vm_cpu8086 *cpu, uint64_t max_steps);
uint32_t a5vm_cpu8086_linear_address(const a5vm_cpu8086 *cpu,
                                     uint16_t segment, uint16_t offset);
const char *a5vm_cpu8086_fault(const a5vm_cpu8086 *cpu);

#endif

#ifndef A5VM_CPU386_H
#define A5VM_CPU386_H

#include <stdint.h>

#include "a5vm/cpu8086.h"

enum {
    A5VM_CPU386_REG_EAX, A5VM_CPU386_REG_ECX,
    A5VM_CPU386_REG_EDX, A5VM_CPU386_REG_EBX,
    A5VM_CPU386_REG_ESP, A5VM_CPU386_REG_EBP,
    A5VM_CPU386_REG_ESI, A5VM_CPU386_REG_EDI,
    A5VM_CPU386_REG_COUNT
};

enum {
    A5VM_CPU386_SEG_ES, A5VM_CPU386_SEG_CS, A5VM_CPU386_SEG_SS,
    A5VM_CPU386_SEG_DS, A5VM_CPU386_SEG_FS, A5VM_CPU386_SEG_GS,
    A5VM_CPU386_SEG_COUNT
};

#define A5VM_CPU386_CR0_PE 0x00000001u

typedef struct {
    uint32_t regs[A5VM_CPU386_REG_COUNT];
    uint16_t segs[A5VM_CPU386_SEG_COUNT];
    uint32_t eip;
    uint32_t eflags;
    uint32_t cr0;
    uint64_t steps;
    uint32_t gdtr_base;
    uint16_t gdtr_limit;
    uint32_t segment_bases[A5VM_CPU386_SEG_COUNT];
    uint32_t segment_limits[A5VM_CPU386_SEG_COUNT];
    uint8_t segment_access[A5VM_CPU386_SEG_COUNT];
    int protected_mode;
    int default_operand_size32;
    a5vm_cpu_status status;
    char fault[128];
    a5vm_memory *memory;
} a5vm_cpu386;

void a5vm_cpu386_init(a5vm_cpu386 *cpu, a5vm_memory *memory);
void a5vm_cpu386_reset(a5vm_cpu386 *cpu);
a5vm_cpu_status a5vm_cpu386_step(a5vm_cpu386 *cpu);
a5vm_cpu_status a5vm_cpu386_run(a5vm_cpu386 *cpu, uint64_t max_steps);
uint32_t a5vm_cpu386_linear_address(const a5vm_cpu386 *cpu,
                                    unsigned segment, uint32_t offset);
const char *a5vm_cpu386_fault(const a5vm_cpu386 *cpu);

#endif

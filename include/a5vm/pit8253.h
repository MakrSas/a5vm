#ifndef A5VM_PIT8253_H
#define A5VM_PIT8253_H

#include <stdint.h>

typedef struct {
    uint32_t divisor;
    uint32_t counter;
    uint64_t ticks;
} a5vm_pit8253;

void a5vm_pit8253_init(a5vm_pit8253 *pit, uint32_t divisor);
uint32_t a5vm_pit8253_tick(a5vm_pit8253 *pit, uint32_t cycles);

#endif

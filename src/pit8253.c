#include "a5vm/pit8253.h"

#define A5VM_PIT8253_DEFAULT_DIVISOR 65536u

void a5vm_pit8253_init(a5vm_pit8253 *pit, uint32_t divisor) {
    pit->divisor = divisor == 0 ? A5VM_PIT8253_DEFAULT_DIVISOR : divisor;
    pit->counter = 0;
    pit->ticks = 0;
}

uint32_t a5vm_pit8253_tick(a5vm_pit8253 *pit, uint32_t cycles) {
    uint64_t total = (uint64_t)pit->counter + cycles;
    uint64_t pulses = total / pit->divisor;
    pit->counter = (uint32_t)(total % pit->divisor);
    pit->ticks += pulses;
    return pulses > UINT32_MAX ? UINT32_MAX : (uint32_t)pulses;
}

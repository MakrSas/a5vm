#include "a5vm/memory.h"

#include <string.h>

static uint32_t normalize_address(uint32_t address) {
    return address & A5VM_ADDRESS_MASK;
}

void a5vm_memory_init(a5vm_memory *memory) {
    memset(memory->bytes, 0, sizeof(memory->bytes));
}

uint8_t a5vm_memory_read8(const a5vm_memory *memory, uint32_t address) {
    return memory->bytes[normalize_address(address)];
}

uint16_t a5vm_memory_read16(const a5vm_memory *memory, uint32_t address) {
    uint8_t low = a5vm_memory_read8(memory, address);
    uint8_t high = a5vm_memory_read8(memory, address + 1u);
    return (uint16_t)(low | ((uint16_t)high << 8));
}

void a5vm_memory_write8(a5vm_memory *memory, uint32_t address, uint8_t value) {
    memory->bytes[normalize_address(address)] = value;
}

void a5vm_memory_write16(a5vm_memory *memory, uint32_t address, uint16_t value) {
    a5vm_memory_write8(memory, address, (uint8_t)value);
    a5vm_memory_write8(memory, address + 1u, (uint8_t)(value >> 8));
}

void a5vm_memory_load(a5vm_memory *memory, uint32_t address,
                      const uint8_t *data, size_t length) {
    size_t i;
    for (i = 0; i < length; ++i) {
        a5vm_memory_write8(memory, address + (uint32_t)i, data[i]);
    }
}

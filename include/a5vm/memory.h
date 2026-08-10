#ifndef A5VM_MEMORY_H
#define A5VM_MEMORY_H

#include <stddef.h>
#include <stdint.h>

#define A5VM_MEMORY_SIZE (1024u * 1024u)
#define A5VM_ADDRESS_MASK 0xFFFFFu

typedef struct {
    uint8_t bytes[A5VM_MEMORY_SIZE];
} a5vm_memory;

void a5vm_memory_init(a5vm_memory *memory);
uint8_t a5vm_memory_read8(const a5vm_memory *memory, uint32_t address);
uint16_t a5vm_memory_read16(const a5vm_memory *memory, uint32_t address);
void a5vm_memory_write8(a5vm_memory *memory, uint32_t address, uint8_t value);
void a5vm_memory_write16(a5vm_memory *memory, uint32_t address, uint16_t value);
void a5vm_memory_load(a5vm_memory *memory, uint32_t address,
                      const uint8_t *data, size_t length);

#endif

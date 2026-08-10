#ifndef A5VM_PIC8259_H
#define A5VM_PIC8259_H

#include <stdint.h>

#define A5VM_PIC8259_IRQ_COUNT 8u

typedef struct {
    uint8_t vector_offset;
    uint8_t mask;
    uint8_t pending;
} a5vm_pic8259;

void a5vm_pic8259_init(a5vm_pic8259 *pic, uint8_t vector_offset);
void a5vm_pic8259_set_mask(a5vm_pic8259 *pic, unsigned irq, int enabled);
void a5vm_pic8259_raise(a5vm_pic8259 *pic, unsigned irq);
int a5vm_pic8259_has_pending(const a5vm_pic8259 *pic);
int a5vm_pic8259_acknowledge(a5vm_pic8259 *pic, uint8_t *vector);

#endif

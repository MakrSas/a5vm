#include "a5vm/pic8259.h"

void a5vm_pic8259_init(a5vm_pic8259 *pic, uint8_t vector_offset) {
    pic->vector_offset = vector_offset;
    pic->mask = 0xFF;
    pic->pending = 0;
}

void a5vm_pic8259_set_mask(a5vm_pic8259 *pic, unsigned irq, int enabled) {
    if (irq >= A5VM_PIC8259_IRQ_COUNT) return;
    if (enabled) {
        pic->mask = (uint8_t)(pic->mask & (uint8_t)~(1u << irq));
    } else {
        pic->mask = (uint8_t)(pic->mask | (uint8_t)(1u << irq));
    }
}

void a5vm_pic8259_raise(a5vm_pic8259 *pic, unsigned irq) {
    if (irq >= A5VM_PIC8259_IRQ_COUNT) return;
    pic->pending = (uint8_t)(pic->pending | (uint8_t)(1u << irq));
}

int a5vm_pic8259_has_pending(const a5vm_pic8259 *pic) {
    return (pic->pending & (uint8_t)~pic->mask) != 0;
}

int a5vm_pic8259_acknowledge(a5vm_pic8259 *pic, uint8_t *vector) {
    unsigned irq;
    uint8_t ready = (uint8_t)(pic->pending & (uint8_t)~pic->mask);

    if (ready == 0) return 0;
    for (irq = 0; irq < A5VM_PIC8259_IRQ_COUNT; ++irq) {
        if ((ready & (uint8_t)(1u << irq)) != 0) {
            pic->pending = (uint8_t)(pic->pending & (uint8_t)~(1u << irq));
            *vector = (uint8_t)(pic->vector_offset + irq);
            return 1;
        }
    }
    return 0;
}

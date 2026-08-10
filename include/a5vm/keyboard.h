#ifndef A5VM_KEYBOARD_H
#define A5VM_KEYBOARD_H

#include <stdint.h>

#define A5VM_KEYBOARD_CAPACITY 64u

typedef struct {
    uint8_t bytes[A5VM_KEYBOARD_CAPACITY];
    uint8_t read_index;
    uint8_t write_index;
    uint8_t count;
} a5vm_keyboard;

void a5vm_keyboard_init(a5vm_keyboard *keyboard);
int a5vm_keyboard_push(a5vm_keyboard *keyboard, uint8_t value);
int a5vm_keyboard_pop(a5vm_keyboard *keyboard, uint8_t *value);
int a5vm_keyboard_empty(const a5vm_keyboard *keyboard);

#endif

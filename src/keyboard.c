#include "a5vm/keyboard.h"

void a5vm_keyboard_init(a5vm_keyboard *keyboard) {
    keyboard->read_index = 0;
    keyboard->write_index = 0;
    keyboard->count = 0;
}

int a5vm_keyboard_push(a5vm_keyboard *keyboard, uint8_t value) {
    if (keyboard->count >= A5VM_KEYBOARD_CAPACITY) return 0;
    keyboard->bytes[keyboard->write_index] = value;
    keyboard->write_index = (uint8_t)((keyboard->write_index + 1u) % A5VM_KEYBOARD_CAPACITY);
    keyboard->count++;
    return 1;
}

int a5vm_keyboard_pop(a5vm_keyboard *keyboard, uint8_t *value) {
    if (keyboard->count == 0) return 0;
    *value = keyboard->bytes[keyboard->read_index];
    keyboard->read_index = (uint8_t)((keyboard->read_index + 1u) % A5VM_KEYBOARD_CAPACITY);
    keyboard->count--;
    return 1;
}

int a5vm_keyboard_empty(const a5vm_keyboard *keyboard) {
    return keyboard->count == 0;
}

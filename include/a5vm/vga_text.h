#ifndef A5VM_VGA_TEXT_H
#define A5VM_VGA_TEXT_H

#include <stddef.h>
#include <stdint.h>

#define A5VM_VGA_TEXT_COLUMNS 80u
#define A5VM_VGA_TEXT_ROWS 25u
#define A5VM_VGA_TEXT_CELL_BYTES 2u
#define A5VM_VGA_TEXT_BUFFER_SIZE \
    (A5VM_VGA_TEXT_COLUMNS * A5VM_VGA_TEXT_ROWS * A5VM_VGA_TEXT_CELL_BYTES)

typedef struct {
    uint8_t cells[A5VM_VGA_TEXT_BUFFER_SIZE];
    uint8_t cursor_column;
    uint8_t cursor_row;
    uint8_t attribute;
} a5vm_vga_text;

void a5vm_vga_text_init(a5vm_vga_text *vga);
void a5vm_vga_text_clear(a5vm_vga_text *vga);
void a5vm_vga_text_putc(a5vm_vga_text *vga, uint8_t value);
void a5vm_vga_text_write(a5vm_vga_text *vga, const char *text);
const uint8_t *a5vm_vga_text_cells(const a5vm_vga_text *vga);

#endif

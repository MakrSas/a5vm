#include "a5vm/vga_text.h"

static size_t cell_offset(unsigned column, unsigned row) {
    return (row * A5VM_VGA_TEXT_COLUMNS + column) * A5VM_VGA_TEXT_CELL_BYTES;
}

void a5vm_vga_text_clear(a5vm_vga_text *vga) {
    unsigned row;
    unsigned column;
    for (row = 0; row < A5VM_VGA_TEXT_ROWS; ++row) {
        for (column = 0; column < A5VM_VGA_TEXT_COLUMNS; ++column) {
            size_t offset = cell_offset(column, row);
            vga->cells[offset] = ' ';
            vga->cells[offset + 1u] = vga->attribute;
        }
    }
    vga->cursor_column = 0;
    vga->cursor_row = 0;
}

void a5vm_vga_text_init(a5vm_vga_text *vga) {
    vga->attribute = 0x07;
    a5vm_vga_text_clear(vga);
}

static void scroll(a5vm_vga_text *vga) {
    unsigned row;
    unsigned column;
    for (row = 1; row < A5VM_VGA_TEXT_ROWS; ++row) {
        for (column = 0; column < A5VM_VGA_TEXT_COLUMNS; ++column) {
            size_t source = cell_offset(column, row);
            size_t target = cell_offset(column, row - 1u);
            vga->cells[target] = vga->cells[source];
            vga->cells[target + 1u] = vga->cells[source + 1u];
        }
    }
    for (column = 0; column < A5VM_VGA_TEXT_COLUMNS; ++column) {
        size_t offset = cell_offset(column, A5VM_VGA_TEXT_ROWS - 1u);
        vga->cells[offset] = ' ';
        vga->cells[offset + 1u] = vga->attribute;
    }
    vga->cursor_row = A5VM_VGA_TEXT_ROWS - 1u;
}

void a5vm_vga_text_putc(a5vm_vga_text *vga, uint8_t value) {
    if (value == '\r') {
        vga->cursor_column = 0;
        return;
    }
    if (value == '\n') {
        vga->cursor_column = 0;
        vga->cursor_row++;
        if (vga->cursor_row >= A5VM_VGA_TEXT_ROWS) scroll(vga);
        return;
    }
    if (value == '\b') {
        if (vga->cursor_column > 0) vga->cursor_column--;
        return;
    }
    if (vga->cursor_column >= A5VM_VGA_TEXT_COLUMNS) {
        vga->cursor_column = 0;
        vga->cursor_row++;
        if (vga->cursor_row >= A5VM_VGA_TEXT_ROWS) scroll(vga);
    }
    {
        size_t offset = cell_offset(vga->cursor_column, vga->cursor_row);
        vga->cells[offset] = value;
        vga->cells[offset + 1u] = vga->attribute;
    }
    vga->cursor_column++;
}

void a5vm_vga_text_write(a5vm_vga_text *vga, const char *text) {
    while (*text != '\0') a5vm_vga_text_putc(vga, (uint8_t)*text++);
}

const uint8_t *a5vm_vga_text_cells(const a5vm_vga_text *vga) {
    return vga->cells;
}

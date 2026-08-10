#ifndef A5VM_FLOPPY_H
#define A5VM_FLOPPY_H

#include <stddef.h>
#include <stdint.h>

#define A5VM_FLOPPY_SECTOR_SIZE 512u
#define A5VM_FLOPPY_SECTOR_COUNT 2880u
#define A5VM_FLOPPY_IMAGE_SIZE \
    (A5VM_FLOPPY_SECTOR_SIZE * A5VM_FLOPPY_SECTOR_COUNT)

typedef struct {
    uint8_t *bytes;
    size_t size;
} a5vm_floppy;

int a5vm_floppy_init(a5vm_floppy *floppy, size_t size);
void a5vm_floppy_deinit(a5vm_floppy *floppy);
int a5vm_floppy_read_sector(const a5vm_floppy *floppy,
                            unsigned sector, uint8_t *buffer);
int a5vm_floppy_write_sector(a5vm_floppy *floppy,
                             unsigned sector, const uint8_t *buffer);
void a5vm_floppy_create_demo(a5vm_floppy *floppy);

#endif

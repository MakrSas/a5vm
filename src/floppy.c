#include "a5vm/floppy.h"

#include <stdlib.h>
#include <string.h>

int a5vm_floppy_init(a5vm_floppy *floppy, size_t size) {
    if (size == 0) size = A5VM_FLOPPY_IMAGE_SIZE;
    floppy->bytes = (uint8_t *)calloc(1, size);
    if (!floppy->bytes) {
        floppy->size = 0;
        return 0;
    }
    floppy->size = size;
    return 1;
}

void a5vm_floppy_deinit(a5vm_floppy *floppy) {
    free(floppy->bytes);
    floppy->bytes = NULL;
    floppy->size = 0;
}

static int valid_sector(const a5vm_floppy *floppy, unsigned sector) {
    size_t offset = (size_t)sector * A5VM_FLOPPY_SECTOR_SIZE;
    return floppy->bytes != NULL &&
           offset + A5VM_FLOPPY_SECTOR_SIZE <= floppy->size;
}

int a5vm_floppy_read_sector(const a5vm_floppy *floppy,
                            unsigned sector, uint8_t *buffer) {
    if (!buffer || !valid_sector(floppy, sector)) return 0;
    memcpy(buffer, floppy->bytes + (size_t)sector * A5VM_FLOPPY_SECTOR_SIZE,
           A5VM_FLOPPY_SECTOR_SIZE);
    return 1;
}

int a5vm_floppy_write_sector(a5vm_floppy *floppy,
                             unsigned sector, const uint8_t *buffer) {
    if (!buffer || !valid_sector(floppy, sector)) return 0;
    memcpy(floppy->bytes + (size_t)sector * A5VM_FLOPPY_SECTOR_SIZE, buffer,
           A5VM_FLOPPY_SECTOR_SIZE);
    return 1;
}

void a5vm_floppy_create_demo(a5vm_floppy *floppy) {
    static const uint8_t boot_code[] = {
        0xB8, 0x02, 0x00,       /* mov ax, 2 */
        0xBB, 0x03, 0x00,       /* mov bx, 3 */
        0x01, 0xD8,             /* add ax, bx */
        0xF4                    /* hlt */
    };
    uint8_t *sector;
    if (!valid_sector(floppy, 0)) return;
    sector = floppy->bytes;
    memset(sector, 0, A5VM_FLOPPY_SECTOR_SIZE);
    memcpy(sector, boot_code, sizeof(boot_code));
    sector[510] = 0x55;
    sector[511] = 0xAA;
}

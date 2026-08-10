#include "a5vm/disk.h"

#include <stdlib.h>
#include <string.h>

int a5vm_disk_init(a5vm_disk *disk, size_t size) {
    disk->bytes = NULL;
    disk->size = 0;
    if (size == 0) size = A5VM_DISK_IMAGE_SIZE;
    if (size < A5VM_DISK_SECTOR_SIZE ||
        (size % A5VM_DISK_SECTOR_SIZE) != 0) {
        disk->bytes = NULL;
        disk->size = 0;
        return 0;
    }
    disk->bytes = (uint8_t *)calloc(1, size);
    if (!disk->bytes) {
        disk->size = 0;
        return 0;
    }
    disk->size = size;
    return 1;
}

void a5vm_disk_deinit(a5vm_disk *disk) {
    free(disk->bytes);
    disk->bytes = NULL;
    disk->size = 0;
}

static int valid_sector(const a5vm_disk *disk, uint32_t sector) {
    return disk->bytes != NULL &&
           sector < disk->size / A5VM_DISK_SECTOR_SIZE;
}

int a5vm_disk_read_sector(const a5vm_disk *disk, uint32_t sector,
                          uint8_t *buffer) {
    if (!buffer || !valid_sector(disk, sector)) return 0;
    memcpy(buffer, disk->bytes + (size_t)sector * A5VM_DISK_SECTOR_SIZE,
           A5VM_DISK_SECTOR_SIZE);
    return 1;
}

int a5vm_disk_write_sector(a5vm_disk *disk, uint32_t sector,
                           const uint8_t *buffer) {
    if (!buffer || !valid_sector(disk, sector)) return 0;
    memcpy(disk->bytes + (size_t)sector * A5VM_DISK_SECTOR_SIZE,
           buffer, A5VM_DISK_SECTOR_SIZE);
    return 1;
}

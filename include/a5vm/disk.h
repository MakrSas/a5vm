#ifndef A5VM_DISK_H
#define A5VM_DISK_H

#include <stddef.h>
#include <stdint.h>

#define A5VM_DISK_SECTOR_SIZE 512u
#define A5VM_DISK_IMAGE_SIZE (16u * 1024u * 1024u)

typedef struct {
    uint8_t *bytes;
    size_t size;
} a5vm_disk;

int a5vm_disk_init(a5vm_disk *disk, size_t size);
void a5vm_disk_deinit(a5vm_disk *disk);
int a5vm_disk_read_sector(const a5vm_disk *disk, uint32_t sector,
                          uint8_t *buffer);
int a5vm_disk_write_sector(a5vm_disk *disk, uint32_t sector,
                           const uint8_t *buffer);

#endif

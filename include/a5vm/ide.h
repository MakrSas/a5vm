#ifndef A5VM_IDE_H
#define A5VM_IDE_H

#include <stdint.h>

#include "a5vm/disk.h"

#define A5VM_IDE_DATA_PORT 0x1F0u
#define A5VM_IDE_SECTOR_COUNT_PORT 0x1F2u
#define A5VM_IDE_LBA_LOW_PORT 0x1F3u
#define A5VM_IDE_LBA_MID_PORT 0x1F4u
#define A5VM_IDE_LBA_HIGH_PORT 0x1F5u
#define A5VM_IDE_DRIVE_HEAD_PORT 0x1F6u
#define A5VM_IDE_STATUS_COMMAND_PORT 0x1F7u

typedef struct {
    a5vm_disk *disk;
    uint8_t sector_count;
    uint8_t lba_low;
    uint8_t lba_mid;
    uint8_t lba_high;
    uint8_t drive_head;
    uint8_t status;
    uint8_t error;
    uint8_t buffer[A5VM_DISK_SECTOR_SIZE];
    unsigned data_index;
    int write_command;
} a5vm_ide;

void a5vm_ide_init(a5vm_ide *ide, a5vm_disk *disk);
void a5vm_ide_reset(a5vm_ide *ide);
int a5vm_ide_read8(a5vm_ide *ide, uint16_t port, uint8_t *value);
int a5vm_ide_write8(a5vm_ide *ide, uint16_t port, uint8_t value);

#endif

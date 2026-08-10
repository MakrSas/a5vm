#include "a5vm/ide.h"

#include <string.h>

#define A5VM_IDE_STATUS_READY 0x40u
#define A5VM_IDE_STATUS_DRQ 0x08u
#define A5VM_IDE_STATUS_ERROR 0x01u
#define A5VM_IDE_COMMAND_READ 0x20u
#define A5VM_IDE_COMMAND_WRITE 0x30u

void a5vm_ide_init(a5vm_ide *ide, a5vm_disk *disk) {
    memset(ide, 0, sizeof(*ide));
    ide->disk = disk;
    a5vm_ide_reset(ide);
}

void a5vm_ide_reset(a5vm_ide *ide) {
    ide->sector_count = 0;
    ide->lba_low = 0;
    ide->lba_mid = 0;
    ide->lba_high = 0;
    ide->drive_head = 0xE0;
    ide->status = A5VM_IDE_STATUS_READY;
    ide->error = 0;
    ide->data_index = 0;
    ide->write_command = 0;
}

static uint32_t current_lba(const a5vm_ide *ide) {
    return (uint32_t)ide->lba_low |
           ((uint32_t)ide->lba_mid << 8) |
           ((uint32_t)ide->lba_high << 16) |
           ((uint32_t)(ide->drive_head & 0x0Fu) << 24);
}

static void set_error(a5vm_ide *ide) {
    ide->status = (uint8_t)(A5VM_IDE_STATUS_READY | A5VM_IDE_STATUS_ERROR);
    ide->error = 0x04;
    ide->data_index = 0;
}

static void execute_command(a5vm_ide *ide, uint8_t command) {
    uint32_t lba = current_lba(ide);
    if (ide->sector_count != 1 || (ide->drive_head & 0x10u) != 0 ||
        !ide->disk || lba >= ide->disk->size / A5VM_DISK_SECTOR_SIZE) {
        set_error(ide);
        return;
    }
    if (command == A5VM_IDE_COMMAND_READ) {
        if (!a5vm_disk_read_sector(ide->disk, lba, ide->buffer)) {
            set_error(ide);
            return;
        }
        ide->write_command = 0;
    } else if (command == A5VM_IDE_COMMAND_WRITE) {
        ide->write_command = 1;
    } else {
        set_error(ide);
        return;
    }
    ide->data_index = 0;
    ide->error = 0;
    ide->status = (uint8_t)(A5VM_IDE_STATUS_READY | A5VM_IDE_STATUS_DRQ);
}

int a5vm_ide_read8(a5vm_ide *ide, uint16_t port, uint8_t *value) {
    if (port == A5VM_IDE_DATA_PORT) {
        if ((ide->status & A5VM_IDE_STATUS_DRQ) == 0 ||
            ide->data_index >= A5VM_DISK_SECTOR_SIZE) {
            *value = 0xFF;
            return 1;
        }
        *value = ide->buffer[ide->data_index++];
        if (ide->data_index == A5VM_DISK_SECTOR_SIZE) {
            ide->status = A5VM_IDE_STATUS_READY;
        }
        return 1;
    }
    if (port == A5VM_IDE_SECTOR_COUNT_PORT) {
        *value = ide->sector_count;
        return 1;
    }
    if (port == A5VM_IDE_LBA_LOW_PORT) {
        *value = ide->lba_low;
        return 1;
    }
    if (port == A5VM_IDE_LBA_MID_PORT) {
        *value = ide->lba_mid;
        return 1;
    }
    if (port == A5VM_IDE_LBA_HIGH_PORT) {
        *value = ide->lba_high;
        return 1;
    }
    if (port == A5VM_IDE_DRIVE_HEAD_PORT) {
        *value = ide->drive_head;
        return 1;
    }
    if (port == A5VM_IDE_STATUS_COMMAND_PORT) {
        *value = ide->status;
        return 1;
    }
    return 0;
}

int a5vm_ide_write8(a5vm_ide *ide, uint16_t port, uint8_t value) {
    if (port == A5VM_IDE_DATA_PORT) {
        if ((ide->status & A5VM_IDE_STATUS_DRQ) == 0 ||
            !ide->write_command || ide->data_index >= A5VM_DISK_SECTOR_SIZE) {
            return 1;
        }
        ide->buffer[ide->data_index++] = value;
        if (ide->data_index == A5VM_DISK_SECTOR_SIZE) {
            if (!a5vm_disk_write_sector(ide->disk, current_lba(ide), ide->buffer)) {
                set_error(ide);
            } else {
                ide->status = A5VM_IDE_STATUS_READY;
            }
        }
        return 1;
    }
    if (port == A5VM_IDE_SECTOR_COUNT_PORT) {
        ide->sector_count = value;
        return 1;
    }
    if (port == A5VM_IDE_LBA_LOW_PORT) {
        ide->lba_low = value;
        return 1;
    }
    if (port == A5VM_IDE_LBA_MID_PORT) {
        ide->lba_mid = value;
        return 1;
    }
    if (port == A5VM_IDE_LBA_HIGH_PORT) {
        ide->lba_high = value;
        return 1;
    }
    if (port == A5VM_IDE_DRIVE_HEAD_PORT) {
        ide->drive_head = value;
        return 1;
    }
    if (port == A5VM_IDE_STATUS_COMMAND_PORT) {
        execute_command(ide, value);
        return 1;
    }
    return 0;
}

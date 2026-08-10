#include "a5vm/cpu386.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    uint8_t mod;
    uint8_t reg;
    uint8_t rm;
    uint32_t displacement;
} modrm386;

static void faultf(a5vm_cpu386 *cpu, a5vm_cpu_status status,
                   const char *format, ...) {
    va_list args;
    cpu->status = status;
    va_start(args, format);
    vsnprintf(cpu->fault, sizeof(cpu->fault), format, args);
    va_end(args);
}

static uint16_t read16(const a5vm_cpu386 *cpu, uint32_t address) {
    return a5vm_memory_read16(cpu->memory, address);
}

static uint32_t read32(const a5vm_cpu386 *cpu, uint32_t address) {
    return (uint32_t)read16(cpu, address) |
           ((uint32_t)read16(cpu, address + 2u) << 16);
}

static void write32(a5vm_cpu386 *cpu, uint32_t address, uint32_t value) {
    a5vm_memory_write16(cpu->memory, address, (uint16_t)value);
    a5vm_memory_write16(cpu->memory, address + 2u, (uint16_t)(value >> 16));
}

static void set_flag(a5vm_cpu386 *cpu, uint32_t flag, int value) {
    if (value) cpu->eflags |= flag;
    else cpu->eflags &= ~flag;
}

static void update_flags(a5vm_cpu386 *cpu, uint32_t value, int operand32) {
    uint32_t mask = operand32 ? 0xFFFFFFFFu : 0xFFFFu;
    uint32_t sign = operand32 ? 0x80000000u : 0x8000u;
    value &= mask;
    set_flag(cpu, A5VM_FLAG_ZF, value == 0);
    set_flag(cpu, A5VM_FLAG_SF, (value & sign) != 0);
}

static uint32_t add_value(a5vm_cpu386 *cpu, uint32_t left, uint32_t right,
                          int operand32) {
    uint64_t result = (uint64_t)left + right;
    uint32_t mask = operand32 ? 0xFFFFFFFFu : 0xFFFFu;
    uint32_t value = (uint32_t)result & mask;
    set_flag(cpu, A5VM_FLAG_CF, result > mask);
    update_flags(cpu, value, operand32);
    return value;
}

static uint32_t sub_value(a5vm_cpu386 *cpu, uint32_t left, uint32_t right,
                          int operand32) {
    uint32_t mask = operand32 ? 0xFFFFFFFFu : 0xFFFFu;
    uint32_t value = (left - right) & mask;
    set_flag(cpu, A5VM_FLAG_CF, (left & mask) < (right & mask));
    update_flags(cpu, value, operand32);
    return value;
}

static int descriptor(const a5vm_cpu386 *cpu, uint16_t selector,
                      uint32_t *base, uint32_t *limit, int *default32,
                      uint8_t *access) {
    uint32_t address;
    uint32_t low;
    uint32_t high;
    if ((selector & 0xFFF8u) == 0 ||
        (uint32_t)(selector & 0xFFF8u) + 7u > cpu->gdtr_limit) return 0;
    address = cpu->gdtr_base + (selector & 0xFFF8u);
    low = read32(cpu, address);
    high = read32(cpu, address + 4u);
    *base = ((low >> 16) & 0xFFFFu) |
            ((high & 0xFFu) << 16) | ((high >> 24) << 24);
    *limit = (low & 0xFFFFu) | (high & 0x000F0000u);
    if ((high & 0x00800000u) != 0) *limit = (*limit << 12) | 0xFFFu;
    *default32 = (high & 0x00400000u) != 0;
    *access = (uint8_t)(high >> 8);
    return (*access & 0x80u) != 0 && (*access & 0x10u) != 0;
}

uint32_t a5vm_cpu386_linear_address(const a5vm_cpu386 *cpu,
                                    unsigned segment, uint32_t offset) {
    if (!cpu->protected_mode) {
        return ((((uint32_t)cpu->segs[segment] << 4) + offset) &
                A5VM_ADDRESS_MASK);
    }
    return (cpu->segment_bases[segment] + offset) & A5VM_ADDRESS_MASK;
}

static uint32_t checked_linear_address(a5vm_cpu386 *cpu, unsigned segment,
                                       uint32_t offset) {
    uint32_t address = a5vm_cpu386_linear_address(cpu, segment, offset);
    uint64_t physical = (uint64_t)cpu->segment_bases[segment] + offset;
    if (cpu->protected_mode && offset > cpu->segment_limits[segment]) {
        faultf(cpu, A5VM_CPU_FAULT,
               "segment %u limit exceeded at offset %08X", segment, offset);
        return 0;
    }
    if (cpu->protected_mode && physical > A5VM_ADDRESS_MASK) {
        faultf(cpu, A5VM_CPU_FAULT,
               "i386 address exceeds available memory at %08X", offset);
        return 0;
    }
    return address;
}

static uint8_t fetch8(a5vm_cpu386 *cpu) {
    uint32_t address = checked_linear_address(cpu, A5VM_CPU386_SEG_CS,
                                              cpu->eip);
    uint8_t value = a5vm_memory_read8(cpu->memory, address);
    cpu->eip++;
    return value;
}

static uint16_t fetch16(a5vm_cpu386 *cpu) {
    uint16_t low = fetch8(cpu);
    return (uint16_t)(low | ((uint16_t)fetch8(cpu) << 8));
}

static uint32_t fetch32(a5vm_cpu386 *cpu) {
    return (uint32_t)fetch16(cpu) | ((uint32_t)fetch16(cpu) << 16);
}

static int decode_modrm(a5vm_cpu386 *cpu, modrm386 *m, int address32) {
    uint8_t value = fetch8(cpu);
    m->mod = value >> 6;
    m->reg = (value >> 3) & 7u;
    m->rm = value & 7u;
    m->displacement = 0;
    if (m->mod == 3) return 1;
    if (!address32 && m->mod == 0 && m->rm == 6) {
        m->displacement = fetch16(cpu);
        return 1;
    }
    if (address32 && m->mod == 0 && m->rm == 5) {
        m->displacement = fetch32(cpu);
        return 1;
    }
    faultf(cpu, A5VM_CPU_UNIMPLEMENTED, "i386 addressing mode mod=%u rm=%u",
           m->mod, m->rm);
    return 0;
}

static uint32_t memory_address(a5vm_cpu386 *cpu, const modrm386 *m,
                               int address32) {
    (void)address32;
    if (m->mod == 0) return checked_linear_address(cpu, A5VM_CPU386_SEG_DS,
                                                   m->displacement);
    return 0;
}

static int load_segment(a5vm_cpu386 *cpu, unsigned segment, uint16_t selector) {
    uint32_t base;
    uint32_t limit;
    int default32;
    uint8_t access;
    if (!cpu->protected_mode) {
        cpu->segs[segment] = selector;
        cpu->segment_bases[segment] = (uint32_t)selector << 4;
        cpu->segment_limits[segment] = 0xFFFF;
        cpu->segment_access[segment] = 0;
        return 1;
    }
    if (segment == A5VM_CPU386_SEG_CS ||
        !descriptor(cpu, selector, &base, &limit, &default32, &access) ||
        (access & 0x08u) != 0) {
        return 0;
    }
    (void)default32;
    cpu->segs[segment] = selector;
    cpu->segment_bases[segment] = base;
    cpu->segment_limits[segment] = limit;
    cpu->segment_access[segment] = access;
    return 1;
}

void a5vm_cpu386_init(a5vm_cpu386 *cpu, a5vm_memory *memory) {
    memset(cpu, 0, sizeof(*cpu));
    cpu->memory = memory;
    a5vm_cpu386_reset(cpu);
}

void a5vm_cpu386_set_interrupt_handler(a5vm_cpu386 *cpu,
                                        a5vm_cpu386_interrupt_handler handler,
                                        void *context) {
    cpu->interrupt_handler = handler;
    cpu->interrupt_context = context;
}

void a5vm_cpu386_set_io_handlers(a5vm_cpu386 *cpu,
                                 a5vm_cpu386_io_read8_handler read8,
                                 a5vm_cpu386_io_write8_handler write8,
                                 void *context) {
    cpu->io_read8 = read8;
    cpu->io_write8 = write8;
    cpu->io_context = context;
}

void a5vm_cpu386_reset(a5vm_cpu386 *cpu) {
    memset(cpu->regs, 0, sizeof(cpu->regs));
    memset(cpu->segs, 0, sizeof(cpu->segs));
    cpu->segs[A5VM_CPU386_SEG_CS] = 0xF000;
    cpu->eip = 0xFFF0;
    cpu->eflags = 0x00000002u;
    cpu->cr0 = 0;
    cpu->steps = 0;
    cpu->gdtr_base = 0;
    cpu->gdtr_limit = 0;
    memset(cpu->segment_bases, 0, sizeof(cpu->segment_bases));
    memset(cpu->segment_limits, 0, sizeof(cpu->segment_limits));
    memset(cpu->segment_access, 0, sizeof(cpu->segment_access));
    cpu->segment_bases[A5VM_CPU386_SEG_CS] = 0xF0000;
    for (unsigned index = 0; index < A5VM_CPU386_SEG_COUNT; ++index) {
        cpu->segment_limits[index] = 0xFFFFF;
    }
    cpu->protected_mode = 0;
    cpu->default_operand_size32 = 0;
    cpu->status = A5VM_CPU_RUNNING;
    cpu->fault[0] = '\0';
}

const char *a5vm_cpu386_fault(const a5vm_cpu386 *cpu) {
    return cpu->fault;
}

a5vm_cpu_status a5vm_cpu386_step(a5vm_cpu386 *cpu) {
    uint8_t opcode;
    int operand32;
    modrm386 m;
    if (cpu->status != A5VM_CPU_RUNNING) return cpu->status;
    operand32 = cpu->default_operand_size32;
    opcode = fetch8(cpu);
    cpu->steps++;
    if (opcode == 0x66) {
        operand32 = !operand32;
        opcode = fetch8(cpu);
    }
    if (opcode == 0x90) return cpu->status;
    if (opcode == 0xF4) {
        cpu->status = A5VM_CPU_HALTED;
        return cpu->status;
    }
    if (opcode == 0xFA) {
        cpu->eflags &= ~((uint32_t)A5VM_FLAG_IF);
        return cpu->status;
    }
    if (opcode == 0xFB) {
        cpu->eflags |= A5VM_FLAG_IF;
        return cpu->status;
    }
    if (opcode >= 0xB0 && opcode <= 0xB7) {
        unsigned reg = opcode - 0xB0u;
        uint8_t value = fetch8(cpu);
        if (reg < 4) cpu->regs[reg] = (cpu->regs[reg] & 0xFFFFFF00u) | value;
        else {
            reg -= 4;
            cpu->regs[reg] = (cpu->regs[reg] & 0xFFFF00FFu) |
                ((uint32_t)value << 8);
        }
        return cpu->status;
    }
    if (opcode == 0xE4 || opcode == 0xE5 || opcode == 0xE6 || opcode == 0xE7 ||
        opcode == 0xEC || opcode == 0xED || opcode == 0xEE || opcode == 0xEF) {
        uint16_t port = (opcode >= 0xEC) ? (uint16_t)cpu->regs[A5VM_CPU386_REG_EDX]
                                         : fetch8(cpu);
        uint8_t low;
        uint8_t high;
        if ((opcode == 0xE4 || opcode == 0xE5 || opcode == 0xEC || opcode == 0xED) &&
            !cpu->io_read8) {
            faultf(cpu, A5VM_CPU_UNIMPLEMENTED,
                   "IN from port 0x%04X has no device", port);
            return cpu->status;
        }
        if ((opcode == 0xE6 || opcode == 0xE7 || opcode == 0xEE || opcode == 0xEF) &&
            !cpu->io_write8) {
            faultf(cpu, A5VM_CPU_UNIMPLEMENTED,
                   "OUT to port 0x%04X has no device", port);
            return cpu->status;
        }
        if (opcode == 0xE4 || opcode == 0xEC) {
            cpu->regs[A5VM_CPU386_REG_EAX] =
                (cpu->regs[A5VM_CPU386_REG_EAX] & 0xFFFFFF00u) |
                cpu->io_read8(cpu, port, cpu->io_context);
        } else if (opcode == 0xE5 || opcode == 0xED) {
            low = cpu->io_read8(cpu, port, cpu->io_context);
            high = cpu->io_read8(cpu, port, cpu->io_context);
            cpu->regs[A5VM_CPU386_REG_EAX] = low | ((uint32_t)high << 8);
        } else if (opcode == 0xE6 || opcode == 0xEE) {
            cpu->io_write8(cpu, port,
                           (uint8_t)cpu->regs[A5VM_CPU386_REG_EAX],
                           cpu->io_context);
        } else {
            cpu->io_write8(cpu, port,
                           (uint8_t)cpu->regs[A5VM_CPU386_REG_EAX],
                           cpu->io_context);
            cpu->io_write8(cpu, port,
                           (uint8_t)(cpu->regs[A5VM_CPU386_REG_EAX] >> 8),
                           cpu->io_context);
        }
        return cpu->status;
    }
    if (opcode >= 0xB8 && opcode <= 0xBF) {
        unsigned reg = opcode - 0xB8u;
        if (operand32) cpu->regs[reg] = fetch32(cpu);
        else cpu->regs[reg] = (cpu->regs[reg] & 0xFFFF0000u) | fetch16(cpu);
        return cpu->status;
    }
    if (opcode >= 0x40 && opcode <= 0x47) {
        unsigned reg = opcode - 0x40u;
        if (operand32) cpu->regs[reg] = add_value(cpu, cpu->regs[reg], 1, 1);
        else cpu->regs[reg] = (cpu->regs[reg] & 0xFFFF0000u) |
            add_value(cpu, cpu->regs[reg], 1, 0);
        return cpu->status;
    }
    if (opcode >= 0x48 && opcode <= 0x4F) {
        unsigned reg = opcode - 0x48u;
        if (operand32) cpu->regs[reg] = sub_value(cpu, cpu->regs[reg], 1, 1);
        else cpu->regs[reg] = (cpu->regs[reg] & 0xFFFF0000u) |
            sub_value(cpu, cpu->regs[reg], 1, 0);
        return cpu->status;
    }
    if (opcode == 0x05) {
        if (operand32) cpu->regs[A5VM_CPU386_REG_EAX] =
            add_value(cpu, cpu->regs[A5VM_CPU386_REG_EAX], fetch32(cpu), 1);
        else cpu->regs[A5VM_CPU386_REG_EAX] =
            (cpu->regs[A5VM_CPU386_REG_EAX] & 0xFFFF0000u) |
            add_value(cpu, cpu->regs[A5VM_CPU386_REG_EAX], fetch16(cpu), 0);
        return cpu->status;
    }
    if (opcode == 0x3D) {
        if (operand32) (void)sub_value(cpu, cpu->regs[A5VM_CPU386_REG_EAX], fetch32(cpu), 1);
        else (void)sub_value(cpu, cpu->regs[A5VM_CPU386_REG_EAX], fetch16(cpu), 0);
        return cpu->status;
    }
    if (opcode == 0x8E) {
        if (!decode_modrm(cpu, &m, cpu->default_operand_size32)) return cpu->status;
        if (m.mod != 3 || m.reg >= A5VM_CPU386_SEG_COUNT || m.reg == A5VM_CPU386_SEG_CS ||
            !load_segment(cpu, m.reg, (uint16_t)cpu->regs[m.rm])) {
            faultf(cpu, A5VM_CPU_FAULT, "invalid MOV segment selector");
            return cpu->status;
        }
        return cpu->status;
    }
    if (opcode == 0xCD) {
        uint8_t vector = fetch8(cpu);
        if (cpu->interrupt_handler &&
            cpu->interrupt_handler(cpu, vector, cpu->interrupt_context)) {
            return cpu->status;
        }
        faultf(cpu, A5VM_CPU_UNIMPLEMENTED,
               "interrupt 0x%02X has no BIOS device yet", vector);
        return cpu->status;
    }
    if (opcode == 0x75) {
        int8_t displacement = (int8_t)fetch8(cpu);
        if ((cpu->eflags & A5VM_FLAG_ZF) == 0) cpu->eip += displacement;
        return cpu->status;
    }
    if (opcode == 0xEB) {
        cpu->eip += (int8_t)fetch8(cpu);
        return cpu->status;
    }
    if (opcode == 0xE9) {
        if (operand32) cpu->eip += (int32_t)fetch32(cpu);
        else cpu->eip += (int16_t)fetch16(cpu);
        return cpu->status;
    }
    if (opcode == 0x89 || opcode == 0x8B || opcode == 0x01 || opcode == 0x03) {
        uint32_t left;
        uint32_t right;
        int address32 = cpu->default_operand_size32;
        if (!decode_modrm(cpu, &m, address32)) return cpu->status;
        if (m.mod == 3) {
            if (opcode == 0x89) {
                if (operand32) cpu->regs[m.rm] = cpu->regs[m.reg];
                else cpu->regs[m.rm] = (cpu->regs[m.rm] & 0xFFFF0000u) |
                    (cpu->regs[m.reg] & 0xFFFFu);
            } else if (opcode == 0x8B) {
                if (operand32) cpu->regs[m.reg] = cpu->regs[m.rm];
                else cpu->regs[m.reg] = (cpu->regs[m.reg] & 0xFFFF0000u) |
                    (cpu->regs[m.rm] & 0xFFFFu);
            } else if (opcode == 0x01) {
                left = operand32 ? cpu->regs[m.rm] : cpu->regs[m.rm] & 0xFFFFu;
                right = operand32 ? cpu->regs[m.reg] : cpu->regs[m.reg] & 0xFFFFu;
                left = add_value(cpu, left, right, operand32);
                cpu->regs[m.rm] = operand32 ? left :
                    (cpu->regs[m.rm] & 0xFFFF0000u) | left;
            } else {
                left = operand32 ? cpu->regs[m.reg] : cpu->regs[m.reg] & 0xFFFFu;
                right = operand32 ? cpu->regs[m.rm] : cpu->regs[m.rm] & 0xFFFFu;
                left = add_value(cpu, left, right, operand32);
                cpu->regs[m.reg] = operand32 ? left :
                    (cpu->regs[m.reg] & 0xFFFF0000u) | left;
            }
        } else {
            uint32_t address = memory_address(cpu, &m, address32);
            if (opcode == 0x89 || opcode == 0x01) {
                uint32_t value = cpu->regs[m.reg];
                if (opcode == 0x01) value = add_value(cpu, read32(cpu, address), value, operand32);
                if (operand32) write32(cpu, address, value);
                else a5vm_memory_write16(cpu->memory, address, (uint16_t)value);
            } else {
                uint32_t value = operand32 ? read32(cpu, address) : read16(cpu, address);
                if (opcode == 0x03) cpu->regs[m.reg] = operand32 ? value :
                    (cpu->regs[m.reg] & 0xFFFF0000u) | value;
                else cpu->regs[m.reg] = operand32 ? value :
                    (cpu->regs[m.reg] & 0xFFFF0000u) | value;
            }
        }
        return cpu->status;
    }
    if (opcode == 0x0F) {
        uint8_t extension = fetch8(cpu);
        if (extension == 0x01) {
            uint8_t value = fetch8(cpu);
            if (((value >> 6) & 3u) != 0 || ((value >> 3) & 7u) != 2 ||
                (value & 7u) != 6) {
                faultf(cpu, A5VM_CPU_UNIMPLEMENTED, "unsupported LGDT form");
                return cpu->status;
            }
            {
                uint32_t address = a5vm_cpu386_linear_address(
                    cpu, A5VM_CPU386_SEG_DS, fetch16(cpu));
                cpu->gdtr_limit = read16(cpu, address);
                cpu->gdtr_base = read16(cpu, address + 2u) |
                    ((uint32_t)read16(cpu, address + 4u) << 16);
            }
            return cpu->status;
        }
        if (extension == 0x20 || extension == 0x22) {
            uint8_t value = fetch8(cpu);
            if (((value >> 6) & 3u) != 3 || ((value >> 3) & 7u) != 0) {
                faultf(cpu, A5VM_CPU_UNIMPLEMENTED, "unsupported control register form");
                return cpu->status;
            }
            if (extension == 0x20) cpu->regs[value & 7u] = cpu->cr0;
            else {
                cpu->cr0 = cpu->regs[value & 7u];
                cpu->protected_mode = (cpu->cr0 & A5VM_CPU386_CR0_PE) != 0;
                if (cpu->protected_mode) {
                    cpu->segment_bases[A5VM_CPU386_SEG_CS] =
                        (uint32_t)cpu->segs[A5VM_CPU386_SEG_CS] << 4;
                    cpu->segment_limits[A5VM_CPU386_SEG_CS] = 0xFFFFF;
                }
            }
            return cpu->status;
        }
        faultf(cpu, A5VM_CPU_UNIMPLEMENTED, "i386 0F opcode 0x%02X", extension);
        return cpu->status;
    }
    if (opcode == 0xEA) {
        uint32_t target = operand32 ? fetch32(cpu) : fetch16(cpu);
        uint16_t selector = fetch16(cpu);
        cpu->segs[A5VM_CPU386_SEG_CS] = selector;
        cpu->eip = target;
        if (cpu->protected_mode) {
            uint32_t base;
            uint32_t limit;
            int default32;
            uint8_t access;
            if (!descriptor(cpu, selector, &base, &limit, &default32, &access) ||
                (access & 0x08u) == 0) {
                faultf(cpu, A5VM_CPU_FAULT, "invalid protected CS 0x%04X", selector);
                return cpu->status;
            }
            cpu->segment_bases[A5VM_CPU386_SEG_CS] = base;
            cpu->segment_limits[A5VM_CPU386_SEG_CS] = limit;
            cpu->segment_access[A5VM_CPU386_SEG_CS] = access;
            cpu->default_operand_size32 = default32;
        }
        return cpu->status;
    }
    faultf(cpu, A5VM_CPU_UNIMPLEMENTED, "i386 opcode 0x%02X at EIP %08X",
           opcode, cpu->eip - 1u);
    return cpu->status;
}

a5vm_cpu_status a5vm_cpu386_run(a5vm_cpu386 *cpu, uint64_t max_steps) {
    uint64_t start = cpu->steps;
    while (cpu->status == A5VM_CPU_RUNNING && cpu->steps - start < max_steps) {
        (void)a5vm_cpu386_step(cpu);
    }
    return cpu->status;
}

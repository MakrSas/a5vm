#include "a5vm/cpu8086.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    uint8_t mod;
    uint8_t reg;
    uint8_t rm;
    uint16_t displacement;
    int uses_ss;
} modrm;

static void faultf(a5vm_cpu8086 *cpu, a5vm_cpu_status status,
                   const char *format, ...) {
    va_list args;
    cpu->status = status;
    va_start(args, format);
    vsnprintf(cpu->fault, sizeof(cpu->fault), format, args);
    va_end(args);
}

static uint8_t get_reg8(const a5vm_cpu8086 *cpu, unsigned index) {
    uint16_t value = cpu->regs[index & 3u];
    return (uint8_t)((index & 4u) ? (value >> 8) : value);
}

static void set_reg8(a5vm_cpu8086 *cpu, unsigned index, uint8_t value) {
    uint16_t *reg = &cpu->regs[index & 3u];
    if (index & 4u) *reg = (uint16_t)((*reg & 0x00FFu) | ((uint16_t)value << 8));
    else *reg = (uint16_t)((*reg & 0xFF00u) | value);
}

uint32_t a5vm_cpu8086_linear_address(const a5vm_cpu8086 *cpu,
                                     uint16_t segment, uint16_t offset) {
    (void)cpu;
    return (((uint32_t)segment << 4) + offset) & A5VM_ADDRESS_MASK;
}

static uint8_t fetch8(a5vm_cpu8086 *cpu) {
    uint32_t address = a5vm_cpu8086_linear_address(cpu, cpu->segs[A5VM_SEG_CS], cpu->ip);
    uint8_t value = a5vm_memory_read8(cpu->memory, address);
    cpu->ip = (uint16_t)(cpu->ip + 1u);
    return value;
}

static uint16_t fetch16(a5vm_cpu8086 *cpu) {
    uint16_t low = fetch8(cpu);
    return (uint16_t)(low | ((uint16_t)fetch8(cpu) << 8));
}

static int parity_even(uint8_t value) {
    value ^= (uint8_t)(value >> 4);
    value ^= (uint8_t)(value >> 2);
    value ^= (uint8_t)(value >> 1);
    return !(value & 1u);
}

static void set_flag(a5vm_cpu8086 *cpu, uint16_t flag, int value) {
    if (value) cpu->flags |= flag;
    else cpu->flags &= (uint16_t)~flag;
}

static void update_logic_flags(a5vm_cpu8086 *cpu, uint16_t value, int width) {
    uint16_t mask = width == 8 ? 0x00FFu : 0xFFFFu;
    uint16_t sign = width == 8 ? 0x0080u : 0x8000u;
    value &= mask;
    set_flag(cpu, A5VM_FLAG_ZF, value == 0);
    set_flag(cpu, A5VM_FLAG_SF, (value & sign) != 0);
    set_flag(cpu, A5VM_FLAG_PF, parity_even((uint8_t)value));
}

static uint16_t alu_add(a5vm_cpu8086 *cpu, uint16_t left, uint16_t right,
                        int width) {
    uint32_t mask = width == 8 ? 0xFFu : 0xFFFFu;
    uint32_t sign = width == 8 ? 0x80u : 0x8000u;
    uint32_t result = (uint32_t)left + right;
    uint16_t value = (uint16_t)(result & mask);
    set_flag(cpu, A5VM_FLAG_CF, result > mask);
    set_flag(cpu, A5VM_FLAG_OF, ((~((uint32_t)left ^ right) &
                                 ((uint32_t)left ^ value) & sign) != 0));
    set_flag(cpu, A5VM_FLAG_AF, ((left ^ right ^ value) & 0x10u) != 0);
    update_logic_flags(cpu, value, width);
    return value;
}

static uint16_t alu_sub(a5vm_cpu8086 *cpu, uint16_t left, uint16_t right,
                        int width) {
    uint32_t mask = width == 8 ? 0xFFu : 0xFFFFu;
    uint32_t sign = width == 8 ? 0x80u : 0x8000u;
    uint16_t value = (uint16_t)(((uint32_t)left - right) & mask);
    set_flag(cpu, A5VM_FLAG_CF, (left & mask) < (right & mask));
    set_flag(cpu, A5VM_FLAG_OF, ((((uint32_t)left ^ right) &
                                 ((uint32_t)left ^ value) & sign) != 0));
    set_flag(cpu, A5VM_FLAG_AF, ((left ^ right ^ value) & 0x10u) != 0);
    update_logic_flags(cpu, value, width);
    return value;
}

static int decode_modrm(a5vm_cpu8086 *cpu, modrm *m) {
    uint8_t byte = fetch8(cpu);
    m->mod = (uint8_t)(byte >> 6);
    m->reg = (uint8_t)((byte >> 3) & 7u);
    m->rm = (uint8_t)(byte & 7u);
    m->displacement = 0;
    m->uses_ss = m->rm == 2 || m->rm == 3 || (m->rm == 6 && m->mod != 0);
    if (m->mod == 0 && m->rm == 6) m->displacement = fetch16(cpu);
    else if (m->mod == 1) m->displacement = (uint16_t)(int16_t)(int8_t)fetch8(cpu);
    else if (m->mod == 2) m->displacement = fetch16(cpu);
    return 1;
}

static uint16_t effective_offset(a5vm_cpu8086 *cpu, const modrm *m) {
    uint16_t base;
    switch (m->rm) {
        case 0: base = (uint16_t)(cpu->regs[A5VM_REG_BX] + cpu->regs[A5VM_REG_SI]); break;
        case 1: base = (uint16_t)(cpu->regs[A5VM_REG_BX] + cpu->regs[A5VM_REG_DI]); break;
        case 2: base = (uint16_t)(cpu->regs[A5VM_REG_BP] + cpu->regs[A5VM_REG_SI]); break;
        case 3: base = (uint16_t)(cpu->regs[A5VM_REG_BP] + cpu->regs[A5VM_REG_DI]); break;
        case 4: base = cpu->regs[A5VM_REG_SI]; break;
        case 5: base = cpu->regs[A5VM_REG_DI]; break;
        case 6: base = m->mod == 0 ? 0 : cpu->regs[A5VM_REG_BP]; break;
        default: base = cpu->regs[A5VM_REG_BX]; break;
    }
    return (uint16_t)(base + m->displacement);
}

static uint32_t modrm_address(a5vm_cpu8086 *cpu, const modrm *m) {
    uint16_t segment = m->uses_ss ? cpu->segs[A5VM_SEG_SS] : cpu->segs[A5VM_SEG_DS];
    return a5vm_cpu8086_linear_address(cpu, segment, effective_offset(cpu, m));
}

static uint16_t read_rm16(a5vm_cpu8086 *cpu, const modrm *m) {
    return m->mod == 3 ? cpu->regs[m->rm] : a5vm_memory_read16(cpu->memory, modrm_address(cpu, m));
}

static uint8_t read_rm8(a5vm_cpu8086 *cpu, const modrm *m) {
    return m->mod == 3 ? get_reg8(cpu, m->rm) : a5vm_memory_read8(cpu->memory, modrm_address(cpu, m));
}

static void write_rm16(a5vm_cpu8086 *cpu, const modrm *m, uint16_t value) {
    if (m->mod == 3) cpu->regs[m->rm] = value;
    else a5vm_memory_write16(cpu->memory, modrm_address(cpu, m), value);
}

static void write_rm8(a5vm_cpu8086 *cpu, const modrm *m, uint8_t value) {
    if (m->mod == 3) set_reg8(cpu, m->rm, value);
    else a5vm_memory_write8(cpu->memory, modrm_address(cpu, m), value);
}

static int conditional(const a5vm_cpu8086 *cpu, uint8_t opcode) {
    switch (opcode) {
        case 0x74: return (cpu->flags & A5VM_FLAG_ZF) != 0;
        case 0x75: return (cpu->flags & A5VM_FLAG_ZF) == 0;
        case 0x72: return (cpu->flags & A5VM_FLAG_CF) != 0;
        case 0x73: return (cpu->flags & A5VM_FLAG_CF) == 0;
        case 0x70: return (cpu->flags & A5VM_FLAG_OF) != 0;
        case 0x71: return (cpu->flags & A5VM_FLAG_OF) == 0;
        case 0x78: return (cpu->flags & A5VM_FLAG_SF) != 0;
        case 0x79: return (cpu->flags & A5VM_FLAG_SF) == 0;
        default: return 0;
    }
}

void a5vm_cpu8086_init(a5vm_cpu8086 *cpu, a5vm_memory *memory) {
    memset(cpu, 0, sizeof(*cpu));
    cpu->memory = memory;
    a5vm_cpu8086_reset(cpu);
}

void a5vm_cpu8086_reset(a5vm_cpu8086 *cpu) {
    memset(cpu->regs, 0, sizeof(cpu->regs));
    memset(cpu->segs, 0, sizeof(cpu->segs));
    cpu->segs[A5VM_SEG_CS] = 0xF000;
    cpu->ip = 0xFFF0;
    cpu->flags = 0x0002;
    cpu->steps = 0;
    cpu->status = A5VM_CPU_RUNNING;
    cpu->fault[0] = '\0';
}

void a5vm_cpu8086_set_interrupt_handler(a5vm_cpu8086 *cpu,
                                         a5vm_cpu_interrupt_handler handler,
                                         void *context) {
    cpu->interrupt_handler = handler;
    cpu->interrupt_context = context;
}

const char *a5vm_cpu8086_fault(const a5vm_cpu8086 *cpu) {
    return cpu->fault;
}

a5vm_cpu_status a5vm_cpu8086_step(a5vm_cpu8086 *cpu) {
    uint8_t opcode;
    uint8_t displacement;
    modrm m;
    if (cpu->status != A5VM_CPU_RUNNING) return cpu->status;
    opcode = fetch8(cpu);
    cpu->steps++;
    if (opcode == 0x90) return cpu->status;
    if (opcode == 0xF4) { cpu->status = A5VM_CPU_HALTED; return cpu->status; }
    if (opcode >= 0xB0 && opcode <= 0xB7) {
        set_reg8(cpu, opcode - 0xB0, fetch8(cpu));
        return cpu->status;
    }
    if (opcode >= 0xB8 && opcode <= 0xBF) {
        cpu->regs[opcode - 0xB8] = fetch16(cpu);
        return cpu->status;
    }
    if (opcode == 0x05) {
        cpu->regs[A5VM_REG_AX] = alu_add(cpu, cpu->regs[A5VM_REG_AX], fetch16(cpu), 16);
        return cpu->status;
    }
    if (opcode == 0x2D) {
        cpu->regs[A5VM_REG_AX] = alu_sub(cpu, cpu->regs[A5VM_REG_AX], fetch16(cpu), 16);
        return cpu->status;
    }
    if (opcode == 0x3D) {
        (void)alu_sub(cpu, cpu->regs[A5VM_REG_AX], fetch16(cpu), 16);
        return cpu->status;
    }
    if (opcode >= 0x40 && opcode <= 0x47) {
        uint16_t carry = cpu->flags & A5VM_FLAG_CF;
        cpu->regs[opcode - 0x40] = alu_add(cpu, cpu->regs[opcode - 0x40], 1, 16);
        cpu->flags = (uint16_t)((cpu->flags & (uint16_t)~A5VM_FLAG_CF) | carry);
        return cpu->status;
    }
    if (opcode >= 0x48 && opcode <= 0x4F) {
        uint16_t carry = cpu->flags & A5VM_FLAG_CF;
        cpu->regs[opcode - 0x48] = alu_sub(cpu, cpu->regs[opcode - 0x48], 1, 16);
        cpu->flags = (uint16_t)((cpu->flags & (uint16_t)~A5VM_FLAG_CF) | carry);
        return cpu->status;
    }
    if (opcode >= 0x50 && opcode <= 0x57) {
        cpu->regs[A5VM_REG_SP] = (uint16_t)(cpu->regs[A5VM_REG_SP] - 2);
        a5vm_memory_write16(cpu->memory,
            a5vm_cpu8086_linear_address(cpu, cpu->segs[A5VM_SEG_SS], cpu->regs[A5VM_REG_SP]),
            cpu->regs[opcode - 0x50]);
        return cpu->status;
    }
    if (opcode >= 0x58 && opcode <= 0x5F) {
        cpu->regs[opcode - 0x58] = a5vm_memory_read16(cpu->memory,
            a5vm_cpu8086_linear_address(cpu, cpu->segs[A5VM_SEG_SS], cpu->regs[A5VM_REG_SP]));
        cpu->regs[A5VM_REG_SP] = (uint16_t)(cpu->regs[A5VM_REG_SP] + 2);
        return cpu->status;
    }
    if (opcode == 0xEB) { cpu->ip = (uint16_t)(cpu->ip + (int8_t)fetch8(cpu)); return cpu->status; }
    if (opcode == 0xE9) { cpu->ip = (uint16_t)(cpu->ip + (int16_t)fetch16(cpu)); return cpu->status; }
    if (opcode == 0x74 || opcode == 0x75 || opcode == 0x70 || opcode == 0x71 ||
        opcode == 0x72 || opcode == 0x73 || opcode == 0x78 || opcode == 0x79) {
        displacement = fetch8(cpu);
        if (conditional(cpu, opcode)) cpu->ip = (uint16_t)(cpu->ip + (int8_t)displacement);
        return cpu->status;
    }
    if (opcode >= 0x88 && opcode <= 0x8B) {
        decode_modrm(cpu, &m);
        if (opcode == 0x88) write_rm8(cpu, &m, get_reg8(cpu, m.reg));
        else if (opcode == 0x89) write_rm16(cpu, &m, cpu->regs[m.reg]);
        else if (opcode == 0x8A) set_reg8(cpu, m.reg, read_rm8(cpu, &m));
        else cpu->regs[m.reg] = read_rm16(cpu, &m);
        return cpu->status;
    }
    if (opcode == 0xC6 || opcode == 0xC7) {
        decode_modrm(cpu, &m);
        if (m.reg != 0) {
            faultf(cpu, A5VM_CPU_FAULT, "invalid MOV group /%u", m.reg);
            return cpu->status;
        }
        if (opcode == 0xC6) write_rm8(cpu, &m, fetch8(cpu));
        else write_rm16(cpu, &m, fetch16(cpu));
        return cpu->status;
    }
    if (opcode == 0x01 || opcode == 0x03 || opcode == 0x29 || opcode == 0x2B ||
        opcode == 0x39 || opcode == 0x3B) {
        uint16_t value;
        decode_modrm(cpu, &m);
        if (opcode == 0x01) write_rm16(cpu, &m, alu_add(cpu, read_rm16(cpu, &m), cpu->regs[m.reg], 16));
        else if (opcode == 0x03) cpu->regs[m.reg] = alu_add(cpu, cpu->regs[m.reg], read_rm16(cpu, &m), 16);
        else if (opcode == 0x29) write_rm16(cpu, &m, alu_sub(cpu, read_rm16(cpu, &m), cpu->regs[m.reg], 16));
        else if (opcode == 0x2B) cpu->regs[m.reg] = alu_sub(cpu, cpu->regs[m.reg], read_rm16(cpu, &m), 16);
        else if (opcode == 0x39) (void)alu_sub(cpu, read_rm16(cpu, &m), cpu->regs[m.reg], 16);
        else { value = read_rm16(cpu, &m); (void)alu_sub(cpu, cpu->regs[m.reg], value, 16); }
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
    faultf(cpu, A5VM_CPU_UNIMPLEMENTED, "opcode 0x%02X at CS:IP %04X:%04X",
           opcode, cpu->segs[A5VM_SEG_CS], (uint16_t)(cpu->ip - 1));
    return cpu->status;
}

a5vm_cpu_status a5vm_cpu8086_run(a5vm_cpu8086 *cpu, uint64_t max_steps) {
    uint64_t start = cpu->steps;
    while (cpu->status == A5VM_CPU_RUNNING && cpu->steps - start < max_steps) {
        (void)a5vm_cpu8086_step(cpu);
    }
    return cpu->status;
}

#include <stdio.h>

#include "a5vm/cpu8086.h"

static int failures;

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #condition); \
        failures++; \
    } \
} while (0)

static void test_memory_wrap(void) {
    a5vm_memory memory;
    a5vm_memory_init(&memory);
    a5vm_memory_write16(&memory, 0xFFFFF, 0xBEEF);
    CHECK(a5vm_memory_read8(&memory, 0xFFFFF) == 0xEF);
    CHECK(a5vm_memory_read8(&memory, 0x100000) == 0xBE);
    CHECK(a5vm_memory_read16(&memory, 0xFFFFF) == 0xBEEF);
}

static void run_program(const uint8_t *program, size_t length,
                        a5vm_cpu8086 *cpu, a5vm_memory *memory) {
    a5vm_memory_init(memory);
    a5vm_memory_load(memory, 0x200, program, length);
    a5vm_cpu8086_init(cpu, memory);
    cpu->segs[A5VM_SEG_CS] = 0;
    cpu->ip = 0x200;
    cpu->regs[A5VM_REG_SP] = 0x8000;
    (void)a5vm_cpu8086_run(cpu, 1000);
}

static void test_arithmetic_and_branch(void) {
    static const uint8_t program[] = {
        0xB8, 0x02, 0x00,       /* mov ax, 2 */
        0x05, 0x03, 0x00,       /* add ax, 3 */
        0x3D, 0x05, 0x00,       /* cmp ax, 5 */
        0x74, 0x03,             /* jz +3 */
        0xB9, 0xAD, 0xDE,       /* mov cx, dead (must be skipped) */
        0xF4                    /* hlt */
    };
    a5vm_memory memory;
    a5vm_cpu8086 cpu;
    run_program(program, sizeof(program), &cpu, &memory);
    CHECK(cpu.status == A5VM_CPU_HALTED);
    CHECK(cpu.regs[A5VM_REG_AX] == 5);
    CHECK(cpu.regs[A5VM_REG_CX] == 0);
    CHECK((cpu.flags & A5VM_FLAG_ZF) != 0);
}

static void test_stack(void) {
    static const uint8_t program[] = {
        0xB8, 0x34, 0x12,       /* mov ax, 1234 */
        0x50,                   /* push ax */
        0xB8, 0, 0,             /* mov ax, 0 */
        0x58,                   /* pop ax */
        0xF4                    /* hlt */
    };
    a5vm_memory memory;
    a5vm_cpu8086 cpu;
    run_program(program, sizeof(program), &cpu, &memory);
    CHECK(cpu.status == A5VM_CPU_HALTED);
    CHECK(cpu.regs[A5VM_REG_AX] == 0x1234);
    CHECK(cpu.regs[A5VM_REG_SP] == 0x8000);
}

int main(void) {
    test_memory_wrap();
    test_arithmetic_and_branch();
    test_stack();
    if (failures != 0) {
        fprintf(stderr, "%d test(s) failed\n", failures);
        return 1;
    }
    puts("a5vm-tests: all tests passed");
    return 0;
}

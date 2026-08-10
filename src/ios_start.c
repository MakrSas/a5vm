extern int a5vm_ios_main(void);

__attribute__((noreturn)) void start(void) {
    register int result __asm__("r0") = a5vm_ios_main();
    register int syscall_number __asm__("r12") = 1;
    __asm__ volatile("svc #0x80"
                     :
                     : "r"(result), "r"(syscall_number)
                     : "memory");
    for (;;) {}
}

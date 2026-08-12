/*
 * Standalone device smoke test for qemu_init()/qemu_main_loop(), built
 * and linked against the same libqemu-system-i386.dylib the real
 * A5VMQemuBridge uses, but with no UIKit/ObjC/A5VM app involved at
 * all. qemu_init() calls exit() directly on argument errors (it is
 * ordinary standalone-QEMU code, just built as a shared library), so
 * this exists to answer one question in isolation, away from any risk
 * to the rest of the app: does qemu_init() survive the exact argv
 * shape +[A5VMQemuBridge argumentsWithRAMMegabytes:driveImagePath:
 * isISO:] builds, on the real device? Run manually over SSH; not part
 * of the app bundle and never invoked by A5VM itself.
 */

#include <stdio.h>

extern void qemu_init(int argc, char **argv, char **envp);
extern void qemu_main_loop(void);
extern void qemu_cleanup(void);

int main(int argc, char **argv)
{
    /* Mirrors +[A5VMQemuBridge argumentsWithRAMMegabytes:driveImagePath:
       isISO:]'s output exactly (see app/A5VMQemuBridge.m), so a pass
       here is direct evidence about that exact code path -- with the
       drive path taken from argv[1] so this can be pointed at whatever
       image actually exists on the device being tested, rather than a
       path baked in at CI build time. */
    const char *drive_path = argc > 1 ? argv[1] : "/var/mobile/Documents/Win98-SE-Boot.img";
    char drive_arg[512];
    snprintf(drive_arg, sizeof(drive_arg), "file=%s,if=ide,media=disk", drive_path);

    char *qemu_argv[] = {
        "a5vm-qemu",
        "-M", "pc",
        "-m", "32",
        "-vga", "std",
        "-boot", "order=c",
        "-drive", drive_arg,
        "-display", "none",
        "-monitor", "none",
        "-serial", "none",
        "-parallel", "none",
        NULL,
    };
    int qemu_argc = (int)(sizeof(qemu_argv) / sizeof(qemu_argv[0])) - 1;

    fprintf(stderr, "A5VM_SMOKETEST: drive=%s\n", drive_path);
    fprintf(stderr, "A5VM_SMOKETEST: calling qemu_init...\n");
    fflush(stderr);
    qemu_init(qemu_argc, qemu_argv, NULL);
    fprintf(stderr, "A5VM_SMOKETEST: qemu_init returned, entering qemu_main_loop...\n");
    fflush(stderr);
    qemu_main_loop();
    fprintf(stderr, "A5VM_SMOKETEST: qemu_main_loop returned, calling qemu_cleanup...\n");
    fflush(stderr);
    qemu_cleanup();
    fprintf(stderr, "A5VM_SMOKETEST: qemu_cleanup returned, success\n");
    return 0;
}

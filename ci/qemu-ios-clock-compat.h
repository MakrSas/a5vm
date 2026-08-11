#ifndef A5VM_QEMU_IOS_CLOCK_COMPAT_H
#define A5VM_QEMU_IOS_CLOCK_COMPAT_H

/*
 * The iPhoneOS6.1 SDK predates POSIX clock_gettime()/CLOCK_MONOTONIC on
 * Apple platforms (Apple added them around iOS 10 / macOS 10.12), so
 * QEMU's use of them in include/qemu/timer.h and util/qemu-timer-common.c
 * fails to compile against it. Force-included ahead of every QEMU
 * translation unit via -include, this provides the same POSIX surface
 * backed by Darwin's own long-standing mach_absolute_time()/gettimeofday()
 * so QEMU's vendored source does not need patching.
 */
#if defined(__APPLE__) && !defined(CLOCK_MONOTONIC)

#include <mach/mach_time.h>
#include <sys/time.h>
#include <time.h>

#define CLOCK_MONOTONIC 1
#define CLOCK_REALTIME 0

static inline int a5vm_qemu_ios_clock_gettime(int clk_id, struct timespec *ts)
{
    if (clk_id == CLOCK_MONOTONIC) {
        static mach_timebase_info_data_t timebase;
        uint64_t now;

        if (timebase.denom == 0) {
            mach_timebase_info(&timebase);
        }
        now = mach_absolute_time() * timebase.numer / timebase.denom;
        ts->tv_sec = now / 1000000000ULL;
        ts->tv_nsec = now % 1000000000ULL;
    } else {
        struct timeval tv;

        gettimeofday(&tv, NULL);
        ts->tv_sec = tv.tv_sec;
        ts->tv_nsec = tv.tv_usec * 1000;
    }
    return 0;
}
#define clock_gettime a5vm_qemu_ios_clock_gettime

#endif /* __APPLE__ && !CLOCK_MONOTONIC */

#endif /* A5VM_QEMU_IOS_CLOCK_COMPAT_H */

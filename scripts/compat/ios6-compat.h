/*
 * ios6-compat.h — подставляется через -include в каждую единицу трансляции
 * QEMU.
 *
 * Здесь только то, чего в iPhoneOS6.1.sdk нет, а современный код считает
 * само собой разумеющимся.  Заголовок, а не патч исходников QEMU: так
 * дерево QEMU остаётся нетронутым и обновляемым, а весь список отличий
 * собран в одном месте.
 */

#ifndef A5_IOS6_COMPAT_H
#define A5_IOS6_COMPAT_H

/*
 * clock_gettime() и CLOCK_MONOTONIC Apple добавила только в SDK iOS 10.
 * include/qemu/timer.h вызывает их безусловно (ветка не под #ifdef), так
 * что без этой заглушки QEMU не соберётся вовсе.
 *
 * mach_absolute_time() — то, во что clock_gettime(CLOCK_MONOTONIC) на
 * Дарвине в итоге и превращается: монотонные тики с момента загрузки,
 * доступные на iOS задолго до 6.0.
 */
#ifndef CLOCK_MONOTONIC

#include <time.h>
#include <sys/time.h>
#include <stdint.h>
#include <mach/mach_time.h>

#define CLOCK_REALTIME  0
#define CLOCK_MONOTONIC 6

typedef int clockid_t;

static inline int clock_gettime(clockid_t clock_id, struct timespec *ts)
{
    if (!ts) {
        return -1;
    }

    if (clock_id == CLOCK_MONOTONIC) {
        /* На ARM тики не наносекунды (у A5 это 24 МГц), поэтому нужен
         * пересчёт через timebase. */
        static mach_timebase_info_data_t timebase;
        uint64_t nanoseconds;

        if (timebase.denom == 0) {
            mach_timebase_info(&timebase);
        }
        nanoseconds = mach_absolute_time() * timebase.numer / timebase.denom;
        ts->tv_sec  = (time_t)(nanoseconds / 1000000000ULL);
        ts->tv_nsec = (long)(nanoseconds % 1000000000ULL);
        return 0;
    }

    {
        struct timeval tv;
        if (gettimeofday(&tv, NULL) != 0) {
            return -1;
        }
        ts->tv_sec  = tv.tv_sec;
        ts->tv_nsec = (long)tv.tv_usec * 1000;
        return 0;
    }
}

#endif /* CLOCK_MONOTONIC */

/*
 * VM_FLAGS_RANDOM_ADDR — флаг vm_map(2), которым пользуется код iOS-JIT в
 * accel/tcg/translate-all.c (alloc_jit_rw_mirror).  Значение задаёт и
 * интерпретирует само ядро, поэтому оно не может измениться между версиями
 * ОС, не сломав уже собранные бинарники; проще объявить константу, чем
 * подменять целый заголовок ядра ради одного макроса.
 */
#ifndef VM_FLAGS_RANDOM_ADDR
#define VM_FLAGS_RANDOM_ADDR 0x00000800
#endif

#endif /* A5_IOS6_COMPAT_H */

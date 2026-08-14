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
 * Два флага, которыми QEMU выделяет память под JIT, появились уже после
 * iOS 6.  Оба проверены на устройстве: каждый в свой черёд валил запуск.
 *
 * MAP_JIT (accel/tcg/translate-all.c, ветка CONFIG_DARWIN) введён ради
 * hardened runtime и на iOS требует права dynamic-codesigning; ядро
 * xnu-2107 его не принимает, и mmap просто возвращает ошибку —
 * «Could not allocate dynamic translator buffer».  Смысл флага в том,
 * чтобы разрешить страницы, одновременно записываемые и исполняемые, а на
 * устройстве с jailbreak такие страницы и так доступны обычным mmap.
 * Значит здесь он не нужен, а мешает.
 *
 * VM_FLAGS_RANDOM_ADDR (там же, alloc_jit_rw_mirror) в SDK 6.1 не объявлен
 * вовсе — потому что появился позже.  vm_map отвергает неизвестные биты
 * флагов, и mach_vm_remap падал с «Could not remap code buffer mirror».
 * Единственное, что он даёт, — рандомизацию адреса зеркального
 * отображения; без неё можно обойтись.
 *
 * Обнуление, а не удаление из исходников: оба используются ровно по
 * одному разу и только в этих двух местах, так что смысл правки виден
 * целиком отсюда.
 */
#include <sys/mman.h>

#undef MAP_JIT
#define MAP_JIT 0

#undef VM_FLAGS_RANDOM_ADDR
#define VM_FLAGS_RANDOM_ADDR 0

#endif /* A5_IOS6_COMPAT_H */

/*
 * ios6-compat.c — функции рантайма, которых для пары
 * «armv7-apple-ios + iPhoneOS6.1.sdk» не даёт ни libSystem, ни автоматически
 * подключаемый compiler-rt.  Объектный файл добавляется прямо в линковку
 * libqemu-system-i386.dylib.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <libkern/OSCacheControl.h>

/*
 * __clear_cache
 *
 * tcg/arm/tcg-target.h вызывает __builtin___clear_cache(), чтобы только что
 * сгенерированный ARM-код стал виден кэшу инструкций — без этого JIT молча
 * исполняет мусор.  Билтин компилируется в вызов внешнего символа
 * __clear_cache, который для этой комбинации SDK и таргета не находится.
 *
 * Сигнатура обязана быть (void *, void *) — именно её ожидает clang; при
 * (char *, char *) он ругается на несовпадение с прототипом билтина.
 */
void __clear_cache(void *start, void *end)
{
    if (end > start) {
        sys_icache_invalidate(start, (size_t)((char *)end - (char *)start));
    }
}

/*
 * Эмулированный TLS
 *
 * QEMU нужен __thread, а нативный TLS для 32-битного iOS требует поддержки
 * Mach-O TLV в dyld, которой на iOS 6 нет (см. комментарий про
 * A5_TLS_MIN_VERSION в scripts/ios-env.sh).  Поэтому сборка идёт с
 * -femulated-tls: обращения к __thread превращаются в вызовы
 * __emutls_get_address.
 *
 * Функция живёт в compiler-rt, но в современных Xcode из libclang_rt.ios.a
 * armv7-срез уже убран, так что рассчитывать на неё нельзя.  Реализация
 * ниже повторяет ABI compiler-rt: если линковщик всё же найдёт настоящую,
 * он возьмёт определение отсюда (символ уже определён в объектнике, и член
 * архива просто не подтягивается) — поведение в обоих случаях одинаковое.
 */

typedef struct {
    size_t size;    /* размер объекта в байтах */
    size_t align;   /* выравнивание, степень двойки */
    union {
        uintptr_t index;  /* 1-based индекс в массиве потока */
        void *address;
    } object;
    void *value;    /* начальное значение либо NULL для нулей */
} a5_emutls_control;

typedef struct {
    uintptr_t size;    /* сколько слотов выделено */
    void *data[];
} a5_emutls_array;

static pthread_mutex_t a5_emutls_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_key_t   a5_emutls_key;
static pthread_once_t  a5_emutls_once = PTHREAD_ONCE_INIT;
static uintptr_t       a5_emutls_next_index;

static void a5_emutls_destroy(void *pointer)
{
    a5_emutls_array *array = (a5_emutls_array *)pointer;
    uintptr_t index;

    if (!array) {
        return;
    }
    for (index = 0; index < array->size; index++) {
        free(array->data[index]);
    }
    free(array);
}

static void a5_emutls_init(void)
{
    if (pthread_key_create(&a5_emutls_key, a5_emutls_destroy) != 0) {
        abort();
    }
}

static void *a5_emutls_allocate(a5_emutls_control *control)
{
    size_t alignment = control->align;
    size_t size = control->size ? control->size : 1;
    void *object = NULL;

    if (alignment < sizeof(void *)) {
        alignment = sizeof(void *);
    }
    if (posix_memalign(&object, alignment, size) != 0) {
        abort();
    }

    if (control->value) {
        memcpy(object, control->value, control->size);
    } else {
        memset(object, 0, size);
    }
    return object;
}

void *__emutls_get_address(void *pointer)
{
    a5_emutls_control *control = (a5_emutls_control *)pointer;
    a5_emutls_array *array;
    uintptr_t index;
    void *object;

    pthread_once(&a5_emutls_once, a5_emutls_init);

    /* Индекс объекта раздаётся один раз на всю программу и дальше только
     * читается, поэтому под блокировкой — лишь его назначение. */
    pthread_mutex_lock(&a5_emutls_mutex);
    if (control->object.index == 0) {
        control->object.index = ++a5_emutls_next_index;
    }
    index = control->object.index;
    pthread_mutex_unlock(&a5_emutls_mutex);

    array = (a5_emutls_array *)pthread_getspecific(a5_emutls_key);
    if (!array || array->size < index) {
        /* С запасом, чтобы новый __thread-объект не вызывал перевыделение
         * массива у каждого потока по отдельности. */
        uintptr_t wanted = index + 16;
        a5_emutls_array *grown =
            (a5_emutls_array *)calloc(1, sizeof(a5_emutls_array) +
                                          wanted * sizeof(void *));
        if (!grown) {
            abort();
        }
        if (array) {
            memcpy(grown->data, array->data, array->size * sizeof(void *));
            free(array);
        }
        grown->size = wanted;
        array = grown;
        if (pthread_setspecific(a5_emutls_key, array) != 0) {
            abort();
        }
    }

    object = array->data[index - 1];
    if (!object) {
        object = a5_emutls_allocate(control);
        array->data[index - 1] = object;
    }
    return object;
}

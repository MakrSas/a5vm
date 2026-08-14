/*
 * tls-selftest — проверка эмулированного TLS на устройстве.
 *
 * QEMU держит в __thread ключевое состояние (tcg_ctx, current_cpu, RCU), а
 * на этой платформе TLS работает не нативно, а через __emutls_get_address
 * из compiler-rt (см. build-qemu.sh).
 *
 * Ошибка там проявилась бы как «переменная внезапно нулевая» глубоко
 * внутри QEMU, где отличить её от чего угодно другого невозможно. Поэтому
 * проверяется отдельно и прямо: начальное значение, изоляция между
 * потоками и, главное, устойчивость адреса — один и тот же __thread-объект
 * обязан жить по одному адресу при всех обращениях внутри потока.
 *
 * Собирается теми же флагами, что и QEMU (-femulated-tls), и линкуется с
 * тем же ios6-compat.o.
 */

#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define THREADS 4
#define REPEATS 2000

static __thread int       tls_int;
static __thread long long tls_big;
static __thread void     *tls_ptr;
static __thread char      tls_buf[64];
/* Ненулевое начальное значение: emutls обязан копировать его из control->value,
 * а не просто отдавать обнулённую память. */
static __thread int       tls_preset = 0x5A5A5A5A;

struct worker_arg {
    int id;
    int failures;
};

static void *worker(void *opaque)
{
    struct worker_arg *arg = opaque;
    long long expected_big = (long long)arg->id * 1000003LL;
    void *first_address = &tls_int;
    int i;

    if (tls_preset != 0x5A5A5A5A) {
        printf("  поток %d: начальное значение не дошло: 0x%08x\n",
               arg->id, tls_preset);
        arg->failures++;
    }
    if (tls_int != 0 || tls_big != 0 || tls_ptr != NULL) {
        printf("  поток %d: свежий объект не обнулён\n", arg->id);
        arg->failures++;
    }

    tls_int = arg->id;
    tls_big = expected_big;
    tls_ptr = &tls_int;
    memset(tls_buf, arg->id, sizeof(tls_buf));

    /* Дать остальным потокам записать своё — если объекты общие, значения
     * затрут друг друга. */
    usleep(100000);

    for (i = 0; i < REPEATS; i++) {
        if (&tls_int != first_address) {
            printf("  поток %d: адрес объекта поехал на шаге %d\n", arg->id, i);
            arg->failures++;
            break;
        }
        if (tls_int != arg->id || tls_big != expected_big ||
            tls_ptr != first_address ||
            (unsigned char)tls_buf[0] != (unsigned char)arg->id) {
            printf("  поток %d: значение испортилось на шаге %d "
                   "(int=%d big=%lld buf=%u)\n",
                   arg->id, i, tls_int, tls_big,
                   (unsigned)(unsigned char)tls_buf[0]);
            arg->failures++;
            break;
        }
    }
    return NULL;
}

/*
 * Проверка заглушки clock_gettime из ios6-compat.h.
 *
 * На ней держится вся система таймеров QEMU: get_clock() в
 * include/qemu/timer.h вызывает clock_gettime(CLOCK_MONOTONIC) напрямую.
 * Если эти часы врут, таймеры считают себя вечно просроченными, главный
 * цикл непрерывно выбивает поток исполнения из цепочки блоков, и гость
 * ползёт, формально ничего не нарушая.
 */
static int check_clock(void)
{
    struct timespec a, b;
    long long elapsed_ns, expected_ns = 500000000LL;
    int failures = 0;

    if (clock_gettime(CLOCK_MONOTONIC, &a) != 0) {
        printf("  clock_gettime вернула ошибку\n");
        return 1;
    }
    if (a.tv_sec == 0 && a.tv_nsec == 0) {
        printf("  часы стоят на нуле\n");
        failures++;
    }
    if (a.tv_nsec < 0 || a.tv_nsec >= 1000000000L) {
        printf("  tv_nsec вне диапазона: %ld\n", a.tv_nsec);
        failures++;
    }

    usleep(500000);
    clock_gettime(CLOCK_MONOTONIC, &b);

    elapsed_ns = ((long long)b.tv_sec - a.tv_sec) * 1000000000LL +
                 ((long long)b.tv_nsec - a.tv_nsec);
    printf("  за паузу 0.5 c часы прошли %lld нс\n", elapsed_ns);

    /* Допуск щедрый: важно не точное значение, а верный порядок величины —
     * ошибка в timebase дала бы промах в десятки раз. */
    if (elapsed_ns < expected_ns / 2 || elapsed_ns > expected_ns * 4) {
        printf("  ход часов неверен (ожидалось около %lld нс)\n", expected_ns);
        failures++;
    }

    /* Монотонность: подряд идущие отсчёты не должны идти назад. */
    {
        struct timespec prev = b, now;
        int i;
        for (i = 0; i < 20000; i++) {
            clock_gettime(CLOCK_MONOTONIC, &now);
            if (now.tv_sec < prev.tv_sec ||
                (now.tv_sec == prev.tv_sec && now.tv_nsec < prev.tv_nsec)) {
                printf("  часы пошли назад на шаге %d\n", i);
                failures++;
                break;
            }
            prev = now;
        }
    }

    printf("[clock] %s\n", failures ? "ЕСТЬ ОШИБКИ" : "всё верно");
    return failures;
}

int main(void)
{
    pthread_t threads[THREADS];
    struct worker_arg args[THREADS];
    int failures = 0;
    int i;

    failures += check_clock();

    /* Главный поток тоже владеет своей копией. */
    tls_int = 0x1234;
    tls_big = -1;

    printf("[tls] запуск %d потоков\n", THREADS);
    for (i = 0; i < THREADS; i++) {
        args[i].id = i + 1;
        args[i].failures = 0;
        if (pthread_create(&threads[i], NULL, worker, &args[i]) != 0) {
            printf("  не удалось создать поток %d\n", i);
            return 1;
        }
    }
    for (i = 0; i < THREADS; i++) {
        pthread_join(threads[i], NULL);
        failures += args[i].failures;
    }

    if (tls_int != 0x1234 || tls_big != -1) {
        printf("  главный поток: значения затёрты (int=%d big=%lld)\n",
               tls_int, tls_big);
        failures++;
    }

    printf("[tls] %s\n", failures ? "ЕСТЬ ОШИБКИ" : "всё верно");
    return failures ? 1 : 0;
}

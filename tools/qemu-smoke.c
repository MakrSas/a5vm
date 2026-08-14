/*
 * qemu-smoke — запуск ВМ без участия UI.
 *
 * Нужен потому, что единственный другой способ проверить работу гостя —
 * физически тапнуть по иконке на устройстве, а по SSH этого не сделать.
 * Программа повторяет ровно то, что делает приложение (dlopen библиотеки,
 * dlsym моста, a5_qemu_start с готовым argv), крутится заданное время и
 * сохраняет последний кадр в PPM — так видно не только «не упало», но и
 * что именно гость нарисовал.
 *
 * Собирается в CI, кладётся в артефакт отдельно от бандла приложения.
 *
 * Использование:
 *   qemu-smoke <путь к dylib> <секунд> <куда сохранить .ppm> [-- аргументы QEMU]
 */

#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "a5_qemu.h"

static pthread_mutex_t frame_lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned char *last_frame;
static int last_width, last_height, last_stride, last_bpp;
static int frame_count;
static int stopped;
static char stop_message[256];

static void on_frame(void *context, const a5_qemu_frame *frame)
{
    size_t bytes;

    pthread_mutex_lock(&frame_lock);
    frame_count++;
    if (frame_count <= 3) {
        printf("[frame %d] %dx%d stride=%d bpp=%d\n", frame_count,
               frame->width, frame->height, frame->stride,
               frame->bits_per_pixel);
        fflush(stdout);
    }

    bytes = (size_t)frame->stride * (size_t)frame->height;
    free(last_frame);
    last_frame = malloc(bytes);
    if (last_frame) {
        memcpy(last_frame, frame->pixels, bytes);
        last_width  = frame->width;
        last_height = frame->height;
        last_stride = frame->stride;
        last_bpp    = frame->bits_per_pixel;
    }
    pthread_mutex_unlock(&frame_lock);
}

static void on_stop(void *context, const char *message)
{
    stopped = 1;
    snprintf(stop_message, sizeof(stop_message), "%s",
             message ? message : "(штатное завершение)");
    printf("[stopped] %s\n", stop_message);
    fflush(stdout);
}

/* PPM выбран потому, что его можно записать без единой зависимости, а
 * прочитать чем угодно на стороне разработчика. */
static void write_ppm(const char *path)
{
    FILE *file;
    int x, y;

    pthread_mutex_lock(&frame_lock);
    if (!last_frame) {
        pthread_mutex_unlock(&frame_lock);
        printf("[ppm] кадров не было, файл не создан\n");
        return;
    }

    file = fopen(path, "wb");
    if (!file) {
        pthread_mutex_unlock(&frame_lock);
        printf("[ppm] не удалось открыть %s\n", path);
        return;
    }

    fprintf(file, "P6\n%d %d\n255\n", last_width, last_height);
    for (y = 0; y < last_height; y++) {
        const unsigned char *row = last_frame + (size_t)y * last_stride;
        for (x = 0; x < last_width; x++) {
            /* Поверхность QEMU — PIXMAN_x8r8g8b8, на little-endian это
             * байты B, G, R, X. Пишем в PPM как R, G, B. */
            const unsigned char *pixel = row + x * 4;
            fputc(pixel[2], file);
            fputc(pixel[1], file);
            fputc(pixel[0], file);
        }
    }
    fclose(file);
    printf("[ppm] %s: %dx%d\n", path, last_width, last_height);
    pthread_mutex_unlock(&frame_lock);
}

int main(int argc, char **argv)
{
    void *handle;
    int32_t (*abi_version)(void);
    void (*set_callbacks)(a5_qemu_frame_callback, a5_qemu_stopped_callback, void *);
    int32_t (*start)(int32_t, const char *const *);
    int32_t (*is_running)(void);
    void (*request_quit)(void);

    const char *library;
    int seconds;
    const char *ppm_path;
    int qemu_argc;
    const char **qemu_argv;
    int i;

    if (argc < 5 || strcmp(argv[4], "--") != 0) {
        fprintf(stderr,
                "использование: %s <dylib> <секунд> <кадр.ppm> -- <аргументы qemu>\n",
                argv[0]);
        return 2;
    }

    library  = argv[1];
    seconds  = atoi(argv[2]);
    ppm_path = argv[3];

    handle = dlopen(library, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        fprintf(stderr, "dlopen: %s\n", dlerror());
        return 1;
    }

#define RESOLVE(var, name)                                                  \
    do {                                                                    \
        *(void **)(&var) = dlsym(handle, name);                             \
        if (!var) { fprintf(stderr, "нет символа %s\n", name); return 1; }  \
    } while (0)

    RESOLVE(abi_version,   "a5_qemu_abi_version");
    RESOLVE(set_callbacks, "a5_qemu_set_callbacks");
    RESOLVE(start,         "a5_qemu_start");
    RESOLVE(is_running,    "a5_qemu_is_running");
    RESOLVE(request_quit,  "a5_qemu_request_quit");
#undef RESOLVE

    printf("[abi] версия библиотеки %d, ожидается %d\n",
           (int)abi_version(), A5_QEMU_ABI_VERSION);
    if (abi_version() != A5_QEMU_ABI_VERSION) {
        return 1;
    }

    /* argv[0] для QEMU — как у обычной командной строки. */
    qemu_argc = argc - 5 + 1;
    qemu_argv = calloc((size_t)qemu_argc + 1, sizeof(char *));
    qemu_argv[0] = "qemu-system-i386";
    for (i = 0; i < argc - 5; i++) {
        qemu_argv[i + 1] = argv[5 + i];
    }

    printf("[argv]");
    for (i = 0; i < qemu_argc; i++) {
        printf(" %s", qemu_argv[i]);
    }
    printf("\n");
    fflush(stdout);

    set_callbacks(on_frame, on_stop, NULL);

    if (start(qemu_argc, qemu_argv) != 0) {
        fprintf(stderr, "a5_qemu_start не смог создать поток\n");
        return 1;
    }

    for (i = 0; i < seconds && !stopped; i++) {
        sleep(1);
        printf("[t=%2d] кадров: %d, работает: %d\n", i + 1, frame_count,
               (int)is_running());
        fflush(stdout);
    }

    write_ppm(ppm_path);

    if (!stopped) {
        request_quit();
        sleep(2);
    }

    printf("[итог] кадров: %d, остановлена: %d %s\n",
           frame_count, stopped, stopped ? stop_message : "");
    return frame_count > 0 ? 0 : 3;
}

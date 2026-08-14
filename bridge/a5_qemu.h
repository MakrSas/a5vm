/*
 * a5_qemu.h — стабильный C-ABI между A5VM и QEMU.
 *
 * Этот заголовок — ЕДИНСТВЕННОЕ, что приложение знает о QEMU.  Реализация
 * (a5_qemu.c) компилируется внутри дерева QEMU, со всеми его настоящими
 * заголовками, поэтому в приложении не нужно вручную повторять layout
 * внутренних структур QEMU — самая хрупкая часть подобных мостов.
 *
 * Приложение резолвит эти функции через dlsym, а не линкуется с ними:
 * qemu_init() можно вызвать в образе ровно один раз (после остановки ВМ
 * глобальное состояние QEMU остаётся грязным), поэтому каждый запуск ВМ
 * получает свежезагруженную копию dylib.  См. A5QemuLoader в приложении.
 *
 * Все коды клавиш и кнопок здесь — собственные, не QKeyCode: QKeyCode
 * генерируется из qapi и может переставиться при смене версии QEMU, а этот
 * ABI должен переживать такое молча.  Отображение в QKeyCode — в a5_qemu.c.
 */

#ifndef A5_QEMU_H
#define A5_QEMU_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Версия ABI.  Приложение сверяет её после dlopen и отказывается работать с
 * несовпадающей библиотекой, вместо того чтобы падать на несовместимости. */
#define A5_QEMU_ABI_VERSION 1

/* ------------------------------------------------------------------ */
/* Кадр гостевого экрана                                               */
/* ------------------------------------------------------------------ */

typedef struct {
    const void *pixels;       /* 32 бита на пиксель, little-endian BGRA */
    int32_t     width;
    int32_t     height;
    int32_t     stride;       /* байт в строке; может быть > width*4 */
    int32_t     bits_per_pixel;
} a5_qemu_frame;

/*
 * Вызывается из потока QEMU при каждом обновлении экрана.  Буфер живёт
 * только на время вызова — потребитель обязан скопировать то, что ему нужно,
 * до возврата.
 */
typedef void (*a5_qemu_frame_callback)(void *context, const a5_qemu_frame *frame);

/*
 * Вызывается из потока QEMU ровно один раз, когда ВМ окончательно
 * остановилась: гость выключился, произошла ошибка запуска или было
 * запрошено завершение.  `message` — NULL при штатной остановке.
 */
typedef void (*a5_qemu_stopped_callback)(void *context, const char *message);

/* ------------------------------------------------------------------ */
/* Клавиатура                                                          */
/* ------------------------------------------------------------------ */

typedef enum {
    A5_KEY_NONE = 0,

    A5_KEY_A, A5_KEY_B, A5_KEY_C, A5_KEY_D, A5_KEY_E, A5_KEY_F, A5_KEY_G,
    A5_KEY_H, A5_KEY_I, A5_KEY_J, A5_KEY_K, A5_KEY_L, A5_KEY_M, A5_KEY_N,
    A5_KEY_O, A5_KEY_P, A5_KEY_Q, A5_KEY_R, A5_KEY_S, A5_KEY_T, A5_KEY_U,
    A5_KEY_V, A5_KEY_W, A5_KEY_X, A5_KEY_Y, A5_KEY_Z,

    A5_KEY_0, A5_KEY_1, A5_KEY_2, A5_KEY_3, A5_KEY_4,
    A5_KEY_5, A5_KEY_6, A5_KEY_7, A5_KEY_8, A5_KEY_9,

    A5_KEY_MINUS, A5_KEY_EQUAL, A5_KEY_BRACKET_LEFT, A5_KEY_BRACKET_RIGHT,
    A5_KEY_BACKSLASH, A5_KEY_SEMICOLON, A5_KEY_APOSTROPHE, A5_KEY_GRAVE,
    A5_KEY_COMMA, A5_KEY_DOT, A5_KEY_SLASH,

    A5_KEY_SPACE, A5_KEY_RETURN, A5_KEY_BACKSPACE, A5_KEY_TAB, A5_KEY_ESC,

    A5_KEY_SHIFT, A5_KEY_SHIFT_R, A5_KEY_CTRL, A5_KEY_CTRL_R,
    A5_KEY_ALT, A5_KEY_ALT_R, A5_KEY_META, A5_KEY_MENU, A5_KEY_CAPS_LOCK,

    A5_KEY_F1, A5_KEY_F2, A5_KEY_F3, A5_KEY_F4, A5_KEY_F5, A5_KEY_F6,
    A5_KEY_F7, A5_KEY_F8, A5_KEY_F9, A5_KEY_F10, A5_KEY_F11, A5_KEY_F12,

    A5_KEY_UP, A5_KEY_DOWN, A5_KEY_LEFT, A5_KEY_RIGHT,
    A5_KEY_INSERT, A5_KEY_DELETE, A5_KEY_HOME, A5_KEY_END,
    A5_KEY_PAGE_UP, A5_KEY_PAGE_DOWN,

    A5_KEY_NUM_LOCK, A5_KEY_SCROLL_LOCK, A5_KEY_PRINT, A5_KEY_PAUSE,

    A5_KEY_KP_0, A5_KEY_KP_1, A5_KEY_KP_2, A5_KEY_KP_3, A5_KEY_KP_4,
    A5_KEY_KP_5, A5_KEY_KP_6, A5_KEY_KP_7, A5_KEY_KP_8, A5_KEY_KP_9,
    A5_KEY_KP_ADD, A5_KEY_KP_SUBTRACT, A5_KEY_KP_MULTIPLY,
    A5_KEY_KP_DIVIDE, A5_KEY_KP_ENTER, A5_KEY_KP_DECIMAL,

    A5_KEY_COUNT
} a5_qemu_key;

/* Битовая маска кнопок мыши для a5_qemu_send_pointer(). */
enum {
    A5_BUTTON_LEFT   = 1 << 0,
    A5_BUTTON_RIGHT  = 1 << 1,
    A5_BUTTON_MIDDLE = 1 << 2
};

/* ------------------------------------------------------------------ */
/* Управление                                                          */
/* ------------------------------------------------------------------ */

/* Версия ABI этой конкретной библиотеки. */
int32_t a5_qemu_abi_version(void);

/*
 * Задать обработчики.  Вызывать до a5_qemu_start().  Оба могут быть NULL.
 */
void a5_qemu_set_callbacks(a5_qemu_frame_callback frame_callback,
                           a5_qemu_stopped_callback stopped_callback,
                           void *context);

/*
 * Запустить ВМ: создаёт поток, в котором выполняется qemu_init(), затем
 * регистрирует слушатель экрана и входит в qemu_main_loop().
 *
 * Возвращает 0, если поток создан.  Ошибки самого QEMU приходят позже,
 * через stopped_callback — на этом этапе они ещё не известны.
 *
 * argv должен быть валидной командной строкой QEMU: при неприемлемых
 * аргументах qemu_init() зовёт exit() и уносит с собой весь процесс.
 * Формированием argv занимается A5QemuArguments на стороне приложения.
 */
int32_t a5_qemu_start(int32_t argc, const char *const *argv);

/* ACPI-выключение (гость увидит нажатие кнопки питания). */
void a5_qemu_request_shutdown(void);

/* Немедленный сброс, как кнопка Reset. */
void a5_qemu_request_reset(void);

/* Жёсткое завершение работы ВМ без участия гостя. */
void a5_qemu_request_quit(void);

/* Приостановить/возобновить исполнение гостя. */
void a5_qemu_set_paused(int32_t paused);

/* 1, пока поток QEMU жив. */
int32_t a5_qemu_is_running(void);

/* ------------------------------------------------------------------ */
/* Ввод                                                                */
/* ------------------------------------------------------------------ */

void a5_qemu_send_key(a5_qemu_key key, int32_t down);

/*
 * Отправить событие указателя.  При absolute != 0 x/y — координаты в
 * пикселях гостевого экрана; иначе это относительное смещение.
 * `buttons` — маска A5_BUTTON_*, описывающая состояние ПОСЛЕ события.
 */
void a5_qemu_send_pointer(int32_t x, int32_t y, int32_t buttons, int32_t absolute);

#ifdef __cplusplus
}
#endif

#endif /* A5_QEMU_H */

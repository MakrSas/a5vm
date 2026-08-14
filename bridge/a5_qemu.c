/*
 * a5_qemu.c — реализация моста A5VM внутри дерева QEMU.
 *
 * Этот файл копируется сборочным скриптом в ui/ дерева QEMU и добавляется в
 * ui/Makefile.objs, чтобы компилироваться теми же флагами и с теми же
 * заголовками, что и остальной QEMU.  Именно в этом смысл: приложению не
 * приходится вручную повторять layout DisplaySurface, DisplayChangeListener
 * и прочих внутренних структур — самое хрупкое место в подобных мостах, где
 * несовпадение молча портит память вместо честной ошибки компоновки.
 *
 * Модель потоков повторяет ui/cocoa.m, единственный поддерживаемый в QEMU
 * пример «UI на главном потоке, QEMU на отдельном»:
 *
 *   - поток QEMU выполняет qemu_init() → qemu_main_loop() → qemu_cleanup();
 *   - qemu_init() захватывает BQL (softmmu/vl.c) и не отпускает его, так что
 *     после её возврата слушатель экрана регистрируется уже под блокировкой;
 *   - главный поток (UIKit) при любом обращении к состоянию гостя берёт BQL
 *     сам — main_loop_wait() отпускает её на время опроса, так что взаимной
 *     блокировки не возникает.
 */

#include "qemu/osdep.h"
#include "qemu-common.h"
#include "qemu/main-loop.h"
#include "sysemu/sysemu.h"
#include "sysemu/runstate.h"
#include "ui/console.h"
#include "ui/input.h"

#include <pthread.h>

#include "a5_qemu.h"

/* ------------------------------------------------------------------ */
/* Состояние                                                           */
/* ------------------------------------------------------------------ */

static DisplayChangeListener     a5_dcl;
static a5_qemu_frame_callback    a5_frame_callback;
static a5_qemu_stopped_callback  a5_stopped_callback;
static void                     *a5_callback_context;

static int      a5_argc;
static char   **a5_argv;
static bool     a5_thread_running;
/*
 * Отдельно от a5_thread_running: поток считается запущенным сразу, но
 * консоль и BQL появляются только после возврата из qemu_init().  До этого
 * момента ни одно обращение к состоянию гостя недопустимо — блокировка ещё
 * не инициализирована, а a5_dcl.con равен NULL, и qemu_console_surface()
 * по нему разыменует нулевой указатель.
 */
static bool     a5_display_ready;
static bool     a5_surface_dirty;
static uint32_t a5_button_state;

/*
 * Очередь ввода.
 *
 * Раньше отправка клавиш и указателя бралась за BQL прямо из главного
 * потока UIKit, как это делает ui/cocoa.m. На настольной macOS так можно, а
 * здесь нельзя: если поток QEMU почему-либо застревает, удерживая BQL, то
 * следом намертво встаёт и главный поток приложения — вместо неработающей
 * ВМ пользователь получает неработающий телефон.
 *
 * Поэтому UI только кладёт события в этот кольцевой буфер под собственным
 * мьютексом (который никто не держит дольше нескольких инструкций), а
 * разбирает их поток QEMU в dpy_refresh, где BQL уже взят. Задержка — не
 * больше интервала обновления экрана, зато зависнуть UI не может в
 * принципе. Переполнение осознанно теряет самые старые события: свежие
 * важнее, а расти буферу некуда.
 */
enum {
    A5_INPUT_KEY,
    A5_INPUT_POINTER,
    A5_INPUT_PAUSE
};

typedef struct {
    int32_t kind;
    int32_t a, b, c, d;
} a5_input_event;

#define A5_INPUT_QUEUE_SIZE 512

static a5_input_event  a5_input_queue[A5_INPUT_QUEUE_SIZE];
static unsigned        a5_input_head;   /* откуда читаем */
static unsigned        a5_input_count;  /* сколько лежит */
static pthread_mutex_t a5_input_mutex = PTHREAD_MUTEX_INITIALIZER;

static void a5_input_push(int32_t kind, int32_t a, int32_t b,
                          int32_t c, int32_t d)
{
    a5_input_event *slot;

    pthread_mutex_lock(&a5_input_mutex);
    if (a5_input_count == A5_INPUT_QUEUE_SIZE) {
        /* Буфер полон — выбрасываем самое старое событие. */
        a5_input_head = (a5_input_head + 1) % A5_INPUT_QUEUE_SIZE;
        a5_input_count--;
    }
    slot = &a5_input_queue[(a5_input_head + a5_input_count) % A5_INPUT_QUEUE_SIZE];
    slot->kind = kind;
    slot->a = a;
    slot->b = b;
    slot->c = c;
    slot->d = d;
    a5_input_count++;
    pthread_mutex_unlock(&a5_input_mutex);
}

static bool a5_input_pop(a5_input_event *event)
{
    bool found = false;

    pthread_mutex_lock(&a5_input_mutex);
    if (a5_input_count > 0) {
        *event = a5_input_queue[a5_input_head];
        a5_input_head = (a5_input_head + 1) % A5_INPUT_QUEUE_SIZE;
        a5_input_count--;
        found = true;
    }
    pthread_mutex_unlock(&a5_input_mutex);
    return found;
}

/* ------------------------------------------------------------------ */
/* Экран                                                               */
/* ------------------------------------------------------------------ */

static void a5_gfx_update(DisplayChangeListener *dcl, int x, int y, int w, int h)
{
    a5_surface_dirty = true;
}

static void a5_gfx_switch(DisplayChangeListener *dcl, DisplaySurface *surface)
{
    /* Смена видеорежима гостем: следующий refresh отдаст кадр нового размера. */
    a5_surface_dirty = true;
}

/* Определён ниже, рядом с таблицей кодов клавиш. */
static void a5_input_drain(void);

static void a5_refresh(DisplayChangeListener *dcl)
{
    DisplaySurface *surface;
    a5_qemu_frame frame;

    /* Единственное место, где события ввода попадают в гостя: здесь мы уже
     * в потоке QEMU и под BQL. */
    a5_input_drain();

    /* Заставляем видеоустройство перерисовать содержимое в поверхность —
     * без этого dpy_gfx_update не придёт вовсе. */
    graphic_hw_update(dcl->con);

    if (!a5_surface_dirty || !a5_frame_callback) {
        return;
    }
    a5_surface_dirty = false;

    surface = qemu_console_surface(dcl->con);
    if (!surface) {
        return;
    }

    frame.pixels         = surface_data(surface);
    frame.width          = surface_width(surface);
    frame.height         = surface_height(surface);
    frame.stride         = surface_stride(surface);
    frame.bits_per_pixel = surface_bits_per_pixel(surface);

    if (frame.pixels && frame.width > 0 && frame.height > 0) {
        a5_frame_callback(a5_callback_context, &frame);
    }
}

static const DisplayChangeListenerOps a5_dcl_ops = {
    .dpy_name       = "a5vm",
    .dpy_gfx_update = a5_gfx_update,
    .dpy_gfx_switch = a5_gfx_switch,
    .dpy_refresh    = a5_refresh,
};

/* ------------------------------------------------------------------ */
/* Поток QEMU                                                          */
/* ------------------------------------------------------------------ */

static void *a5_qemu_thread(void *opaque)
{
    /* Если argv некорректен, qemu_init() печатает ошибку и зовёт exit(),
     * унося весь процесс.  Перехватить это отсюда нельзя — argv обязан быть
     * заведомо валидным, этим занимается A5Machine+QEMU на стороне UI. */
    qemu_init(a5_argc, a5_argv, NULL);

    /* BQL взят внутри qemu_init() и не отпущен — регистрируемся под ним. */
    a5_dcl.ops = &a5_dcl_ops;
    a5_dcl.con = qemu_console_lookup_by_index(0);
    register_displaychangelistener(&a5_dcl);
    a5_display_ready = true;

    qemu_main_loop();
    qemu_cleanup();

    a5_display_ready = false;
    a5_thread_running = false;
    if (a5_stopped_callback) {
        a5_stopped_callback(a5_callback_context, NULL);
    }
    return NULL;
}

/* ------------------------------------------------------------------ */
/* Публичный ABI                                                       */
/* ------------------------------------------------------------------ */

int32_t a5_qemu_abi_version(void)
{
    return A5_QEMU_ABI_VERSION;
}

void a5_qemu_set_callbacks(a5_qemu_frame_callback frame_callback,
                           a5_qemu_stopped_callback stopped_callback,
                           void *context)
{
    a5_frame_callback   = frame_callback;
    a5_stopped_callback = stopped_callback;
    a5_callback_context = context;
}

int32_t a5_qemu_start(int32_t argc, const char *const *argv)
{
    pthread_attr_t attributes;
    pthread_t thread;
    int result;

    if (a5_thread_running) {
        return -1;
    }

    /* QEMU сохраняет указатели внутрь argv на всё время работы, поэтому
     * массив обязан пережить этот вызов; владение остаётся за вызывающим. */
    a5_argc = (int)argc;
    a5_argv = (char **)argv;

    if (pthread_attr_init(&attributes) != 0) {
        return -1;
    }
    pthread_attr_setdetachstate(&attributes, PTHREAD_CREATE_DETACHED);
    /* Стек по умолчанию для не-главного потока в iOS — 512 КБ.  Инициализация
     * устройств и block layer QEMU этого не гарантированно хватает, а падение
     * от переполнения стека выглядит как случайный крах в произвольном месте. */
    pthread_attr_setstacksize(&attributes, 8 * 1024 * 1024);

    a5_thread_running = true;
    result = pthread_create(&thread, &attributes, a5_qemu_thread, NULL);
    pthread_attr_destroy(&attributes);

    if (result != 0) {
        a5_thread_running = false;
        return -1;
    }
    return 0;
}

int32_t a5_qemu_is_running(void)
{
    return a5_thread_running ? 1 : 0;
}

void a5_qemu_request_shutdown(void)
{
    /* Штатное «нажатие кнопки питания»: гость сам завершает работу.  Функция
     * рассчитана на вызов из обработчика сигнала, блокировка ей не нужна. */
    qemu_system_powerdown_request();
}

void a5_qemu_request_reset(void)
{
    qemu_system_reset_request(SHUTDOWN_CAUSE_HOST_QMP_SYSTEM_RESET);
}

void a5_qemu_request_quit(void)
{
    qemu_system_shutdown_request(SHUTDOWN_CAUSE_HOST_UI);
}

void a5_qemu_set_paused(int32_t paused)
{
    /* Через ту же очередь, что и ввод: vm_stop/vm_start требуют BQL, а брать
     * её из главного потока приложения нельзя (см. комментарий к очереди). */
    a5_input_push(A5_INPUT_PAUSE, paused, 0, 0, 0);
}

/* ------------------------------------------------------------------ */
/* Ввод                                                                */
/* ------------------------------------------------------------------ */

static QKeyCode a5_key_to_qcode(a5_qemu_key key)
{
    switch (key) {
    case A5_KEY_A: return Q_KEY_CODE_A;
    case A5_KEY_B: return Q_KEY_CODE_B;
    case A5_KEY_C: return Q_KEY_CODE_C;
    case A5_KEY_D: return Q_KEY_CODE_D;
    case A5_KEY_E: return Q_KEY_CODE_E;
    case A5_KEY_F: return Q_KEY_CODE_F;
    case A5_KEY_G: return Q_KEY_CODE_G;
    case A5_KEY_H: return Q_KEY_CODE_H;
    case A5_KEY_I: return Q_KEY_CODE_I;
    case A5_KEY_J: return Q_KEY_CODE_J;
    case A5_KEY_K: return Q_KEY_CODE_K;
    case A5_KEY_L: return Q_KEY_CODE_L;
    case A5_KEY_M: return Q_KEY_CODE_M;
    case A5_KEY_N: return Q_KEY_CODE_N;
    case A5_KEY_O: return Q_KEY_CODE_O;
    case A5_KEY_P: return Q_KEY_CODE_P;
    case A5_KEY_Q: return Q_KEY_CODE_Q;
    case A5_KEY_R: return Q_KEY_CODE_R;
    case A5_KEY_S: return Q_KEY_CODE_S;
    case A5_KEY_T: return Q_KEY_CODE_T;
    case A5_KEY_U: return Q_KEY_CODE_U;
    case A5_KEY_V: return Q_KEY_CODE_V;
    case A5_KEY_W: return Q_KEY_CODE_W;
    case A5_KEY_X: return Q_KEY_CODE_X;
    case A5_KEY_Y: return Q_KEY_CODE_Y;
    case A5_KEY_Z: return Q_KEY_CODE_Z;

    case A5_KEY_0: return Q_KEY_CODE_0;
    case A5_KEY_1: return Q_KEY_CODE_1;
    case A5_KEY_2: return Q_KEY_CODE_2;
    case A5_KEY_3: return Q_KEY_CODE_3;
    case A5_KEY_4: return Q_KEY_CODE_4;
    case A5_KEY_5: return Q_KEY_CODE_5;
    case A5_KEY_6: return Q_KEY_CODE_6;
    case A5_KEY_7: return Q_KEY_CODE_7;
    case A5_KEY_8: return Q_KEY_CODE_8;
    case A5_KEY_9: return Q_KEY_CODE_9;

    case A5_KEY_MINUS:         return Q_KEY_CODE_MINUS;
    case A5_KEY_EQUAL:         return Q_KEY_CODE_EQUAL;
    case A5_KEY_BRACKET_LEFT:  return Q_KEY_CODE_BRACKET_LEFT;
    case A5_KEY_BRACKET_RIGHT: return Q_KEY_CODE_BRACKET_RIGHT;
    case A5_KEY_BACKSLASH:     return Q_KEY_CODE_BACKSLASH;
    case A5_KEY_SEMICOLON:     return Q_KEY_CODE_SEMICOLON;
    case A5_KEY_APOSTROPHE:    return Q_KEY_CODE_APOSTROPHE;
    case A5_KEY_GRAVE:         return Q_KEY_CODE_GRAVE_ACCENT;
    case A5_KEY_COMMA:         return Q_KEY_CODE_COMMA;
    case A5_KEY_DOT:           return Q_KEY_CODE_DOT;
    case A5_KEY_SLASH:         return Q_KEY_CODE_SLASH;

    case A5_KEY_SPACE:     return Q_KEY_CODE_SPC;
    case A5_KEY_RETURN:    return Q_KEY_CODE_RET;
    case A5_KEY_BACKSPACE: return Q_KEY_CODE_BACKSPACE;
    case A5_KEY_TAB:       return Q_KEY_CODE_TAB;
    case A5_KEY_ESC:       return Q_KEY_CODE_ESC;

    case A5_KEY_SHIFT:     return Q_KEY_CODE_SHIFT;
    case A5_KEY_SHIFT_R:   return Q_KEY_CODE_SHIFT_R;
    case A5_KEY_CTRL:      return Q_KEY_CODE_CTRL;
    case A5_KEY_CTRL_R:    return Q_KEY_CODE_CTRL_R;
    case A5_KEY_ALT:       return Q_KEY_CODE_ALT;
    case A5_KEY_ALT_R:     return Q_KEY_CODE_ALT_R;
    case A5_KEY_META:      return Q_KEY_CODE_META_L;
    case A5_KEY_MENU:      return Q_KEY_CODE_MENU;
    case A5_KEY_CAPS_LOCK: return Q_KEY_CODE_CAPS_LOCK;

    case A5_KEY_F1:  return Q_KEY_CODE_F1;
    case A5_KEY_F2:  return Q_KEY_CODE_F2;
    case A5_KEY_F3:  return Q_KEY_CODE_F3;
    case A5_KEY_F4:  return Q_KEY_CODE_F4;
    case A5_KEY_F5:  return Q_KEY_CODE_F5;
    case A5_KEY_F6:  return Q_KEY_CODE_F6;
    case A5_KEY_F7:  return Q_KEY_CODE_F7;
    case A5_KEY_F8:  return Q_KEY_CODE_F8;
    case A5_KEY_F9:  return Q_KEY_CODE_F9;
    case A5_KEY_F10: return Q_KEY_CODE_F10;
    case A5_KEY_F11: return Q_KEY_CODE_F11;
    case A5_KEY_F12: return Q_KEY_CODE_F12;

    case A5_KEY_UP:        return Q_KEY_CODE_UP;
    case A5_KEY_DOWN:      return Q_KEY_CODE_DOWN;
    case A5_KEY_LEFT:      return Q_KEY_CODE_LEFT;
    case A5_KEY_RIGHT:     return Q_KEY_CODE_RIGHT;
    case A5_KEY_INSERT:    return Q_KEY_CODE_INSERT;
    case A5_KEY_DELETE:    return Q_KEY_CODE_DELETE;
    case A5_KEY_HOME:      return Q_KEY_CODE_HOME;
    case A5_KEY_END:       return Q_KEY_CODE_END;
    case A5_KEY_PAGE_UP:   return Q_KEY_CODE_PGUP;
    case A5_KEY_PAGE_DOWN: return Q_KEY_CODE_PGDN;

    case A5_KEY_NUM_LOCK:    return Q_KEY_CODE_NUM_LOCK;
    case A5_KEY_SCROLL_LOCK: return Q_KEY_CODE_SCROLL_LOCK;
    case A5_KEY_PRINT:       return Q_KEY_CODE_PRINT;
    case A5_KEY_PAUSE:       return Q_KEY_CODE_PAUSE;

    case A5_KEY_KP_0: return Q_KEY_CODE_KP_0;
    case A5_KEY_KP_1: return Q_KEY_CODE_KP_1;
    case A5_KEY_KP_2: return Q_KEY_CODE_KP_2;
    case A5_KEY_KP_3: return Q_KEY_CODE_KP_3;
    case A5_KEY_KP_4: return Q_KEY_CODE_KP_4;
    case A5_KEY_KP_5: return Q_KEY_CODE_KP_5;
    case A5_KEY_KP_6: return Q_KEY_CODE_KP_6;
    case A5_KEY_KP_7: return Q_KEY_CODE_KP_7;
    case A5_KEY_KP_8: return Q_KEY_CODE_KP_8;
    case A5_KEY_KP_9: return Q_KEY_CODE_KP_9;

    case A5_KEY_KP_ADD:      return Q_KEY_CODE_KP_ADD;
    case A5_KEY_KP_SUBTRACT: return Q_KEY_CODE_KP_SUBTRACT;
    case A5_KEY_KP_MULTIPLY: return Q_KEY_CODE_KP_MULTIPLY;
    case A5_KEY_KP_DIVIDE:   return Q_KEY_CODE_KP_DIVIDE;
    case A5_KEY_KP_ENTER:    return Q_KEY_CODE_KP_ENTER;
    case A5_KEY_KP_DECIMAL:  return Q_KEY_CODE_KP_DECIMAL;

    default: return Q_KEY_CODE_UNMAPPED;
    }
}

/* Публичные функции ввода только кладут события в очередь — см. комментарий
 * к ней выше.  Ничего от QEMU здесь не трогается, поэтому вызывать их можно
 * из любого потока и в любой момент, даже до запуска ВМ. */

void a5_qemu_send_key(a5_qemu_key key, int32_t down)
{
    a5_input_push(A5_INPUT_KEY, key, down, 0, 0);
}

void a5_qemu_send_pointer(int32_t x, int32_t y, int32_t buttons, int32_t absolute)
{
    a5_input_push(A5_INPUT_POINTER, x, y, buttons, absolute);
}

/* Дальше — сторона потока QEMU: вызывается из a5_refresh под BQL. */

static void a5_apply_key(a5_qemu_key key, bool down)
{
    QKeyCode qcode = a5_key_to_qcode(key);

    if (qcode != Q_KEY_CODE_UNMAPPED) {
        qemu_input_event_send_key_qcode(a5_dcl.con, qcode, down);
    }
}

static void a5_apply_pointer(int32_t x, int32_t y, int32_t buttons,
                             bool absolute)
{
    uint32_t wanted = 0;
    uint32_t changed;
    DisplaySurface *surface;

    if (buttons & A5_BUTTON_LEFT)   { wanted |= 1u << INPUT_BUTTON_LEFT; }
    if (buttons & A5_BUTTON_RIGHT)  { wanted |= 1u << INPUT_BUTTON_RIGHT; }
    if (buttons & A5_BUTTON_MIDDLE) { wanted |= 1u << INPUT_BUTTON_MIDDLE; }

    if (absolute) {
        /* Диапазон осей — реальный размер поверхности: qemu_input_queue_abs
         * сама пересчитает в 0..0x7FFF, который ждёт usb-tablet. */
        surface = qemu_console_surface(a5_dcl.con);
        if (surface) {
            qemu_input_queue_abs(a5_dcl.con, INPUT_AXIS_X, x, 0,
                                 surface_width(surface));
            qemu_input_queue_abs(a5_dcl.con, INPUT_AXIS_Y, y, 0,
                                 surface_height(surface));
        }
    } else if (x != 0 || y != 0) {
        qemu_input_queue_rel(a5_dcl.con, INPUT_AXIS_X, x);
        qemu_input_queue_rel(a5_dcl.con, INPUT_AXIS_Y, y);
    }

    /* Отправляем только изменения состояния кнопок: гость ждёт пары
     * нажатие/отпускание, а не повторяющееся «кнопка всё ещё нажата». */
    changed = wanted ^ a5_button_state;
    if (changed & (1u << INPUT_BUTTON_LEFT)) {
        qemu_input_queue_btn(a5_dcl.con, INPUT_BUTTON_LEFT,
                             (wanted & (1u << INPUT_BUTTON_LEFT)) != 0);
    }
    if (changed & (1u << INPUT_BUTTON_RIGHT)) {
        qemu_input_queue_btn(a5_dcl.con, INPUT_BUTTON_RIGHT,
                             (wanted & (1u << INPUT_BUTTON_RIGHT)) != 0);
    }
    if (changed & (1u << INPUT_BUTTON_MIDDLE)) {
        qemu_input_queue_btn(a5_dcl.con, INPUT_BUTTON_MIDDLE,
                             (wanted & (1u << INPUT_BUTTON_MIDDLE)) != 0);
    }
    a5_button_state = wanted;

    qemu_input_event_sync();
}

static void a5_input_drain(void)
{
    a5_input_event event;

    if (!a5_display_ready) {
        return;
    }

    while (a5_input_pop(&event)) {
        switch (event.kind) {
        case A5_INPUT_KEY:
            a5_apply_key((a5_qemu_key)event.a, event.b != 0);
            break;

        case A5_INPUT_POINTER:
            a5_apply_pointer(event.a, event.b, event.c, event.d != 0);
            break;

        case A5_INPUT_PAUSE:
            if (event.a) {
                if (runstate_is_running()) {
                    vm_stop(RUN_STATE_PAUSED);
                }
            } else if (!runstate_is_running()) {
                vm_start();
            }
            break;

        default:
            break;
        }
    }
}

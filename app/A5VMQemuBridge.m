#import "A5VMQemuBridge.h"
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>

#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/*
 * QEMU's own C entry points and the handful of types we touch, declared
 * by hand rather than #including QEMU's real headers. QEMU's headers
 * (ui/console.h, sysemu/runstate.h, ...) pull in its entire internal,
 * CONFIG_*-gated header tree, which is only meaningful compiled with the
 * exact flags/include paths ci/build-qemu-ios-armv7.sh used to build the
 * dylib itself -- not Makefile.ios's separate Theos build. A shared
 * library's consumer only needs its public C ABI, which is what this
 * declares, copied field-for-field/value-for-value from
 * third_party/qemu's headers and qapi schema files at the pinned submodule
 * commit (see HANDOFF.md). If a future QEMU submodule bump changes any
 * of these, this file needs updating to match.
 */

extern char **environ;

/* softmmu/main.c's normal entry sequence, exported because configure was
   run with --enable-shared-lib (see ci/build-qemu-ios-armv7.sh). */
extern void qemu_init(int argc, char **argv, char **envp);
extern void qemu_main_loop(void);
extern void qemu_cleanup(void);

/* include/sysemu/runstate.h */
typedef enum {
    RUN_STATE_DEBUG,
    RUN_STATE_INMIGRATE,
    RUN_STATE_INTERNAL_ERROR,
    RUN_STATE_IO_ERROR,
    RUN_STATE_PAUSED,
    RUN_STATE_POSTMIGRATE,
    RUN_STATE_PRELAUNCH,
    RUN_STATE_FINISH_MIGRATE,
    RUN_STATE_RESTORE_VM,
    RUN_STATE_RUNNING,
    RUN_STATE_SAVE_VM,
    RUN_STATE_SHUTDOWN,
    RUN_STATE_SUSPENDED,
    RUN_STATE_WATCHDOG,
    RUN_STATE_GUEST_PANICKED,
    RUN_STATE_COLO,
    RUN_STATE_PRECONFIG,
    RUN_STATE__MAX,
} A5VMRunState;

typedef enum {
    SHUTDOWN_CAUSE_NONE,
    SHUTDOWN_CAUSE_HOST_ERROR,
    SHUTDOWN_CAUSE_HOST_QMP_QUIT,
    SHUTDOWN_CAUSE_HOST_QMP_SYSTEM_RESET,
    SHUTDOWN_CAUSE_HOST_SIGNAL,
    SHUTDOWN_CAUSE_HOST_UI,
    SHUTDOWN_CAUSE_GUEST_SHUTDOWN,
    SHUTDOWN_CAUSE_GUEST_RESET,
    SHUTDOWN_CAUSE_GUEST_PANIC,
    SHUTDOWN_CAUSE_SUBSYSTEM_RESET,
} A5VMShutdownCause;

extern void vm_start(void);
extern int vm_stop(A5VMRunState state);
extern void qemu_system_reset_request(A5VMShutdownCause reason);
extern void qemu_system_powerdown_request(void);

/* qapi/ui.json's QKeyCode enum, in its exact declared order -- the
   integer values below are what qemu_input_event_send_key_qcode()
   actually reads, so the order (not the names) is what has to stay in
   sync with the submodule. */
typedef enum {
    Q_KEY_CODE_UNMAPPED,
    Q_KEY_CODE_SHIFT, Q_KEY_CODE_SHIFT_R, Q_KEY_CODE_ALT, Q_KEY_CODE_ALT_R,
    Q_KEY_CODE_CTRL, Q_KEY_CODE_CTRL_R, Q_KEY_CODE_MENU, Q_KEY_CODE_ESC,
    Q_KEY_CODE_1, Q_KEY_CODE_2, Q_KEY_CODE_3, Q_KEY_CODE_4, Q_KEY_CODE_5,
    Q_KEY_CODE_6, Q_KEY_CODE_7, Q_KEY_CODE_8, Q_KEY_CODE_9, Q_KEY_CODE_0,
    Q_KEY_CODE_MINUS, Q_KEY_CODE_EQUAL, Q_KEY_CODE_BACKSPACE, Q_KEY_CODE_TAB,
    Q_KEY_CODE_Q, Q_KEY_CODE_W, Q_KEY_CODE_E, Q_KEY_CODE_R, Q_KEY_CODE_T,
    Q_KEY_CODE_Y, Q_KEY_CODE_U, Q_KEY_CODE_I, Q_KEY_CODE_O, Q_KEY_CODE_P,
    Q_KEY_CODE_BRACKET_LEFT, Q_KEY_CODE_BRACKET_RIGHT, Q_KEY_CODE_RET,
    Q_KEY_CODE_A, Q_KEY_CODE_S, Q_KEY_CODE_D, Q_KEY_CODE_F, Q_KEY_CODE_G,
    Q_KEY_CODE_H, Q_KEY_CODE_J, Q_KEY_CODE_K, Q_KEY_CODE_L,
    Q_KEY_CODE_SEMICOLON, Q_KEY_CODE_APOSTROPHE, Q_KEY_CODE_GRAVE_ACCENT,
    Q_KEY_CODE_BACKSLASH, Q_KEY_CODE_Z, Q_KEY_CODE_X, Q_KEY_CODE_C,
    Q_KEY_CODE_V, Q_KEY_CODE_B, Q_KEY_CODE_N, Q_KEY_CODE_M, Q_KEY_CODE_COMMA,
    Q_KEY_CODE_DOT, Q_KEY_CODE_SLASH, Q_KEY_CODE_ASTERISK, Q_KEY_CODE_SPC,
    Q_KEY_CODE_CAPS_LOCK, Q_KEY_CODE_F1, Q_KEY_CODE_F2, Q_KEY_CODE_F3,
    Q_KEY_CODE_F4, Q_KEY_CODE_F5, Q_KEY_CODE_F6, Q_KEY_CODE_F7,
    Q_KEY_CODE_F8, Q_KEY_CODE_F9, Q_KEY_CODE_F10, Q_KEY_CODE_NUM_LOCK,
    Q_KEY_CODE_SCROLL_LOCK, Q_KEY_CODE_KP_DIVIDE, Q_KEY_CODE_KP_MULTIPLY,
    Q_KEY_CODE_KP_SUBTRACT, Q_KEY_CODE_KP_ADD, Q_KEY_CODE_KP_ENTER,
    Q_KEY_CODE_KP_DECIMAL, Q_KEY_CODE_SYSRQ, Q_KEY_CODE_KP_0,
    Q_KEY_CODE_KP_1, Q_KEY_CODE_KP_2, Q_KEY_CODE_KP_3, Q_KEY_CODE_KP_4,
    Q_KEY_CODE_KP_5, Q_KEY_CODE_KP_6, Q_KEY_CODE_KP_7, Q_KEY_CODE_KP_8,
    Q_KEY_CODE_KP_9, Q_KEY_CODE_LESS, Q_KEY_CODE_F11, Q_KEY_CODE_F12,
    Q_KEY_CODE_PRINT, Q_KEY_CODE_HOME, Q_KEY_CODE_PGUP, Q_KEY_CODE_PGDN,
    Q_KEY_CODE_END, Q_KEY_CODE_LEFT, Q_KEY_CODE_UP, Q_KEY_CODE_DOWN,
    Q_KEY_CODE_RIGHT, Q_KEY_CODE_INSERT, Q_KEY_CODE_DELETE, Q_KEY_CODE_STOP,
    Q_KEY_CODE_AGAIN, Q_KEY_CODE_PROPS, Q_KEY_CODE_UNDO, Q_KEY_CODE_FRONT,
    Q_KEY_CODE_COPY, Q_KEY_CODE_OPEN, Q_KEY_CODE_PASTE, Q_KEY_CODE_FIND,
    Q_KEY_CODE_CUT, Q_KEY_CODE_LF, Q_KEY_CODE_HELP, Q_KEY_CODE_META_L,
    Q_KEY_CODE_META_R, Q_KEY_CODE_COMPOSE, Q_KEY_CODE_PAUSE, Q_KEY_CODE_RO,
    Q_KEY_CODE_HIRAGANA, Q_KEY_CODE_HENKAN, Q_KEY_CODE_YEN,
    Q_KEY_CODE_MUHENKAN, Q_KEY_CODE_KATAKANAHIRAGANA, Q_KEY_CODE_KP_COMMA,
    Q_KEY_CODE_KP_EQUALS, Q_KEY_CODE_POWER, Q_KEY_CODE_SLEEP,
    Q_KEY_CODE_WAKE, Q_KEY_CODE_AUDIONEXT, Q_KEY_CODE_AUDIOPREV,
    Q_KEY_CODE_AUDIOSTOP, Q_KEY_CODE_AUDIOPLAY, Q_KEY_CODE_AUDIOMUTE,
    Q_KEY_CODE_VOLUMEUP, Q_KEY_CODE_VOLUMEDOWN, Q_KEY_CODE_MEDIASELECT,
    Q_KEY_CODE_MAIL, Q_KEY_CODE_CALCULATOR, Q_KEY_CODE_COMPUTER,
    Q_KEY_CODE_AC_HOME, Q_KEY_CODE_AC_BACK, Q_KEY_CODE_AC_FORWARD,
    Q_KEY_CODE_AC_REFRESH, Q_KEY_CODE_AC_BOOKMARKS,
} A5VMQKeyCode;

typedef struct A5VMQemuConsole A5VMQemuConsole; /* opaque QemuConsole * */

extern A5VMQemuConsole *qemu_console_lookup_by_index(unsigned int index);
extern void qemu_input_event_send_key_qcode(A5VMQemuConsole *src,
                                            A5VMQKeyCode q, _Bool down);

/* include/ui/console.h. DisplaySurface has no #ifdef CONFIG_OPENGL tail
   fields in this build (--disable-opengl, see ci/build-qemu-ios-armv7.sh). */
typedef struct {
    int format;      /* pixman_format_code_t; assumed PIXMAN_x8r8g8b8 below */
    void *image;     /* pixman_image_t * */
    unsigned char flags;
} A5VMDisplaySurface;

typedef struct A5VMDisplayChangeListener A5VMDisplayChangeListener;

typedef struct {
    const char *dpy_name;
    void (*dpy_refresh)(A5VMDisplayChangeListener *dcl);
    void (*dpy_gfx_update)(A5VMDisplayChangeListener *dcl,
                           int x, int y, int w, int h);
    void (*dpy_gfx_switch)(A5VMDisplayChangeListener *dcl,
                           A5VMDisplaySurface *new_surface);
    void *dpy_gfx_check_format;
    void *dpy_text_cursor;
    void *dpy_text_resize;
    void *dpy_text_update;
    void *dpy_mouse_set;
    void *dpy_cursor_define;
    void *dpy_gl_ctx_create;
    void *dpy_gl_ctx_destroy;
    void *dpy_gl_ctx_make_current;
    void *dpy_gl_ctx_get_current;
    void *dpy_gl_scanout_disable;
    void *dpy_gl_scanout_texture;
    void *dpy_gl_scanout_dmabuf;
    void *dpy_gl_cursor_dmabuf;
    void *dpy_gl_cursor_position;
    void *dpy_gl_release_dmabuf;
    void *dpy_gl_update;
} A5VMDisplayChangeListenerOps;

struct A5VMDisplayChangeListener {
    uint64_t update_interval;
    const A5VMDisplayChangeListenerOps *ops;
    void *ds;   /* DisplayState *, unused here */
    A5VMQemuConsole *con;
    void *next_prev, *next_next; /* QLIST_ENTRY(DisplayChangeListener) */
};

extern void register_displaychangelistener(A5VMDisplayChangeListener *dcl);
extern void unregister_displaychangelistener(A5VMDisplayChangeListener *dcl);
extern A5VMDisplaySurface *qemu_console_surface(A5VMQemuConsole *con);

/* pixman's own long-stable public API. Statically linked into
   libqemu-system-i386.dylib (ci/build-qemu-ios-armv7.sh builds it as a
   static dependency), so these symbols resolve from that same dylib. */
extern void *pixman_image_get_data(void *image);
extern int pixman_image_get_width(void *image);
extern int pixman_image_get_height(void *image);
extern int pixman_image_get_stride(void *image);

/* Wraps the DisplayChangeListener QEMU owns and mutates so our callbacks
   -- plain C functions, not ObjC methods -- can recover the
   A5VMQemuBridge instance that registered it. Must start with the
   A5VMDisplayChangeListener itself: register_displaychangelistener()
   only ever sees/touches that leading member, so a pointer to it and a
   pointer to this whole struct are interchangeable, the standard C
   idiom for attaching userdata to a fixed-layout callback struct. */
typedef struct {
    A5VMDisplayChangeListener dcl;
    A5VMQemuBridge *bridge; /* unretained: the bridge outlives its thread */
} A5VMDisplayListener;

static void A5VMQemuDeliverImage(A5VMQemuBridge *bridge, A5VMDisplaySurface *surface);

static void A5VMQemuDisplayGfxUpdate(A5VMDisplayChangeListener *dcl,
                                     int x, int y, int w, int h) {
    (void)x; (void)y; (void)w; (void)h;
    A5VMDisplayListener *listener = (A5VMDisplayListener *)dcl;
    A5VMDisplaySurface *surface = qemu_console_surface(dcl->con);
    if (surface) A5VMQemuDeliverImage(listener->bridge, surface);
}

static void A5VMQemuDisplayGfxSwitch(A5VMDisplayChangeListener *dcl,
                                     A5VMDisplaySurface *new_surface) {
    A5VMDisplayListener *listener = (A5VMDisplayListener *)dcl;
    if (new_surface) A5VMQemuDeliverImage(listener->bridge, new_surface);
}

static const A5VMDisplayChangeListenerOps kA5VMDisplayOps = {
    .dpy_name = "a5vm",
    .dpy_gfx_update = A5VMQemuDisplayGfxUpdate,
    .dpy_gfx_switch = A5VMQemuDisplayGfxSwitch,
};

@interface A5VMQemuBridge ()
- (void)threadMain;
- (void)notifyFailure:(NSString *)message;
- (void)notifyStopped;
- (void)deliverImage:(UIImage *)image;
- (void)sendQCode:(A5VMQKeyCode)qcode shift:(BOOL)shift;
@end

static void A5VMQemuDeliverImage(A5VMQemuBridge *bridge, A5VMDisplaySurface *surface) {
    /* PIXMAN_x8r8g8b8 (QEMU's default VGA surface format): as a native
       32-bit word, 0xXXRRGGBB. On this little-endian ARM target that is
       byte order B,G,R,X in memory -- kCGBitmapByteOrder32Little combined
       with kCGImageAlphaNoneSkipFirst is the matching CoreGraphics
       description. If QEMU ever negotiates a different surface format
       here the colors will look wrong; nothing else about this path
       depends on the format. */
    int width = pixman_image_get_width(surface->image);
    int height = pixman_image_get_height(surface->image);
    int stride = pixman_image_get_stride(surface->image);
    void *data = pixman_image_get_data(surface->image);
    if (width <= 0 || height <= 0 || stride <= 0 || !data) return;

    NSData *pixelData = [NSData dataWithBytes:data length:(NSUInteger)(stride * height)];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)pixelData);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef cgImage = CGImageCreate((size_t)width, (size_t)height, 8, 32, (size_t)stride,
                                       colorSpace,
                                       kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst,
                                       provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    if (!cgImage) return;

    UIImage *image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    [bridge deliverImage:image];
}

static void *A5VMQemuThreadEntry(void *context) {
    A5VMQemuBridge *bridge = (A5VMQemuBridge *)context;
    [bridge threadMain];
    return NULL;
}

@implementation A5VMQemuBridge

@synthesize delegate = _delegate;

- (BOOL)isRunning {
    return _running;
}

- (BOOL)startWithArguments:(NSArray *)arguments {
    if (_startRequested) return NO;
    _startRequested = YES;

    NSMutableArray *fullArguments = [NSMutableArray arrayWithObject:@"a5vm-qemu"];
    [fullArguments addObjectsFromArray:arguments];
    NSUInteger count = [fullArguments count];
    char **argv = (char **)calloc(count + 1, sizeof(char *));
    if (!argv) {
        [self notifyFailure:@"Out of memory building QEMU arguments"];
        return NO;
    }
    for (NSUInteger i = 0; i < count; ++i) {
        argv[i] = strdup([[fullArguments objectAtIndex:i] UTF8String]);
    }
    argv[count] = NULL;

    _argv = argv;
    _argc = (int)count;

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    int result = pthread_create(&_thread, &attr, A5VMQemuThreadEntry, self);
    pthread_attr_destroy(&attr);
    if (result != 0) {
        for (int i = 0; i < _argc; ++i) free(_argv[i]);
        free(_argv);
        _argv = NULL;
        _argc = 0;
        [self notifyFailure:[NSString stringWithFormat:@"pthread_create failed (%d)", result]];
        return NO;
    }
    _running = YES;
    return YES;
}

- (void)threadMain {
    /*
     * qemu_init() parses argv itself; QEMU's own error paths for a bad
     * command line call exit()/error_report()+exit() directly rather
     * than returning an error we could catch here, which would tear
     * down the whole app process, not just this thread. There is no
     * supported way around that short of patching QEMU's option
     * parsing; callers must pass arguments qemu_init() already accepts
     * for a plain command-line invocation.
     */
    qemu_init(_argc, _argv, environ);

    A5VMQemuConsole *console = qemu_console_lookup_by_index(0);
    _console = console;

    A5VMDisplayListener *listener = (A5VMDisplayListener *)calloc(1, sizeof(A5VMDisplayListener));
    listener->dcl.ops = &kA5VMDisplayOps;
    listener->bridge = self;
    if (console) {
        listener->dcl.con = console;
        register_displaychangelistener(&listener->dcl);
    }
    _listener = listener;

    qemu_main_loop();

    if (console) {
        unregister_displaychangelistener(&listener->dcl);
    }
    free(listener);
    _listener = NULL;

    qemu_cleanup();

    for (int i = 0; i < _argc; ++i) free(_argv[i]);
    free(_argv);
    _argv = NULL;

    _running = NO;
    [self notifyStopped];
}

- (void)requestPowerDown {
    qemu_system_powerdown_request();
}

- (void)requestReset {
    qemu_system_reset_request(SHUTDOWN_CAUSE_HOST_UI);
}

- (void)pause {
    vm_stop(RUN_STATE_PAUSED);
}

- (void)resume {
    vm_start();
}

- (void)sendSpecialKey:(A5VMQemuSpecialKey)key down:(BOOL)down {
    if (!_console) return;
    A5VMQKeyCode qcode;
    switch (key) {
        case A5VMQemuKeyEscape:     qcode = Q_KEY_CODE_ESC; break;
        case A5VMQemuKeyTab:        qcode = Q_KEY_CODE_TAB; break;
        case A5VMQemuKeyReturn:     qcode = Q_KEY_CODE_RET; break;
        case A5VMQemuKeyBackspace:  qcode = Q_KEY_CODE_BACKSPACE; break;
        case A5VMQemuKeyLeftArrow:  qcode = Q_KEY_CODE_LEFT; break;
        case A5VMQemuKeyRightArrow: qcode = Q_KEY_CODE_RIGHT; break;
        case A5VMQemuKeyUpArrow:    qcode = Q_KEY_CODE_UP; break;
        case A5VMQemuKeyDownArrow:  qcode = Q_KEY_CODE_DOWN; break;
        default: return;
    }
    qemu_input_event_send_key_qcode((A5VMQemuConsole *)_console, qcode, down ? 1 : 0);
}

- (void)sendQCode:(A5VMQKeyCode)qcode shift:(BOOL)shift {
    if (!_console) return;
    A5VMQemuConsole *console = (A5VMQemuConsole *)_console;
    if (shift) qemu_input_event_send_key_qcode(console, Q_KEY_CODE_SHIFT, 1);
    qemu_input_event_send_key_qcode(console, qcode, 1);
    qemu_input_event_send_key_qcode(console, qcode, 0);
    if (shift) qemu_input_event_send_key_qcode(console, Q_KEY_CODE_SHIFT, 0);
}

- (void)sendCharacter:(unichar)character {
    if (!_console) return;
    struct { unichar ch; A5VMQKeyCode qcode; BOOL shift; } lower[] = {
        {'a', Q_KEY_CODE_A, NO}, {'b', Q_KEY_CODE_B, NO}, {'c', Q_KEY_CODE_C, NO},
        {'d', Q_KEY_CODE_D, NO}, {'e', Q_KEY_CODE_E, NO}, {'f', Q_KEY_CODE_F, NO},
        {'g', Q_KEY_CODE_G, NO}, {'h', Q_KEY_CODE_H, NO}, {'i', Q_KEY_CODE_I, NO},
        {'j', Q_KEY_CODE_J, NO}, {'k', Q_KEY_CODE_K, NO}, {'l', Q_KEY_CODE_L, NO},
        {'m', Q_KEY_CODE_M, NO}, {'n', Q_KEY_CODE_N, NO}, {'o', Q_KEY_CODE_O, NO},
        {'p', Q_KEY_CODE_P, NO}, {'q', Q_KEY_CODE_Q, NO}, {'r', Q_KEY_CODE_R, NO},
        {'s', Q_KEY_CODE_S, NO}, {'t', Q_KEY_CODE_T, NO}, {'u', Q_KEY_CODE_U, NO},
        {'v', Q_KEY_CODE_V, NO}, {'w', Q_KEY_CODE_W, NO}, {'x', Q_KEY_CODE_X, NO},
        {'y', Q_KEY_CODE_Y, NO}, {'z', Q_KEY_CODE_Z, NO},
        {'0', Q_KEY_CODE_0, NO}, {'1', Q_KEY_CODE_1, NO}, {'2', Q_KEY_CODE_2, NO},
        {'3', Q_KEY_CODE_3, NO}, {'4', Q_KEY_CODE_4, NO}, {'5', Q_KEY_CODE_5, NO},
        {'6', Q_KEY_CODE_6, NO}, {'7', Q_KEY_CODE_7, NO}, {'8', Q_KEY_CODE_8, NO},
        {'9', Q_KEY_CODE_9, NO},
        {' ', Q_KEY_CODE_SPC, NO}, {'-', Q_KEY_CODE_MINUS, NO},
        {'=', Q_KEY_CODE_EQUAL, NO}, {'[', Q_KEY_CODE_BRACKET_LEFT, NO},
        {']', Q_KEY_CODE_BRACKET_RIGHT, NO}, {';', Q_KEY_CODE_SEMICOLON, NO},
        {'\'', Q_KEY_CODE_APOSTROPHE, NO}, {'`', Q_KEY_CODE_GRAVE_ACCENT, NO},
        {'\\', Q_KEY_CODE_BACKSLASH, NO}, {',', Q_KEY_CODE_COMMA, NO},
        {'.', Q_KEY_CODE_DOT, NO}, {'/', Q_KEY_CODE_SLASH, NO},
        {'\t', Q_KEY_CODE_TAB, NO}, {'\r', Q_KEY_CODE_RET, NO}, {'\n', Q_KEY_CODE_RET, NO},
        {0x08, Q_KEY_CODE_BACKSPACE, NO}, {0x1B, Q_KEY_CODE_ESC, NO},
        {')', Q_KEY_CODE_0, YES}, {'!', Q_KEY_CODE_1, YES}, {'@', Q_KEY_CODE_2, YES},
        {'#', Q_KEY_CODE_3, YES}, {'$', Q_KEY_CODE_4, YES}, {'%', Q_KEY_CODE_5, YES},
        {'^', Q_KEY_CODE_6, YES}, {'&', Q_KEY_CODE_7, YES}, {'*', Q_KEY_CODE_8, YES},
        {'(', Q_KEY_CODE_9, YES}, {'_', Q_KEY_CODE_MINUS, YES}, {'+', Q_KEY_CODE_EQUAL, YES},
        {'{', Q_KEY_CODE_BRACKET_LEFT, YES}, {'}', Q_KEY_CODE_BRACKET_RIGHT, YES},
        {':', Q_KEY_CODE_SEMICOLON, YES}, {'"', Q_KEY_CODE_APOSTROPHE, YES},
        {'~', Q_KEY_CODE_GRAVE_ACCENT, YES}, {'|', Q_KEY_CODE_BACKSLASH, YES},
        {'<', Q_KEY_CODE_COMMA, YES}, {'>', Q_KEY_CODE_DOT, YES}, {'?', Q_KEY_CODE_SLASH, YES},
    };
    unichar lowered = (character >= 'A' && character <= 'Z') ? (character - 'A' + 'a') : character;
    BOOL uppercaseLetter = (character >= 'A' && character <= 'Z');
    for (size_t i = 0; i < sizeof(lower) / sizeof(lower[0]); ++i) {
        if (lower[i].ch == lowered) {
            [self sendQCode:lower[i].qcode shift:(uppercaseLetter || lower[i].shift)];
            return;
        }
    }
}

- (void)notifyFailure:(NSString *)message {
    _running = NO;
    id<A5VMQemuBridgeDelegate> delegate = _delegate;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([delegate respondsToSelector:@selector(qemuBridge:didFailWithMessage:)]) {
            [delegate qemuBridge:self didFailWithMessage:message];
        }
    });
}

- (void)notifyStopped {
    id<A5VMQemuBridgeDelegate> delegate = _delegate;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([delegate respondsToSelector:@selector(qemuBridgeDidStop:)]) {
            [delegate qemuBridgeDidStop:self];
        }
    });
}

- (void)deliverImage:(UIImage *)image {
    id<A5VMQemuBridgeDelegate> delegate = _delegate;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([delegate respondsToSelector:@selector(qemuBridge:didUpdateScreen:)]) {
            [delegate qemuBridge:self didUpdateScreen:image];
        }
    });
}

- (void)dealloc {
    /* Deliberately does not join/kill _thread: qemu_cleanup() must run
       to completion on QEMU's own terms before this object's memory
       (argv, listener) is safe to free, and there is no supported way
       to force qemu_main_loop() to return early other than the guest
       actually shutting down or -requestPowerDown succeeding. Callers
       must wait for -qemuBridgeDidStop: before releasing their last
       reference. */
    [super dealloc];
}

@end

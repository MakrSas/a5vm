#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <pthread.h>
#include <stdint.h>

/*
 * Bridges A5VM's UIKit runner to the QEMU shared library built by
 * ci/build-qemu-ios-armv7.sh (see docs/QEMU_BACKEND.md). Runs QEMU's
 * qemu_init()/qemu_main_loop()/qemu_cleanup() on a dedicated pthread,
 * forwards the VGA console's DisplayChangeListener updates to the
 * delegate as UIImages, and drives lifecycle/keyboard through QEMU's own
 * C API (vm_start/vm_stop/qemu_system_reset_request/
 * qemu_system_powerdown_request/qemu_input_event_send_key_qcode) rather
 * than QMP, since the bridge and QEMU share one process and address
 * space.
 *
 * Not yet wired into A5VMViewController -- see HANDOFF.md for what that
 * still needs (VM argument construction from the machine's stored
 * configuration, a raster-mode A5VMDisplayView, Run/Pause/Reset/Power
 * button wiring). This class is a complete, self-contained unit on its
 * own; nothing here depends on the rest of the app.
 */

typedef enum {
    A5VMQemuKeyEscape = 0,
    A5VMQemuKeyTab,
    A5VMQemuKeyReturn,
    A5VMQemuKeyBackspace,
    A5VMQemuKeyLeftArrow,
    A5VMQemuKeyRightArrow,
    A5VMQemuKeyUpArrow,
    A5VMQemuKeyDownArrow
} A5VMQemuSpecialKey;

@class A5VMQemuBridge;

@protocol A5VMQemuBridgeDelegate <NSObject>
@optional
/* Called on the main thread whenever the guest's VGA console repaints. */
- (void)qemuBridge:(A5VMQemuBridge *)bridge didUpdateScreen:(UIImage *)image;
/* Called on the main thread if starting or running QEMU fails. The
   bridge has already torn itself down by the time this fires. */
- (void)qemuBridge:(A5VMQemuBridge *)bridge didFailWithMessage:(NSString *)message;
/* Called on the main thread once qemu_main_loop() returns and cleanup
   has finished, whether from a guest shutdown or -shutdown/-powerDown. */
- (void)qemuBridgeDidStop:(A5VMQemuBridge *)bridge;
@end

@interface A5VMQemuBridge : NSObject {
    id<A5VMQemuBridgeDelegate> _delegate;
    BOOL _running;
    BOOL _startRequested;
    pthread_t _thread;
    void *_console;   /* QemuConsole *, opaque to callers */
    void *_listener;  /* our DisplayChangeListener wrapper, opaque to callers */
    char **_argv;
    int _argc;
}

@property (nonatomic, assign) id<A5VMQemuBridgeDelegate> delegate;
@property (nonatomic, readonly) BOOL isRunning;

/*
 * Starts QEMU on a background thread with the given command-line
 * arguments (do not include argv[0]; a placeholder program name is
 * added automatically). Returns immediately; -qemuBridge:didFailWithMessage:
 * or the first -qemuBridge:didUpdateScreen: report how it went.
 * May be called only once per instance -- create a new A5VMQemuBridge
 * for a fresh VM run.
 */
- (BOOL)startWithArguments:(NSArray *)arguments; /* of NSString */

/* Requests a guest ACPI shutdown; -qemuBridgeDidStop: fires once the
   main loop actually exits. Safe to call from any thread. */
- (void)requestPowerDown;
/* Requests an immediate guest reset (not a shutdown). Safe to call from
   any thread. */
- (void)requestReset;
/* Pauses/resumes guest CPU execution; the display stays live. Safe to
   call from any thread. */
- (void)pause;
- (void)resume;

/* Keyboard input, forwarded to the guest via QEMU's qcode input API.
   Safe to call from any thread. */
- (void)sendSpecialKey:(A5VMQemuSpecialKey)key down:(BOOL)down;
/* ASCII only; unmappable characters are silently ignored. Sends and
   releases the key (and any needed shift) as a single event. */
- (void)sendCharacter:(unichar)character;

@end

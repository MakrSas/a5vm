//
//  A5QemuRunner.m
//

#import "A5QemuRunner.h"
#import "a5_qemu.h"

#import <dlfcn.h>
#import <string.h>

static NSString *const A5QemuErrorDomain = @"A5VM.QEMU";

/// Указатели на функции ABI, разрешённые через dlsym.
typedef struct {
    int32_t (*abi_version)(void);
    void    (*set_callbacks)(a5_qemu_frame_callback, a5_qemu_stopped_callback, void *);
    int32_t (*start)(int32_t, const char *const *);
    void    (*request_shutdown)(void);
    void    (*request_reset)(void);
    void    (*request_quit)(void);
    void    (*set_paused)(int32_t);
    int32_t (*is_running)(void);
    void    (*send_key)(a5_qemu_key, int32_t);
    void    (*send_pointer)(int32_t, int32_t, int32_t, int32_t);
} A5QemuSymbols;

static void A5QemuFrameTrampoline(void *context, const a5_qemu_frame *frame);
static void A5QemuStoppedTrampoline(void *context, const char *message);

@interface A5QemuRunner ()
{
    void          *_handle;
    A5QemuSymbols  _symbols;
    NSString      *_imagePath;

    NSLock        *_frameLock;
    NSData        *_pendingFrame;      // защищено _frameLock
    CGSize         _pendingFrameSize;
    size_t         _pendingFrameStride;
    BOOL           _frameDeliveryScheduled;
}
/// Пока ВМ работает, runner держит ссылку сам на себя: поток QEMU обращается
/// к нему через сырой указатель, и он не должен исчезнуть, если контроллер
/// экрана уже закрыт и отпустил свою ссылку.
@property (nonatomic, strong) A5QemuRunner *selfReference;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) CGSize guestScreenSize;
@end

@implementation A5QemuRunner

#pragma mark - Загрузка

+ (instancetype)runnerWithError:(NSError **)error
{
    NSString *bundled = [[[NSBundle mainBundle] bundlePath]
                         stringByAppendingPathComponent:@"libqemu-system-i386.dylib"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:bundled]) {
        if (error) {
            *error = [NSError errorWithDomain:A5QemuErrorDomain code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"В бандле нет libqemu-system-i386.dylib."
            }];
        }
        return nil;
    }

    // Свежий путь на каждый запуск — иначе dyld вернёт уже загруженный образ
    // с грязными глобалами предыдущего прогона (см. комментарий в заголовке).
    static NSUInteger runCounter = 0;
    NSString *copyPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"a5vm-qemu-%lu-%lu.dylib",
                           (unsigned long)[[NSProcessInfo processInfo] processIdentifier],
                           (unsigned long)runCounter++]];
    [fileManager removeItemAtPath:copyPath error:NULL];

    NSError *copyError = nil;
    if (![fileManager copyItemAtPath:bundled toPath:copyPath error:&copyError]) {
        if (error) {
            *error = [NSError errorWithDomain:A5QemuErrorDomain code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"Не удалось подготовить копию QEMU.",
                NSUnderlyingErrorKey: copyError ?: [NSNull null]
            }];
        }
        return nil;
    }

    void *handle = dlopen([copyPath fileSystemRepresentation], RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        const char *message = dlerror();
        [fileManager removeItemAtPath:copyPath error:NULL];
        if (error) {
            *error = [NSError errorWithDomain:A5QemuErrorDomain code:3 userInfo:@{
                NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Не удалось загрузить QEMU: %s",
                     message ?: "неизвестная ошибка"]
            }];
        }
        return nil;
    }

    A5QemuRunner *runner = [[A5QemuRunner alloc] init];
    runner->_handle = handle;
    runner->_imagePath = [copyPath copy];

    if (![runner resolveSymbols]) {
        if (error) {
            *error = [NSError errorWithDomain:A5QemuErrorDomain code:4 userInfo:@{
                NSLocalizedDescriptionKey: @"В библиотеке QEMU нет ожидаемого интерфейса A5VM."
            }];
        }
        return nil;
    }

    int32_t version = runner->_symbols.abi_version();
    if (version != A5_QEMU_ABI_VERSION) {
        if (error) {
            *error = [NSError errorWithDomain:A5QemuErrorDomain code:5 userInfo:@{
                NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Версия QEMU в бандле (%d) не совпадает с приложением (%d).",
                     (int)version, (int)A5_QEMU_ABI_VERSION]
            }];
        }
        return nil;
    }

    return runner;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _frameLock = [[NSLock alloc] init];
        _guestScreenSize = CGSizeZero;
    }
    return self;
}

- (void)dealloc
{
    // dlclose не вызывается намеренно: поток QEMU мог не успеть до конца
    // размотаться, а выгрузка образа из-под работающего кода — гарантированный
    // крах.  Образ остаётся в процессе до его завершения; файл-копия удаляется.
    if (_imagePath) {
        [[NSFileManager defaultManager] removeItemAtPath:_imagePath error:NULL];
    }
}

- (BOOL)resolveSymbols
{
#define A5_RESOLVE(field, name)                                                \
    do {                                                                       \
        void *symbol = dlsym(_handle, name);                                   \
        if (!symbol) { return NO; }                                            \
        *(void **)(&_symbols.field) = symbol;                                  \
    } while (0)

    A5_RESOLVE(abi_version,      "a5_qemu_abi_version");
    A5_RESOLVE(set_callbacks,    "a5_qemu_set_callbacks");
    A5_RESOLVE(start,            "a5_qemu_start");
    A5_RESOLVE(request_shutdown, "a5_qemu_request_shutdown");
    A5_RESOLVE(request_reset,    "a5_qemu_request_reset");
    A5_RESOLVE(request_quit,     "a5_qemu_request_quit");
    A5_RESOLVE(set_paused,       "a5_qemu_set_paused");
    A5_RESOLVE(is_running,       "a5_qemu_is_running");
    A5_RESOLVE(send_key,         "a5_qemu_send_key");
    A5_RESOLVE(send_pointer,     "a5_qemu_send_pointer");
#undef A5_RESOLVE

    return YES;
}

#pragma mark - Запуск

- (BOOL)startWithArguments:(NSArray *)arguments error:(NSError **)error
{
    if (self.running) {
        return NO;
    }

    NSMutableArray *argv = [NSMutableArray arrayWithObject:@"qemu-system-i386"];
    [argv addObjectsFromArray:arguments];

    NSUInteger count = argv.count;
    const char **cArgv = calloc(count + 1, sizeof(char *));
    if (!cArgv) {
        return NO;
    }
    // Строки должны пережить вызов: QEMU разбирает argv в своём потоке уже
    // после того, как start() вернёт управление.  strdup, не -UTF8String,
    // чей буфер живёт лишь до слива autorelease pool.
    for (NSUInteger index = 0; index < count; index++) {
        cArgv[index] = strdup([argv[index] UTF8String]);
    }

    self.selfReference = self;
    self.running = YES;

    _symbols.set_callbacks(A5QemuFrameTrampoline, A5QemuStoppedTrampoline,
                           (__bridge void *)self);

    int32_t result = _symbols.start((int32_t)count, (const char *const *)cArgv);
    if (result != 0) {
        self.running = NO;
        self.selfReference = nil;
        for (NSUInteger index = 0; index < count; index++) {
            free((void *)cArgv[index]);
        }
        free(cArgv);
        if (error) {
            *error = [NSError errorWithDomain:A5QemuErrorDomain code:6 userInfo:@{
                NSLocalizedDescriptionKey: @"Не удалось создать поток QEMU."
            }];
        }
        return NO;
    }

    // cArgv и его строки намеренно не освобождаются: QEMU сохраняет указатели
    // на элементы argv (например, для -name и путей носителей) на всё время
    // работы, и живут они до конца процесса.
    return YES;
}

#pragma mark - Управление

- (void)requestShutdown { if (self.running) { _symbols.request_shutdown(); } }
- (void)requestReset    { if (self.running) { _symbols.request_reset(); } }
- (void)requestQuit     { if (self.running) { _symbols.request_quit(); } }

- (void)setPaused:(BOOL)paused
{
    if (self.running) {
        _symbols.set_paused(paused ? 1 : 0);
    }
}

- (void)sendKey:(int)key down:(BOOL)down
{
    if (self.running) {
        _symbols.send_key((a5_qemu_key)key, down ? 1 : 0);
    }
}

- (void)sendPointerAtX:(int)x y:(int)y buttons:(int)buttons absolute:(BOOL)absolute
{
    if (self.running) {
        _symbols.send_pointer(x, y, buttons, absolute ? 1 : 0);
    }
}

#pragma mark - Приём кадров (поток QEMU)

- (void)acceptFrame:(const a5_qemu_frame *)frame
{
    if (!frame || !frame->pixels || frame->bits_per_pixel != 32) {
        return;  // 8/16-битные режимы гость выставляет редко; пропускаем кадр
    }

    NSUInteger length = (NSUInteger)frame->stride * (NSUInteger)frame->height;
    NSData *data = [NSData dataWithBytes:frame->pixels length:length];

    BOOL needsDispatch = NO;
    [_frameLock lock];
    // Кадр всегда перезаписывает предыдущий неотрисованный: если UI не
    // успевает, лучше показать самый свежий, чем копить очередь.
    _pendingFrame = data;
    _pendingFrameSize = CGSizeMake(frame->width, frame->height);
    _pendingFrameStride = (size_t)frame->stride;
    if (!_frameDeliveryScheduled) {
        _frameDeliveryScheduled = YES;
        needsDispatch = YES;
    }
    [_frameLock unlock];

    if (needsDispatch) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self deliverPendingFrame];
        });
    }
}

- (void)deliverPendingFrame
{
    [_frameLock lock];
    NSData *data = _pendingFrame;
    CGSize size = _pendingFrameSize;
    size_t stride = _pendingFrameStride;
    _pendingFrame = nil;
    _frameDeliveryScheduled = NO;
    [_frameLock unlock];

    if (!data || size.width <= 0 || size.height <= 0) {
        return;
    }

    self.guestScreenSize = size;

    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    // Поверхность QEMU для VGA — PIXMAN_x8r8g8b8: на little-endian это байты
    // B, G, R, X.  Для CoreGraphics это ровно 32-bit little-endian с
    // игнорируемым старшим байтом.
    CGImageRef image = CGImageCreate((size_t)size.width, (size_t)size.height,
                                     8, 32, stride, colorSpace,
                                     (CGBitmapInfo)(kCGBitmapByteOrder32Little |
                                                    kCGImageAlphaNoneSkipFirst),
                                     provider, NULL, false,
                                     kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);

    if (image) {
        [self.delegate qemuRunner:self didProduceFrame:image];
        CGImageRelease(image);
    }
}

- (void)acceptStopWithMessage:(const char *)message
{
    NSString *text = message ? [NSString stringWithUTF8String:message] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.running = NO;
        NSError *error = nil;
        if (text.length > 0) {
            error = [NSError errorWithDomain:A5QemuErrorDomain code:7 userInfo:@{
                NSLocalizedDescriptionKey: text
            }];
        }
        [self.delegate qemuRunner:self didStopWithError:error];
        // Ссылка на себя снимается последней: до этого момента поток QEMU мог
        // ещё обращаться к объекту.
        self.selfReference = nil;
    });
}

@end

#pragma mark - Переходники из C

static void A5QemuFrameTrampoline(void *context, const a5_qemu_frame *frame)
{
    @autoreleasepool {
        [(__bridge A5QemuRunner *)context acceptFrame:frame];
    }
}

static void A5QemuStoppedTrampoline(void *context, const char *message)
{
    @autoreleasepool {
        [(__bridge A5QemuRunner *)context acceptStopWithMessage:message];
    }
}

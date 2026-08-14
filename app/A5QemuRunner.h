//
//  A5QemuRunner.h
//  Обёртка над libqemu-system-i386.dylib.
//
//  Библиотека загружается через dlopen, а не линкуется: qemu_init() можно
//  вызвать в одном загруженном образе ровно один раз — после остановки ВМ
//  глобальное состояние QEMU (зарегистрированные QOM-типы, block layer,
//  таймеры) остаётся грязным, и повторная инициализация падает.  Поэтому
//  каждый запуск ВМ работает со свежей копией dylib по новому пути: для dyld
//  это другой образ, со своими нулевыми глобалами.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class A5QemuRunner;

@protocol A5QemuRunnerDelegate <NSObject>
/// Новый кадр гостевого экрана.  Всегда на главном потоке.
- (void)qemuRunner:(A5QemuRunner *)runner didProduceFrame:(CGImageRef)image;
/// ВМ остановилась.  reason == nil — штатное выключение.  Главный поток.
- (void)qemuRunner:(A5QemuRunner *)runner didStopWithError:(NSError *)error;
@end

@interface A5QemuRunner : NSObject

@property (nonatomic, weak) id<A5QemuRunnerDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL running;
/// Размер гостевого экрана в пикселях; CGSizeZero до первого кадра.
@property (nonatomic, assign, readonly) CGSize guestScreenSize;

/// Загружает свежую копию QEMU.  Возвращает nil, если библиотеки нет в
/// бандле, её не удалось скопировать, dlopen провалился или у неё другая
/// версия ABI.
+ (instancetype)runnerWithError:(NSError **)error;

/// Запускает ВМ.  arguments — argv БЕЗ argv[0], он подставляется сам.
- (BOOL)startWithArguments:(NSArray *)arguments error:(NSError **)error;

- (void)requestShutdown;   // ACPI, гость увидит нажатие кнопки питания
- (void)requestReset;
- (void)requestQuit;       // жёстко, без участия гостя
- (void)setPaused:(BOOL)paused;

- (void)sendKey:(int)key down:(BOOL)down;
/// Координаты в пикселях гостевого экрана.
- (void)sendPointerAtX:(int)x y:(int)y buttons:(int)buttons absolute:(BOOL)absolute;

@end

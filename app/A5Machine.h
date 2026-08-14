//
//  A5Machine.h
//  Конфигурация одной виртуальной машины.
//
//  Модель намеренно "плоская": набор свойств, который сериализуется в
//  config.plist рядом с образами дисков этой машины.  Никаких зависимостей
//  на UIKit — этот класс используется и из бэкенда, который собирает argv.
//

#import <Foundation/Foundation.h>

/// Идентификаторы шаблонов гостевых ОС.  Значение хранится в config.plist,
/// поэтому строки менять нельзя без миграции.
extern NSString *const A5TemplateDOS;
extern NSString *const A5TemplateWindows31;
extern NSString *const A5TemplateWindows95;
extern NSString *const A5TemplateWindows98;
extern NSString *const A5TemplateCustom;

/// Порядок загрузки — буквы, которые понимает `-boot` в QEMU.
extern NSString *const A5BootFloppy;   // @"a"
extern NSString *const A5BootHardDisk; // @"c"
extern NSString *const A5BootCDROM;    // @"d"

@interface A5Machine : NSObject <NSCopying>

/// Имя каталога машины внутри Documents/Machines.  Генерируется при создании
/// и дальше не меняется, даже если пользователь переименует машину.
@property (nonatomic, copy, readonly) NSString *identifier;

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *templateIdentifier;

/// Объём памяти гостя в мегабайтах.  Ограничен разумным для 4S диапазоном —
/// см. +availableRAMSizes.
@property (nonatomic, assign) NSUInteger ramMegabytes;

/// Модель CPU в терминах `-cpu` QEMU: @"486", @"pentium", @"pentium2".
@property (nonatomic, copy) NSString *cpuModel;

/// Размер создаваемого образа жёсткого диска, МБ.  0 — диска нет.
@property (nonatomic, assign) NSUInteger hardDiskMegabytes;

/// Пути к сменным носителям.  Абсолютные; пустая строка/nil — слот пуст.
@property (nonatomic, copy) NSString *cdromPath;
@property (nonatomic, copy) NSString *floppyPath;

@property (nonatomic, copy) NSString *bootDevice;

/// Показывать ли гостю указатель как абсолютный (usb-tablet).  Для сенсорного
/// экрана это единственный удобный режим, но DOS-мыши его не понимают, поэтому
/// оставлена возможность переключиться на относительный PS/2.
@property (nonatomic, assign) BOOL usesAbsolutePointer;

#pragma mark - Жизненный цикл

/// Новая машина по шаблону, со значениями по умолчанию для этого шаблона.
+ (instancetype)machineWithTemplateIdentifier:(NSString *)templateIdentifier
                                         name:(NSString *)name;

/// Восстановление из содержимого config.plist.
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;

#pragma mark - Пути

/// Каталог машины: <Documents>/Machines/<identifier>.
@property (nonatomic, copy, readonly) NSString *directoryPath;
/// Образ жёсткого диска внутри каталога машины (может ещё не существовать).
@property (nonatomic, copy, readonly) NSString *hardDiskPath;

#pragma mark - Справочники для UI

+ (NSArray *)allTemplateIdentifiers;
+ (NSString *)displayNameForTemplate:(NSString *)templateIdentifier;
+ (NSArray *)availableRAMSizes;      // NSNumber, МБ
+ (NSArray *)availableDiskSizes;     // NSNumber, МБ
+ (NSArray *)availableCPUModels;     // NSString
+ (NSString *)displayNameForBootDevice:(NSString *)bootDevice;

/// Короткая строка для подзаголовка в списке машин: "Windows 98 · 64 МБ".
- (NSString *)summaryDescription;

@end

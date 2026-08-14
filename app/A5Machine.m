//
//  A5Machine.m
//

#import "A5Machine.h"

NSString *const A5TemplateDOS       = @"dos";
NSString *const A5TemplateWindows31 = @"win31";
NSString *const A5TemplateWindows95 = @"win95";
NSString *const A5TemplateWindows98 = @"win98";
NSString *const A5TemplateCustom    = @"custom";

NSString *const A5BootFloppy   = @"a";
NSString *const A5BootHardDisk = @"c";
NSString *const A5BootCDROM    = @"d";

static NSString *const A5KeyIdentifier   = @"identifier";
static NSString *const A5KeyName         = @"name";
static NSString *const A5KeyTemplate     = @"template";
static NSString *const A5KeyRAM          = @"ramMegabytes";
static NSString *const A5KeyCPU          = @"cpuModel";
static NSString *const A5KeyDiskSize     = @"hardDiskMegabytes";
static NSString *const A5KeyCDROM        = @"cdromPath";
static NSString *const A5KeyFloppy       = @"floppyPath";
static NSString *const A5KeyBoot         = @"bootDevice";
static NSString *const A5KeyAbsolute     = @"usesAbsolutePointer";

@implementation A5Machine

#pragma mark - Создание

+ (instancetype)machineWithTemplateIdentifier:(NSString *)templateIdentifier
                                         name:(NSString *)name
{
    A5Machine *machine = [[A5Machine alloc] initWithDictionary:nil];
    machine.name = name;
    machine.templateIdentifier = templateIdentifier ?: A5TemplateCustom;
    [machine applyTemplateDefaults];
    return machine;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
{
    self = [super init];
    if (!self) {
        return nil;
    }

    NSString *storedIdentifier = dictionary[A5KeyIdentifier];
    if ([storedIdentifier isKindOfClass:[NSString class]] && storedIdentifier.length > 0) {
        _identifier = [storedIdentifier copy];
    } else {
        CFUUIDRef uuid = CFUUIDCreate(NULL);
        CFStringRef string = CFUUIDCreateString(NULL, uuid);
        _identifier = [(__bridge NSString *)string copy];
        CFRelease(string);
        CFRelease(uuid);
    }

    _name               = [(dictionary[A5KeyName] ?: @"Машина") copy];
    _templateIdentifier = [(dictionary[A5KeyTemplate] ?: A5TemplateCustom) copy];
    _ramMegabytes       = [dictionary[A5KeyRAM] unsignedIntegerValue];
    _cpuModel           = [(dictionary[A5KeyCPU] ?: @"pentium") copy];
    _hardDiskMegabytes  = [dictionary[A5KeyDiskSize] unsignedIntegerValue];
    _cdromPath          = [dictionary[A5KeyCDROM] copy];
    _floppyPath         = [dictionary[A5KeyFloppy] copy];
    _bootDevice         = [(dictionary[A5KeyBoot] ?: A5BootHardDisk) copy];

    NSNumber *absolute = dictionary[A5KeyAbsolute];
    _usesAbsolutePointer = absolute ? [absolute boolValue] : YES;

    if (_ramMegabytes == 0) {
        _ramMegabytes = 32;
    }

    return self;
}

/// Значения по умолчанию для шаблона.  Подобраны под iPhone 4S: у него 512 МБ
/// физической памяти, из которых iOS 6 оставляет процессу заметно меньше, так
/// что даже "большой" профиль Windows 98 держится в пределах 64 МБ гостя.
- (void)applyTemplateDefaults
{
    if ([_templateIdentifier isEqualToString:A5TemplateDOS]) {
        _cpuModel          = @"486";
        _ramMegabytes      = 16;
        _hardDiskMegabytes = 512;
        _bootDevice        = A5BootFloppy;
        _usesAbsolutePointer = NO;   // DOS-мыши не понимают usb-tablet
    } else if ([_templateIdentifier isEqualToString:A5TemplateWindows31]) {
        _cpuModel          = @"486";
        _ramMegabytes      = 32;
        _hardDiskMegabytes = 512;
        _bootDevice        = A5BootFloppy;
        _usesAbsolutePointer = NO;
    } else if ([_templateIdentifier isEqualToString:A5TemplateWindows95]) {
        _cpuModel          = @"pentium";
        _ramMegabytes      = 48;
        _hardDiskMegabytes = 1024;
        _bootDevice        = A5BootCDROM;
        _usesAbsolutePointer = YES;
    } else if ([_templateIdentifier isEqualToString:A5TemplateWindows98]) {
        _cpuModel          = @"pentium2";
        _ramMegabytes      = 64;
        _hardDiskMegabytes = 2048;
        _bootDevice        = A5BootCDROM;
        _usesAbsolutePointer = YES;
    } else {
        _cpuModel          = @"pentium";
        _ramMegabytes      = 32;
        _hardDiskMegabytes = 1024;
        _bootDevice        = A5BootHardDisk;
        _usesAbsolutePointer = YES;
    }
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    dictionary[A5KeyIdentifier] = _identifier;
    dictionary[A5KeyName]       = _name ?: @"";
    dictionary[A5KeyTemplate]   = _templateIdentifier ?: A5TemplateCustom;
    dictionary[A5KeyRAM]        = @(_ramMegabytes);
    dictionary[A5KeyCPU]        = _cpuModel ?: @"pentium";
    dictionary[A5KeyDiskSize]   = @(_hardDiskMegabytes);
    dictionary[A5KeyBoot]       = _bootDevice ?: A5BootHardDisk;
    dictionary[A5KeyAbsolute]   = @(_usesAbsolutePointer);
    if (_cdromPath.length > 0) {
        dictionary[A5KeyCDROM] = _cdromPath;
    }
    if (_floppyPath.length > 0) {
        dictionary[A5KeyFloppy] = _floppyPath;
    }
    return dictionary;
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[A5Machine alloc] initWithDictionary:[self dictionaryRepresentation]];
}

#pragma mark - Пути

+ (NSString *)machinesRootPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"Machines"];
}

- (NSString *)directoryPath
{
    return [[A5Machine machinesRootPath] stringByAppendingPathComponent:_identifier];
}

- (NSString *)hardDiskPath
{
    return [self.directoryPath stringByAppendingPathComponent:@"disk.img"];
}

#pragma mark - Справочники

+ (NSArray *)allTemplateIdentifiers
{
    return @[ A5TemplateDOS, A5TemplateWindows31, A5TemplateWindows95,
              A5TemplateWindows98, A5TemplateCustom ];
}

+ (NSString *)displayNameForTemplate:(NSString *)templateIdentifier
{
    if ([templateIdentifier isEqualToString:A5TemplateDOS])       return @"MS-DOS";
    if ([templateIdentifier isEqualToString:A5TemplateWindows31]) return @"Windows 3.1";
    if ([templateIdentifier isEqualToString:A5TemplateWindows95]) return @"Windows 95";
    if ([templateIdentifier isEqualToString:A5TemplateWindows98]) return @"Windows 98";
    return @"Другая ОС";
}

+ (NSArray *)availableRAMSizes
{
    return @[ @16, @24, @32, @48, @64, @96, @128 ];
}

+ (NSArray *)availableDiskSizes
{
    return @[ @0, @256, @512, @1024, @2048, @4096 ];
}

+ (NSArray *)availableCPUModels
{
    return @[ @"486", @"pentium", @"pentium2" ];
}

+ (NSString *)displayNameForBootDevice:(NSString *)bootDevice
{
    if ([bootDevice isEqualToString:A5BootFloppy]) return @"Дискета";
    if ([bootDevice isEqualToString:A5BootCDROM])  return @"CD-ROM";
    return @"Жёсткий диск";
}

- (NSString *)summaryDescription
{
    return [NSString stringWithFormat:@"%@ · %lu МБ",
            [A5Machine displayNameForTemplate:_templateIdentifier],
            (unsigned long)_ramMegabytes];
}

@end

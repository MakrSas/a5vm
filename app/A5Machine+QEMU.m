//
//  A5Machine+QEMU.m
//

#import "A5Machine+QEMU.h"

/// В -drive параметры разделяются запятыми, поэтому запятая внутри пути
/// экранируется её удвоением.  Пробелы и прочее экранировать не нужно:
/// argv передаётся в QEMU напрямую, без участия шелла.
static NSString *A5EscapeDriveValue(NSString *value)
{
    return [value stringByReplacingOccurrencesOfString:@"," withString:@",,"];
}

@implementation A5Machine (QEMU)

- (NSArray *)qemuArgumentsWithBIOSPath:(NSString *)biosPath error:(NSError **)error
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    BOOL hasHardDisk = self.hardDiskMegabytes > 0 &&
                       [fileManager fileExistsAtPath:self.hardDiskPath];
    BOOL hasCDROM    = self.cdromPath.length > 0 &&
                       [fileManager fileExistsAtPath:self.cdromPath];
    BOOL hasFloppy   = self.floppyPath.length > 0 &&
                       [fileManager fileExistsAtPath:self.floppyPath];

    if (!hasHardDisk && !hasCDROM && !hasFloppy) {
        if (error) {
            *error = [NSError errorWithDomain:@"A5VM" code:10 userInfo:@{
                NSLocalizedDescriptionKey: @"Нечего загружать.",
                NSLocalizedRecoverySuggestionErrorKey:
                    @"Задайте размер жёсткого диска или выберите образ CD/дискеты."
            }];
        }
        return nil;
    }

    NSMutableArray *arguments = [NSMutableArray array];

    // Каталог с прошивками (bios.bin, vgabios-cirrus.bin) внутри бандла.
    [arguments addObjectsFromArray:@[ @"-L", biosPath ]];

    // Память зажата в диапазон, который iPhone 4S реально вытягивает: iOS 6
    // убивает процесс задолго до 512 МБ, а слишком маленькое значение
    // qemu_init() отвергает через exit().
    NSUInteger ram = self.ramMegabytes;
    if (ram < 8)   { ram = 8; }
    if (ram > 128) { ram = 128; }
    [arguments addObjectsFromArray:@[ @"-m", [NSString stringWithFormat:@"%lu", (unsigned long)ram] ]];

    NSString *cpu = self.cpuModel.length > 0 ? self.cpuModel : @"pentium";
    if (![[A5Machine availableCPUModels] containsObject:cpu]) {
        cpu = @"pentium";
    }
    [arguments addObjectsFromArray:@[ @"-cpu", cpu ]];

    // tb-size ограничивает буфер JIT-кода.  По умолчанию QEMU выбирает его от
    // объёма памяти хоста, что для 512 МБ телефона слишком много: буфер должен
    // быть отображён как исполняемый и живёт всё время работы ВМ.
    [arguments addObjectsFromArray:@[ @"-accel", @"tcg,tb-size=32" ]];

    // Ни одного интерактивного канала на stdio: у приложения нет терминала,
    // а QEMU по умолчанию вешает монитор именно туда, когда дисплея нет.
    [arguments addObjectsFromArray:@[ @"-display",  @"none" ]];
    [arguments addObjectsFromArray:@[ @"-monitor",  @"none" ]];
    [arguments addObjectsFromArray:@[ @"-serial",   @"none" ]];
    [arguments addObjectsFromArray:@[ @"-parallel", @"none" ]];

    // Cirrus — та видеокарта, драйверы которой Windows 95/98 содержат прямо в
    // дистрибутиве, так что гость получает нормальное разрешение без доустановки.
    [arguments addObjectsFromArray:@[ @"-vga", @"cirrus" ]];

    [arguments addObjectsFromArray:@[ @"-rtc", @"base=localtime" ]];

    if (hasHardDisk) {
        [arguments addObjectsFromArray:@[ @"-drive",
            [NSString stringWithFormat:@"file=%@,format=raw,if=ide,index=0,media=disk,id=hd0",
             A5EscapeDriveValue(self.hardDiskPath)] ]];
    }
    if (hasCDROM) {
        [arguments addObjectsFromArray:@[ @"-drive",
            [NSString stringWithFormat:@"file=%@,format=raw,if=ide,index=2,media=cdrom,id=cd0",
             A5EscapeDriveValue(self.cdromPath)] ]];
    }
    if (hasFloppy) {
        [arguments addObjectsFromArray:@[ @"-drive",
            [NSString stringWithFormat:@"file=%@,format=raw,if=floppy,index=0,id=fd0",
             A5EscapeDriveValue(self.floppyPath)] ]];
    }

    // Загружаться с отсутствующего носителя нельзя — BIOS в этом случае просто
    // повиснет на "No bootable device", и пользователь решит, что сломано
    // приложение.  Опускаемся до того, что реально подключено.
    NSString *boot = self.bootDevice;
    if ([boot isEqualToString:A5BootCDROM] && !hasCDROM)   { boot = nil; }
    if ([boot isEqualToString:A5BootFloppy] && !hasFloppy) { boot = nil; }
    if ([boot isEqualToString:A5BootHardDisk] && !hasHardDisk) { boot = nil; }
    if (!boot) {
        if (hasCDROM)       { boot = A5BootCDROM; }
        else if (hasFloppy) { boot = A5BootFloppy; }
        else                { boot = A5BootHardDisk; }
    }
    [arguments addObjectsFromArray:@[ @"-boot", boot ]];

    if (self.usesAbsolutePointer) {
        // usb-tablet сообщает гостю абсолютные координаты — единственный режим,
        // в котором тап по экрану попадает туда, куда ткнул пользователь.
        // Windows 95/98 распознают его как обычный USB HID.
        [arguments addObject:@"-usb"];
        [arguments addObjectsFromArray:@[ @"-device", @"usb-tablet" ]];
    }

    return arguments;
}

@end

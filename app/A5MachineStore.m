//
//  A5MachineStore.m
//

#import "A5MachineStore.h"
#import "A5Machine.h"

@interface A5MachineStore ()
@property (nonatomic, strong) NSMutableArray *mutableMachines;
@end

@implementation A5MachineStore

+ (instancetype)sharedStore
{
    static A5MachineStore *store = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[A5MachineStore alloc] init];
        [store reload];
    });
    return store;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _mutableMachines = [NSMutableArray array];
    }
    return self;
}

- (NSArray *)machines
{
    return [_mutableMachines copy];
}

+ (NSString *)rootPath
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"Machines"];
}

- (void)reload
{
    [_mutableMachines removeAllObjects];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *root = [A5MachineStore rootPath];
    [fileManager createDirectoryAtPath:root
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:NULL];

    NSArray *entries = [fileManager contentsOfDirectoryAtPath:root error:NULL];
    // Каталоги приходят в произвольном порядке — сортируем по имени каталога,
    // чтобы список машин не переставлялся между запусками.
    for (NSString *entry in [entries sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *configPath = [[root stringByAppendingPathComponent:entry]
                                stringByAppendingPathComponent:@"config.plist"];
        NSDictionary *dictionary = [NSDictionary dictionaryWithContentsOfFile:configPath];
        if (dictionary) {
            [_mutableMachines addObject:[[A5Machine alloc] initWithDictionary:dictionary]];
        }
    }
}

- (void)addMachine:(A5Machine *)machine
{
    if (!machine) {
        return;
    }
    [_mutableMachines addObject:machine];
    [self saveMachine:machine];
}

- (void)saveMachine:(A5Machine *)machine
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtPath:machine.directoryPath
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:NULL];
    NSString *configPath = [machine.directoryPath
                            stringByAppendingPathComponent:@"config.plist"];
    [[machine dictionaryRepresentation] writeToFile:configPath atomically:YES];
}

- (void)removeMachine:(A5Machine *)machine
{
    [[NSFileManager defaultManager] removeItemAtPath:machine.directoryPath error:NULL];
    [_mutableMachines removeObject:machine];
}

- (BOOL)prepareHardDiskForMachine:(A5Machine *)machine error:(NSError **)error
{
    if (machine.hardDiskMegabytes == 0) {
        return YES;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *path = machine.hardDiskPath;

    [fileManager createDirectoryAtPath:machine.directoryPath
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:NULL];

    if ([fileManager fileExistsAtPath:path]) {
        return YES;
    }

    // Образ создаётся разреженным: ftruncate задаёт размер, но блоки под него
    // файловая система выделит только когда гость реально что-то запишет.
    // Для QEMU это обычный raw-образ, конвертация не нужна.
    if (![fileManager createFileAtPath:path contents:[NSData data] attributes:nil]) {
        if (error) {
            *error = [NSError errorWithDomain:@"A5VM" code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"Не удалось создать файл образа диска."
            }];
        }
        return NO;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        if (error) {
            *error = [NSError errorWithDomain:@"A5VM" code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"Образ диска создан, но недоступен для записи."
            }];
        }
        return NO;
    }

    @try {
        [handle truncateFileAtOffset:(unsigned long long)machine.hardDiskMegabytes * 1024ULL * 1024ULL];
    }
    @catch (NSException *exception) {
        [handle closeFile];
        [fileManager removeItemAtPath:path error:NULL];
        if (error) {
            *error = [NSError errorWithDomain:@"A5VM" code:3 userInfo:@{
                NSLocalizedDescriptionKey: @"Недостаточно места для образа диска."
            }];
        }
        return NO;
    }
    [handle closeFile];
    return YES;
}

- (NSArray *)availableImagePathsWithExtensions:(NSArray *)extensions
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, YES);
    NSString *documents = paths.firstObject;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *entries = [fileManager contentsOfDirectoryAtPath:documents error:NULL];

    NSMutableArray *result = [NSMutableArray array];
    for (NSString *entry in entries) {
        if ([entry isEqualToString:@"Machines"]) {
            continue;
        }
        NSString *extension = [[entry pathExtension] lowercaseString];
        if (extension.length == 0 || ![extensions containsObject:extension]) {
            continue;
        }
        NSString *fullPath = [documents stringByAppendingPathComponent:entry];
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:fullPath isDirectory:&isDirectory] && !isDirectory) {
            [result addObject:fullPath];
        }
    }
    return [result sortedArrayUsingSelector:@selector(compare:)];
}

@end

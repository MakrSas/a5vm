//
//  A5MachineStore.h
//  Хранилище машин на диске: <Documents>/Machines/<uuid>/config.plist.
//

#import <Foundation/Foundation.h>

@class A5Machine;

@interface A5MachineStore : NSObject

+ (instancetype)sharedStore;

/// Машины в порядке, в котором их показывает список.
@property (nonatomic, copy, readonly) NSArray *machines;

- (void)reload;

- (void)addMachine:(A5Machine *)machine;
- (void)saveMachine:(A5Machine *)machine;
/// Удаляет и запись, и каталог машины вместе с её образом диска.
- (void)removeMachine:(A5Machine *)machine;

/// Создаёт разреженный образ жёсткого диска нужного размера, если его ещё нет.
/// Возвращает NO и заполняет error, если места не хватило.
- (BOOL)prepareHardDiskForMachine:(A5Machine *)machine error:(NSError **)error;

/// Образы дисков, лежащие в Documents (то, что пользователь закинул по SSH),
/// отфильтрованные по расширению.  Каталог Machines пропускается.
- (NSArray *)availableImagePathsWithExtensions:(NSArray *)extensions;

@end

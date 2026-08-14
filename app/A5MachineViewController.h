//
//  A5MachineViewController.h
//  Настройки одной машины и её запуск.
//

#import <UIKit/UIKit.h>

@class A5Machine;

@interface A5MachineViewController : UITableViewController

- (instancetype)initWithMachine:(A5Machine *)machine;

@end

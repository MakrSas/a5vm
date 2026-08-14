//
//  A5NewMachineViewController.h
//  Модальный экран создания машины: имя и шаблон гостевой ОС.
//

#import <UIKit/UIKit.h>

@class A5Machine, A5NewMachineViewController;

@protocol A5NewMachineViewControllerDelegate <NSObject>
- (void)newMachineViewController:(A5NewMachineViewController *)controller
                didCreateMachine:(A5Machine *)machine;
- (void)newMachineViewControllerDidCancel:(A5NewMachineViewController *)controller;
@end

@interface A5NewMachineViewController : UITableViewController

@property (nonatomic, weak) id<A5NewMachineViewControllerDelegate> delegate;

@end

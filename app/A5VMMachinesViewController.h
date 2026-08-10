#import <UIKit/UIKit.h>
#import "A5VMMachineSettingsViewController.h"
#import "A5VMNewMachineViewController.h"

@interface A5VMMachinesViewController : UITableViewController <A5VMMachineSettingsDelegate, A5VMNewMachineDelegate> {
    NSMutableArray *_machines;
}

- (void)machineSettingsController:(A5VMMachineSettingsViewController *)controller
              didUpdateMachine:(NSDictionary *)machine
                         atIndex:(NSUInteger)index;
- (void)newMachineController:(A5VMNewMachineViewController *)controller
             didCreateMachine:(NSDictionary *)machine;
@end

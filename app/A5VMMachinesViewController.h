#import <UIKit/UIKit.h>
#import "A5VMMachineSettingsViewController.h"

@interface A5VMMachinesViewController : UITableViewController <UIAlertViewDelegate, A5VMMachineSettingsDelegate> {
    NSMutableArray *_machines;
}

- (void)machineSettingsController:(A5VMMachineSettingsViewController *)controller
              didUpdateMachine:(NSDictionary *)machine
                         atIndex:(NSUInteger)index;
@end

#import <UIKit/UIKit.h>

@class A5VMMachineSettingsViewController;

@protocol A5VMMachineSettingsDelegate <NSObject>
- (void)machineSettingsController:(A5VMMachineSettingsViewController *)controller
              didUpdateMachine:(NSDictionary *)machine
                         atIndex:(NSUInteger)index;
@end

@interface A5VMMachineSettingsViewController : UITableViewController <UIAlertViewDelegate> {
    NSDictionary *_machine;
    NSUInteger _machineIndex;
    id <A5VMMachineSettingsDelegate> _delegate;
}

- (id)initWithMachine:(NSDictionary *)machine
                index:(NSUInteger)index
             delegate:(id <A5VMMachineSettingsDelegate>)delegate;
- (void)runMachine:(id)sender;

@end

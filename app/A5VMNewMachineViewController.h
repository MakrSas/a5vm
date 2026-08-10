#import <UIKit/UIKit.h>

@class A5VMNewMachineViewController;

@protocol A5VMNewMachineDelegate <NSObject>
- (void)newMachineController:(A5VMNewMachineViewController *)controller
             didCreateMachine:(NSDictionary *)machine;
@end

@interface A5VMNewMachineViewController : UITableViewController <UIActionSheetDelegate, UIAlertViewDelegate> {
    id <A5VMNewMachineDelegate> _delegate;
    NSString *_osFamily;
    NSString *_osVersion;
    NSString *_mediaPath;
    NSArray *_mediaChoices;
    NSDictionary *_profile;
}

- (id)initWithDelegate:(id <A5VMNewMachineDelegate>)delegate;
- (void)chooseFamily:(id)sender;
- (void)chooseVersion:(id)sender;
- (void)chooseMedia:(id)sender;
- (void)createMachine:(id)sender;

@end

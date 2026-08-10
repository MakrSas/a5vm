#import <UIKit/UIKit.h>

#include "a5vm/machine.h"

@class A5VMDisplayView;

@interface A5VMViewController : UIViewController <UITextFieldDelegate> {
    NSDictionary *_machine;
    NSString *_machineName;
    A5VMDisplayView *_displayView;
    UILabel *_statusLabel;
    UIButton *_runButton;
    UIButton *_resetButton;
    UITextField *_inputField;
    a5vm_machine *_runtime;
}

- (id)initWithMachine:(NSDictionary *)machine;
- (void)runDemo:(id)sender;
- (void)resetVM:(id)sender;
- (BOOL)textFieldShouldReturn:(UITextField *)textField;

@end

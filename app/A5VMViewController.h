#import <UIKit/UIKit.h>

#include "a5vm/machine.h"

@class A5VMDisplayView;

@interface A5VMViewController : UIViewController <UITextFieldDelegate> {
    NSDictionary *_machine;
    NSString *_machineName;
    UILabel *_screenTitle;
    A5VMDisplayView *_displayView;
    UILabel *_statusLabel;
    UIButton *_runButton;
    UIButton *_resetButton;
    UIButton *_powerButton;
    UIButton *_pauseButton;
    UIButton *_keyboardButton;
    UIButton *_menuButton;
    UIView *_controlPanel;
    UITextField *_inputField;
    a5vm_machine *_runtime;
    BOOL _controlsVisible;
    BOOL _keyboardVisible;
    BOOL _poweredOn;
}

- (id)initWithMachine:(NSDictionary *)machine;
- (void)runDemo:(id)sender;
- (void)resetVM:(id)sender;
- (void)powerVM:(id)sender;
- (void)toggleControls:(id)sender;
- (void)showKeyboard:(id)sender;
- (void)pauseVM:(id)sender;
- (BOOL)textFieldShouldReturn:(UITextField *)textField;

@end

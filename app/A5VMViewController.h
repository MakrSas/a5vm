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
    NSTimer *_runTimer;
    a5vm_machine *_runtime;
    BOOL _controlsVisible;
    BOOL _keyboardVisible;
    BOOL _poweredOn;
    BOOL _isRunning;
    BOOL _isPaused;
    BOOL _is386;
}

- (id)initWithMachine:(NSDictionary *)machine;
- (void)runDemo:(id)sender;
- (void)resetVM:(id)sender;
- (void)powerVM:(id)sender;
- (void)toggleControls:(id)sender;
- (void)showKeyboard:(id)sender;
- (void)pauseVM:(id)sender;
- (void)runSlice:(NSTimer *)timer;
- (BOOL)textFieldShouldReturn:(UITextField *)textField;

@end

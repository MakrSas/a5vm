#import <UIKit/UIKit.h>

#include "a5vm/machine.h"

@class A5VMDisplayView;
@class A5VMIconButton;

@interface A5VMViewController : UIViewController <UITextFieldDelegate> {
    NSDictionary *_machine;
    NSString *_machineName;
    UILabel *_screenTitle;
    A5VMDisplayView *_displayView;
    UILabel *_statusLabel;
    A5VMIconButton *_runButton;
    A5VMIconButton *_resetButton;
    A5VMIconButton *_powerButton;
    A5VMIconButton *_pauseButton;
    A5VMIconButton *_keyboardButton;
    A5VMIconButton *_menuButton;
    UIView *_controlPanel;
    UIView *_keyPanel;
    UITextField *_inputField;
    CGFloat _keyboardTop;
    NSTimer *_runTimer;
    a5vm_machine *_runtime;
    BOOL _controlsVisible;
    BOOL _keyboardVisible;
    BOOL _poweredOn;
    BOOL _isRunning;
    BOOL _isPaused;
    BOOL _is386;
    BOOL _hasSeparateHardDisk;
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

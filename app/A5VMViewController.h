#import <UIKit/UIKit.h>

#include "a5vm/cpu8086.h"
#include "a5vm/keyboard.h"
#include "a5vm/vga_text.h"

@class A5VMDisplayView;

@interface A5VMViewController : UIViewController {
    NSDictionary *_machine;
    NSString *_machineName;
    A5VMDisplayView *_displayView;
    UILabel *_statusLabel;
    UIButton *_runButton;
    UIButton *_resetButton;
    UITextField *_inputField;
    a5vm_memory *_memory;
    a5vm_cpu8086 *_cpu;
    a5vm_keyboard *_keyboard;
    a5vm_vga_text *_vga;
}

- (id)initWithMachine:(NSDictionary *)machine;
- (void)runDemo:(id)sender;
- (void)resetVM:(id)sender;
- (BOOL)textFieldShouldReturn:(UITextField *)textField;

@end

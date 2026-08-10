#import <UIKit/UIKit.h>

#include "a5vm/cpu8086.h"

@class A5VMDisplayView;

@interface A5VMViewController : UIViewController {
    A5VMDisplayView *_displayView;
    UILabel *_statusLabel;
    UIButton *_runButton;
    UIButton *_resetButton;
    a5vm_memory *_memory;
    a5vm_cpu8086 *_cpu;
}

- (void)runDemo:(id)sender;
- (void)resetVM:(id)sender;

@end

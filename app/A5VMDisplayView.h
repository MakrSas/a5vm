#import <UIKit/UIKit.h>

#include "a5vm/vga_text.h"

@interface A5VMDisplayView : UIView {
    NSString *_displayText;
    uint8_t _cells[A5VM_VGA_TEXT_BUFFER_SIZE];
    BOOL _hasTextBuffer;
}

@property(nonatomic, copy) NSString *displayText;

- (void)setTextBuffer:(const uint8_t *)cells;

@end

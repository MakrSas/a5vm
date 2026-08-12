#import <UIKit/UIKit.h>

#include "a5vm/vga_text.h"

@interface A5VMDisplayView : UIView {
    NSString *_displayText;
    uint8_t _cells[A5VM_VGA_TEXT_BUFFER_SIZE];
    BOOL _hasTextBuffer;
    UIImage *_framebufferImage;
    BOOL _hasFramebuffer;
}

@property(nonatomic, copy) NSString *displayText;

/* Portable interpreter's 80x25 text-mode VGA output. Setting this
   clears any framebuffer image previously set with -setFramebufferImage:. */
- (void)setTextBuffer:(const uint8_t *)cells;

/* QEMU's raster VGA console (see app/A5VMQemuBridge.h's
   -qemuBridge:didUpdateScreen:), drawn letterboxed to preserve its
   aspect ratio. Setting this clears any text buffer previously set
   with -setTextBuffer:. Pass nil to go back to the placeholder text. */
- (void)setFramebufferImage:(UIImage *)image;

@end

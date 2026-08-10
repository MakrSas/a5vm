#import "A5VMDisplayView.h"

#include <string.h>

@implementation A5VMDisplayView

@synthesize displayText = _displayText;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.02f green:0.04f blue:0.03f alpha:1.0f];
        self.displayText = @"A5VM\n\n8086 PC is ready\nPress Run demo";
    }
    return self;
}

- (void)setDisplayText:(NSString *)displayText {
    if (_displayText != displayText) {
        [_displayText release];
        _displayText = [displayText copy];
        _hasTextBuffer = NO;
        [self setNeedsDisplay];
    }
}

- (void)setTextBuffer:(const uint8_t *)cells {
    memcpy(_cells, cells, sizeof(_cells));
    _hasTextBuffer = YES;
    [self setNeedsDisplay];
}

- (void)drawTextBuffer {
    UIFont *font = [UIFont fontWithName:@"Courier-Bold" size:9.0f];
    if (!font) font = [UIFont fontWithName:@"Courier" size:9.0f];
    if (!font) font = [UIFont systemFontOfSize:9.0f];

    CGFloat cellWidth = self.bounds.size.width / (CGFloat)A5VM_VGA_TEXT_COLUMNS;
    CGFloat cellHeight = self.bounds.size.height / (CGFloat)A5VM_VGA_TEXT_ROWS;
    UIColor *green = [UIColor colorWithRed:0.45f green:1.0f blue:0.55f alpha:1.0f];
    [green set];

    unsigned row;
    unsigned column;
    for (row = 0; row < A5VM_VGA_TEXT_ROWS; ++row) {
        for (column = 0; column < A5VM_VGA_TEXT_COLUMNS; ++column) {
            size_t offset = (row * A5VM_VGA_TEXT_COLUMNS + column) * 2u;
            unsigned char character = _cells[offset];
            if (character < 0x20 || character > 0x7E) character = ' ';
            NSString *cell = [[NSString alloc] initWithBytes:&character
                                                       length:1
                                                     encoding:NSASCIIStringEncoding];
            [cell drawInRect:CGRectMake(column * cellWidth, row * cellHeight,
                                        cellWidth + 1.0f, cellHeight + 1.0f)
                    withFont:font
               lineBreakMode:NSLineBreakByClipping
                   alignment:NSTextAlignmentLeft];
            [cell release];
        }
    }
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetRGBStrokeColor(context, 0.18f, 0.45f, 0.26f, 1.0f);
    CGContextSetLineWidth(context, 2.0f);
    CGContextStrokeRect(context, CGRectInset(self.bounds, 1.0f, 1.0f));

    if (_hasTextBuffer) {
        [self drawTextBuffer];
        return;
    }

    UIFont *font = [UIFont fontWithName:@"Courier" size:16.0f];
    if (!font) font = [UIFont systemFontOfSize:16.0f];
    [_displayText drawInRect:CGRectInset(self.bounds, 16.0f, 16.0f)
                    withFont:font
               lineBreakMode:NSLineBreakByWordWrapping
                   alignment:NSTextAlignmentLeft];
}

- (void)dealloc {
    [_displayText release];
    [super dealloc];
}

@end

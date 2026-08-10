#import "A5VMDisplayView.h"

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
        [self setNeedsDisplay];
    }
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetRGBStrokeColor(context, 0.18f, 0.45f, 0.26f, 1.0f);
    CGContextSetLineWidth(context, 2.0f);
    CGContextStrokeRect(context, CGRectInset(self.bounds, 1.0f, 1.0f));

    UIFont *font = [UIFont fontWithName:@"Courier" size:16.0f];
    if (!font) font = [UIFont systemFontOfSize:16.0f];
    [_displayText drawInRect:CGRectInset(self.bounds, 16.0f, 16.0f)
                    withFont:font
               lineBreakMode:UILineBreakModeWordWrap
                   alignment:UITextAlignmentLeft];
}

- (void)dealloc {
    [_displayText release];
    [super dealloc];
}

@end

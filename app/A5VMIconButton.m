#import "A5VMIconButton.h"

@implementation A5VMIconButton

@synthesize iconType = _iconType;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)setIconType:(A5VMIconType)iconType {
    _iconType = iconType;
    [self setNeedsDisplay];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect bounds = CGRectInset(self.bounds, 1.0f, 1.0f);
    CGFloat midX = CGRectGetMidX(bounds);
    CGFloat midY = CGRectGetMidY(bounds);
    CGFloat radius = MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds)) * 0.22f;
    UIColor *fill = self.highlighted
        ? [UIColor colorWithWhite:0.30f alpha:0.98f]
        : [UIColor colorWithWhite:0.12f alpha:0.98f];
    CGContextSetFillColorWithColor(context, fill.CGColor);
    CGContextFillEllipseInRect(context, bounds);
    CGContextSetStrokeColorWithColor(context,
                                     [UIColor colorWithWhite:0.40f alpha:1.0f].CGColor);
    CGContextSetLineWidth(context, 1.0f);
    CGContextStrokeEllipseInRect(context, bounds);
    CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(context, 2.2f);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);

    switch (_iconType) {
        case A5VMIconPower:
            CGContextMoveToPoint(context, midX, midY - radius - 5.0f);
            CGContextAddLineToPoint(context, midX, midY - 2.0f);
            CGContextStrokePath(context);
            CGContextAddArc(context, midX, midY, radius + 3.0f,
                            (CGFloat)(-M_PI * 0.78), (CGFloat)(M_PI * 0.78), 0);
            CGContextStrokePath(context);
            break;
        case A5VMIconRun:
            CGContextMoveToPoint(context, midX - 6.0f, midY - 9.0f);
            CGContextAddLineToPoint(context, midX + 9.0f, midY);
            CGContextAddLineToPoint(context, midX - 6.0f, midY + 9.0f);
            CGContextClosePath(context);
            CGContextFillPath(context);
            break;
        case A5VMIconReset:
            CGContextAddArc(context, midX, midY, radius + 4.0f,
                            (CGFloat)(-M_PI * 0.25), (CGFloat)(M_PI * 1.35), 0);
            CGContextStrokePath(context);
            CGContextMoveToPoint(context, midX - 10.0f, midY - 5.0f);
            CGContextAddLineToPoint(context, midX - 10.0f, midY + 5.0f);
            CGContextAddLineToPoint(context, midX - 1.0f, midY + 1.0f);
            CGContextClosePath(context);
            CGContextFillPath(context);
            break;
        case A5VMIconPause:
            CGContextSetLineWidth(context, 3.5f);
            CGContextMoveToPoint(context, midX - 5.0f, midY - 9.0f);
            CGContextAddLineToPoint(context, midX - 5.0f, midY + 9.0f);
            CGContextMoveToPoint(context, midX + 5.0f, midY - 9.0f);
            CGContextAddLineToPoint(context, midX + 5.0f, midY + 9.0f);
            CGContextStrokePath(context);
            break;
        case A5VMIconKeyboard:
            CGContextSetLineWidth(context, 1.8f);
            CGContextStrokeRect(context, CGRectMake(midX - 12.0f, midY - 8.0f,
                                                    24.0f, 16.0f));
            {
                unsigned row;
                unsigned column;
                for (row = 0; row < 2; ++row) {
                    for (column = 0; column < 4; ++column) {
                        CGContextFillRect(context, CGRectMake(midX - 9.0f + column * 5.0f,
                                                             midY - 5.0f + row * 5.0f,
                                                             2.5f, 2.5f));
                    }
                }
                CGContextFillRect(context, CGRectMake(midX - 8.0f, midY + 5.0f,
                                                     16.0f, 2.0f));
            }
            break;
        case A5VMIconArrowLeft:
        case A5VMIconArrowRight: {
            CGFloat direction = _iconType == A5VMIconArrowLeft ? -1.0f : 1.0f;
            CGContextMoveToPoint(context, midX + direction * 8.0f, midY - 10.0f);
            CGContextAddLineToPoint(context, midX - direction * 7.0f, midY);
            CGContextAddLineToPoint(context, midX + direction * 8.0f, midY + 10.0f);
            CGContextStrokePath(context);
            break;
        }
    }
}

@end

//
//  A5DisplayView.m
//

#import "A5DisplayView.h"
#import <QuartzCore/QuartzCore.h>

@implementation A5DisplayView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.opaque = YES;
        self.multipleTouchEnabled = YES;
        self.layer.contentsGravity = kCAGravityResizeAspect;
        // Гостевой экран увеличивается почти всегда (640x480 на 3.5"): при
        // сглаживании текст DOS расплывается, поэтому ближайший сосед.
        self.layer.magnificationFilter = kCAFilterNearest;
        _guestSize = CGSizeZero;
    }
    return self;
}

- (void)setFrameImage:(CGImageRef)image
{
    if (!image) {
        return;
    }
    _guestSize = CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image));
    self.layer.contents = (__bridge id)image;
}

/// Прямоугольник, который изображение реально занимает внутри view.
- (CGRect)imageRect
{
    CGRect bounds = self.bounds;
    if (_guestSize.width <= 0.0f || _guestSize.height <= 0.0f) {
        return bounds;
    }

    CGFloat scale = MIN(CGRectGetWidth(bounds) / _guestSize.width,
                        CGRectGetHeight(bounds) / _guestSize.height);
    CGSize displayed = CGSizeMake(_guestSize.width * scale,
                                  _guestSize.height * scale);
    return CGRectMake(CGRectGetMidX(bounds) - displayed.width / 2.0f,
                      CGRectGetMidY(bounds) - displayed.height / 2.0f,
                      displayed.width, displayed.height);
}

- (BOOL)guestPoint:(CGPoint *)guestPoint forViewPoint:(CGPoint)viewPoint
{
    if (_guestSize.width <= 0.0f || _guestSize.height <= 0.0f) {
        return NO;
    }

    CGRect rect = [self imageRect];
    if (CGRectGetWidth(rect) <= 0.0f || CGRectGetHeight(rect) <= 0.0f) {
        return NO;
    }
    if (!CGRectContainsPoint(rect, viewPoint)) {
        return NO;
    }

    CGFloat x = (viewPoint.x - CGRectGetMinX(rect)) /
                CGRectGetWidth(rect) * _guestSize.width;
    CGFloat y = (viewPoint.y - CGRectGetMinY(rect)) /
                CGRectGetHeight(rect) * _guestSize.height;

    // Крайний пиксель включительно: без зажима тап по правой/нижней границе
    // даёт координату, равную ширине, которой у гостя уже нет.
    x = MAX(0.0f, MIN(x, _guestSize.width - 1.0f));
    y = MAX(0.0f, MIN(y, _guestSize.height - 1.0f));

    if (guestPoint) {
        *guestPoint = CGPointMake(x, y);
    }
    return YES;
}

@end

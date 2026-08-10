#import <UIKit/UIKit.h>

typedef enum {
    A5VMIconPower = 0,
    A5VMIconRun,
    A5VMIconReset,
    A5VMIconPause,
    A5VMIconKeyboard,
    A5VMIconArrowLeft,
    A5VMIconArrowRight
} A5VMIconType;

@interface A5VMIconButton : UIButton {
    A5VMIconType _iconType;
}

@property(nonatomic, assign) A5VMIconType iconType;

@end

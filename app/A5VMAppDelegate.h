#import <UIKit/UIKit.h>

@class A5VMViewController;

@interface A5VMAppDelegate : NSObject <UIApplicationDelegate> {
    UIWindow *_window;
    A5VMViewController *_viewController;
}

@property(nonatomic, retain) UIWindow *window;
@property(nonatomic, retain) A5VMViewController *viewController;

@end

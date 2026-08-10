#import <UIKit/UIKit.h>

@interface A5VMAppDelegate : NSObject <UIApplicationDelegate> {
    UIWindow *_window;
    UIViewController *_viewController;
}

@property(nonatomic, retain) UIWindow *window;
@property(nonatomic, retain) UIViewController *viewController;

@end

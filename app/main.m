#import <UIKit/UIKit.h>

#import "A5VMAppDelegate.h"

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int result = UIApplicationMain(argc, argv, nil,
                                   NSStringFromClass([A5VMAppDelegate class]));
    [pool drain];
    return result;
}

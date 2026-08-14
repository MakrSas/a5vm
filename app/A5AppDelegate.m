//
//  A5AppDelegate.m
//

#import "A5AppDelegate.h"
#import "A5LibraryViewController.h"

@implementation A5AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    A5LibraryViewController *library = [[A5LibraryViewController alloc] init];
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:library];

    self.window.rootViewController = navigation;
    [self.window makeKeyAndVisible];
    return YES;
}

@end

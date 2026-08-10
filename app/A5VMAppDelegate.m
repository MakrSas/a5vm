#import "A5VMAppDelegate.h"
#import "A5VMMachinesViewController.h"

@implementation A5VMAppDelegate

@synthesize window = _window;
@synthesize viewController = _viewController;

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;
    self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    A5VMMachinesViewController *machines = [[[A5VMMachinesViewController alloc] init] autorelease];
    self.viewController = [[[UINavigationController alloc] initWithRootViewController:machines] autorelease];
    self.window.rootViewController = self.viewController;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)dealloc {
    [_viewController release];
    [_window release];
    [super dealloc];
}

@end

//
//  A5DisplayViewController.h
//  Экран работающей машины.
//

#import <UIKit/UIKit.h>

@class A5Machine, A5QemuRunner;

@interface A5DisplayViewController : UIViewController

- (instancetype)initWithMachine:(A5Machine *)machine
                         runner:(A5QemuRunner *)runner
                      arguments:(NSArray *)arguments;

@end

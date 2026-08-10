#import <UIKit/UIKit.h>

@interface A5VMDiskImageViewController : UITableViewController <UIAlertViewDelegate> {
    NSString *_diskPath;
    NSUInteger _diskSize;
    BOOL _hasBootSignature;
}

- (id)initWithDiskPath:(NSString *)path;
- (void)reloadDiskMetadata;
- (void)resetDemoDisk:(id)sender;

@end

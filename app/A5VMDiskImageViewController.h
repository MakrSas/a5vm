#import <UIKit/UIKit.h>

@interface A5VMDiskImageViewController : UITableViewController <UIAlertViewDelegate, UIActionSheetDelegate> {
    NSString *_diskPath;
    NSArray *_imageChoices;
    NSUInteger _diskSize;
    BOOL _hasBootSignature;
}

- (id)initWithDiskPath:(NSString *)path;
- (void)reloadDiskMetadata;
- (void)resetDemoDisk:(id)sender;
- (void)importImage:(id)sender;

@end

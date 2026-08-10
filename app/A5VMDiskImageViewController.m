#import "A5VMDiskImageViewController.h"

#include "a5vm/floppy.h"

@implementation A5VMDiskImageViewController

static NSInteger const A5VMResetDiskAlertTag = 2101;
static NSInteger const A5VMImportDiskAlertTag = 2102;
static NSInteger const A5VMImportActionSheetTag = 2103;

- (id)initWithDiskPath:(NSString *)path {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _diskPath = [path copy];
        self.title = @"Storage";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                             target:self
                             action:@selector(resetDemoDisk:)] autorelease];
    [self reloadDiskMetadata];
}

- (void)reloadDiskMetadata {
    NSData *image = [NSData dataWithContentsOfFile:_diskPath];
    _diskSize = (NSUInteger)[image length];
    _hasBootSignature = _diskSize >= A5VM_FLOPPY_SECTOR_SIZE &&
        ((const uint8_t *)[image bytes])[510] == 0x55 &&
        ((const uint8_t *)[image bytes])[511] == 0xAA;
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? 3 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? @"Disk Image" : @"Actions";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * const CellIdentifier = @"DiskImageCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                       reuseIdentifier:CellIdentifier] autorelease];
    }
    cell.textLabel.textColor = [UIColor darkTextColor];
    cell.detailTextLabel.textColor = [UIColor grayColor];
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == 1) {
        cell.textLabel.text = indexPath.row == 0 ? @"Reset demo boot disk" : @"Import image from path";
        cell.detailTextLabel.text = nil;
        cell.textLabel.textColor = indexPath.row == 0
            ? [UIColor colorWithRed:0.80f green:0.10f blue:0.10f alpha:1.0f]
            : [UIColor colorWithRed:0.10f green:0.35f blue:0.75f alpha:1.0f];
        cell.accessoryType = indexPath.row == 1
            ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
        return cell;
    }

    cell.textLabel.textColor = [UIColor darkTextColor];
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (indexPath.row == 0) {
        cell.textLabel.text = @"File";
        cell.detailTextLabel.text = [_diskPath lastPathComponent];
    } else if (indexPath.row == 1) {
        cell.textLabel.text = @"Size";
        cell.detailTextLabel.text = _diskSize == 0
            ? @"Not created" : [NSString stringWithFormat:@"%lu KB", (unsigned long)(_diskSize / 1024u)];
    } else {
        cell.textLabel.text = @"Boot sector";
        cell.detailTextLabel.text = _hasBootSignature ? @"Valid 55 AA" : @"Not initialized";
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    if (indexPath.row == 1) {
        [self importImage:nil];
        return;
    }
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Reset disk image?"
                                                     message:@"The demo boot sector will replace this floppy image."
                                                    delegate:self
                                           cancelButtonTitle:@"Cancel"
                                           otherButtonTitles:@"Reset", nil] autorelease];
    alert.tag = A5VMResetDiskAlertTag;
    [alert show];
}

- (void)resetDemoDisk:(id)sender {
    (void)sender;
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Reset disk image?"
                                                     message:@"The demo boot sector will replace this floppy image."
                                                    delegate:self
                                           cancelButtonTitle:@"Cancel"
                                           otherButtonTitles:@"Reset", nil] autorelease];
    alert.tag = A5VMResetDiskAlertTag;
    [alert show];
}

- (void)importImage:(id)sender {
    (void)sender;
    NSArray *directories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                NSUserDomainMask, YES);
    NSString *documents = [directories objectAtIndex:0];
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:documents
                                                                            error:nil];
    NSMutableArray *choices = [NSMutableArray array];
    for (NSString *name in names) {
        BOOL isDirectory = NO;
        NSString *path = [documents stringByAppendingPathComponent:name];
        NSString *extension = [[name pathExtension] lowercaseString];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] ||
            isDirectory) continue;
        if ([extension isEqualToString:@"img"] || [extension isEqualToString:@"ima"] ||
            [extension isEqualToString:@"dsk"]) {
            [choices addObject:name];
        }
    }
    [choices sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [_imageChoices release];
    _imageChoices = [choices copy];
    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Import floppy image"
                                                          delegate:self
                                                 cancelButtonTitle:@"Cancel"
                                            destructiveButtonTitle:nil
                                                 otherButtonTitles:@"Enter path", nil] autorelease];
    for (NSString *name in _imageChoices) [sheet addButtonWithTitle:name];
    sheet.tag = A5VMImportActionSheetTag;
    [sheet showInView:self.view];
}

- (void)enterImportPath {
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Import floppy image"
                                                     message:@"Enter the full path of an IMG, IMA, or DSK file."
                                                    delegate:self
                                           cancelButtonTitle:@"Cancel"
                                           otherButtonTitles:@"Import", nil] autorelease];
    alert.tag = A5VMImportDiskAlertTag;
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alert textFieldAtIndex:0].autocorrectionType = UITextAutocorrectionTypeNo;
    [alert textFieldAtIndex:0].autocapitalizationType = UITextAutocapitalizationTypeNone;
    [alert show];
}

- (void)importImageAtPath:(NSString *)source {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:source error:nil];
    NSNumber *fileSize = [attributes objectForKey:NSFileSize];
    if ([fileSize unsignedLongLongValue] == 0 ||
        [fileSize unsignedLongLongValue] > A5VM_FLOPPY_IMAGE_SIZE) {
        UIAlertView *error = [[[UIAlertView alloc] initWithTitle:@"Import failed"
                                                           message:@"The file was not found or is larger than a floppy image."
                                                          delegate:nil
                                                 cancelButtonTitle:@"OK"
                                                 otherButtonTitles:nil] autorelease];
        [error show];
        return;
    }
    NSData *image = [NSData dataWithContentsOfFile:source];
    if (!image || ![image writeToFile:_diskPath atomically:YES]) {
        UIAlertView *error = [[[UIAlertView alloc] initWithTitle:@"Import failed"
                                                           message:@"A5VM could not read the selected file."
                                                          delegate:nil
                                                 cancelButtonTitle:@"OK"
                                                 otherButtonTitles:nil] autorelease];
        [error show];
        return;
    }
    [self reloadDiskMetadata];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.cancelButtonIndex) return;
    if (actionSheet.tag != A5VMImportActionSheetTag) return;
    if (buttonIndex == 0) {
        [self enterImportPath];
        return;
    }
    NSUInteger choiceIndex = (NSUInteger)buttonIndex - 1u;
    if (choiceIndex >= [_imageChoices count]) return;
    NSArray *directories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                NSUserDomainMask, YES);
    NSString *source = [[directories objectAtIndex:0]
                        stringByAppendingPathComponent:[_imageChoices objectAtIndex:choiceIndex]];
    [self importImageAtPath:source];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;
    if (alertView.tag == A5VMImportDiskAlertTag) {
        NSString *source = [[alertView textFieldAtIndex:0].text
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self importImageAtPath:source];
        return;
    }
    a5vm_floppy floppy;
    if (!a5vm_floppy_init(&floppy, 0)) return;
    a5vm_floppy_create_demo(&floppy);
    NSData *image = [NSData dataWithBytes:floppy.bytes length:floppy.size];
    [image writeToFile:_diskPath atomically:YES];
    a5vm_floppy_deinit(&floppy);
    [self reloadDiskMetadata];
}

- (void)dealloc {
    [_diskPath release];
    [_imageChoices release];
    [super dealloc];
}

@end

#import "A5VMMachineSettingsViewController.h"
#import "A5VMViewController.h"
#import "A5VMDiskImageViewController.h"

static NSInteger const A5VMSettingsMediaActionSheetTag = 1101;
static NSInteger const A5VMSettingsMediaAlertTag = 1102;

@implementation A5VMMachineSettingsViewController

- (id)initWithMachine:(NSDictionary *)machine
                index:(NSUInteger)index
             delegate:(id <A5VMMachineSettingsDelegate>)delegate {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _machine = [machine copy];
        _machineIndex = index;
        _delegate = delegate;
        self.title = [_machine objectForKey:@"name"];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemPlay
                             target:self
                             action:@selector(runMachine:)] autorelease];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? 3 : (section == 1 ? 4 : 2);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"General";
    if (section == 1) return @"Hardware & Devices";
    return @"Runtime";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * const CellIdentifier = @"MachineSettingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                       reuseIdentifier:CellIdentifier] autorelease];
        cell.textLabel.textColor = [UIColor darkTextColor];
    }
    cell.textLabel.textColor = [UIColor darkTextColor];
    cell.detailTextLabel.textColor = [UIColor grayColor];
    cell.accessoryType = UITableViewCellAccessoryNone;

    NSString *key = nil;
    NSString *label = nil;
    if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            key = @"capability";
            label = @"Status";
        } else {
            key = @"mediaPath";
            label = @"Installation media";
        }
        cell.textLabel.text = label;
        NSString *mediaPath = [_machine objectForKey:key];
        cell.detailTextLabel.text = [mediaPath length] == 0
            ? @"Not selected" : [mediaPath lastPathComponent];
        if ([[cell.detailTextLabel text] length] == 0) cell.detailTextLabel.text = @"Not selected";
        if (indexPath.row == 0 && [[_machine objectForKey:key] isEqualToString:@"Ready for floppy boot"]) {
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.10f green:0.55f blue:0.15f alpha:1.0f];
        } else if (indexPath.row == 0) {
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.75f green:0.35f blue:0.05f alpha:1.0f];
        }
        return cell;
    }
    if (indexPath.section == 0 && indexPath.row == 0) {
        key = @"name";
        label = @"Name";
    } else if (indexPath.section == 0) {
        key = @"osVersion";
        label = @"Operating System";
        if (indexPath.row == 2) {
            key = @"architecture";
            label = @"Architecture";
        }
    } else if (indexPath.row == 0) {
        key = @"ram";
        label = @"Memory";
    } else if (indexPath.row == 1) {
        key = @"display";
        label = @"Display";
    } else if (indexPath.row == 2) {
        key = @"storage";
        label = @"Storage";
    } else {
        key = @"mediaPath";
        label = @"Installation media";
    }
    cell.textLabel.text = label;
    if (indexPath.section == 0 && indexPath.row == 1) {
        NSString *family = [_machine objectForKey:@"osFamily"];
        NSString *version = [_machine objectForKey:@"osVersion"];
        if ([family length] == 0) family = @"Unknown family";
        if ([version length] == 0) version = @"Unknown version";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ / %@", family, version];
    } else if (indexPath.section == 1 && indexPath.row == 3) {
        NSString *mediaPath = [_machine objectForKey:key];
        cell.detailTextLabel.text = [mediaPath length] == 0
            ? @"Not selected" : [mediaPath lastPathComponent];
    } else {
        cell.detailTextLabel.text = [_machine objectForKey:key];
    }
    if (indexPath.section == 0 && indexPath.row == 0) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1 && indexPath.row == 2) {
        NSString *storage = [[_machine objectForKey:@"storage"] lowercaseString];
        if ([storage rangeOfString:@"floppy"].location != NSNotFound) {
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 0) {
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Machine Name"
                                                         message:nil
                                                        delegate:self
                                               cancelButtonTitle:@"Cancel"
                                               otherButtonTitles:@"Save", nil] autorelease];
        alert.alertViewStyle = UIAlertViewStylePlainTextInput;
        [alert textFieldAtIndex:0].text = [_machine objectForKey:@"name"];
        [alert show];
    } else if (indexPath.section == 1 && indexPath.row == 2) {
        NSString *storage = [[_machine objectForKey:@"storage"] lowercaseString];
        if ([storage rangeOfString:@"floppy"].location == NSNotFound) {
            UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"IDE storage"
                                                             message:@"This preset has a persistent IDE disk attached. The built-in image editor currently edits floppy images only."
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil] autorelease];
            [alert show];
            return;
        }
        NSArray *directories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                    NSUserDomainMask, YES);
        NSString *filename = [_machine objectForKey:@"diskImage"];
        if ([filename length] == 0) filename = @"a5vm-demo.dsk";
        NSString *path = [[directories objectAtIndex:0] stringByAppendingPathComponent:filename];
        A5VMDiskImageViewController *disk =
            [[[A5VMDiskImageViewController alloc] initWithDiskPath:path] autorelease];
        [self.navigationController pushViewController:disk animated:YES];
    } else if (indexPath.section == 2 && indexPath.row == 1) {
        [self chooseMedia:nil];
    }
}

- (void)chooseMedia:(id)sender {
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
            isDirectory || ![extension length]) continue;
        if ([extension isEqualToString:@"img"] || [extension isEqualToString:@"ima"] ||
            [extension isEqualToString:@"dsk"] || [extension isEqualToString:@"iso"] ||
            [extension isEqualToString:@"rom"]) {
            [choices addObject:name];
        }
    }
    [choices sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [_mediaChoices release];
    _mediaChoices = [choices copy];

    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Installation Media"
                                                          delegate:self
                                                 cancelButtonTitle:@"Cancel"
                                            destructiveButtonTitle:nil
                                                 otherButtonTitles:@"Enter path", nil] autorelease];
    for (NSString *name in _mediaChoices) [sheet addButtonWithTitle:name];
    sheet.tag = A5VMSettingsMediaActionSheetTag;
    [sheet showInView:self.view];
}

- (void)enterMediaPath {
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Installation media path"
                                                     message:@"Enter a full path to an IMG, ISO, ROM, or disk image."
                                                    delegate:self
                                           cancelButtonTitle:@"Cancel"
                                           otherButtonTitles:@"Use", nil] autorelease];
    alert.tag = A5VMSettingsMediaAlertTag;
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alert textFieldAtIndex:0].text = [_machine objectForKey:@"mediaPath"];
    [alert textFieldAtIndex:0].autocorrectionType = UITextAutocorrectionTypeNo;
    [alert textFieldAtIndex:0].autocapitalizationType = UITextAutocapitalizationTypeNone;
    [alert show];
}

- (void)updateMediaPath:(NSString *)path {
    if ([path length] == 0) return;
    NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:_machine];
    [updated setObject:path forKey:@"mediaPath"];
    NSString *extension = [[path pathExtension] lowercaseString];
    BOOL floppyImage = [extension isEqualToString:@"img"] ||
        [extension isEqualToString:@"ima"] || [extension isEqualToString:@"dsk"];
    if ([[updated objectForKey:@"osFamily"] isEqualToString:@"DOS"] && floppyImage) {
        [updated setObject:path forKey:@"diskImage"];
    }
    [_machine release];
    _machine = [updated copy];
    [_delegate machineSettingsController:self didUpdateMachine:_machine atIndex:_machineIndex];
    [self.tableView reloadData];
}

- (void)actionSheet:(UIActionSheet *)actionSheet
 clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag != A5VMSettingsMediaActionSheetTag ||
        buttonIndex == actionSheet.cancelButtonIndex) return;
    if (buttonIndex == 0) {
        [self enterMediaPath];
        return;
    }
    NSUInteger choiceIndex = (NSUInteger)(buttonIndex - 1);
    if (choiceIndex < [_mediaChoices count]) {
        [self updateMediaPath:[_mediaChoices objectAtIndex:choiceIndex]];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;
    if (alertView.tag == A5VMSettingsMediaAlertTag) {
        NSString *sourcePath = [[alertView textFieldAtIndex:0].text
                                stringByTrimmingCharactersInSet:
                                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSArray *directories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                    NSUserDomainMask, YES);
        NSString *documents = [directories objectAtIndex:0];
        NSString *resolvedPath = [sourcePath hasPrefix:@"/"]
            ? sourcePath : [documents stringByAppendingPathComponent:sourcePath];
        if (![[NSFileManager defaultManager] fileExistsAtPath:resolvedPath]) {
            UIAlertView *missing = [[[UIAlertView alloc] initWithTitle:@"Media file not found"
                                                                message:@"Select a file in A5VM Documents or enter a valid full path."
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil] autorelease];
            [missing show];
            return;
        }
        NSString *filename = [resolvedPath lastPathComponent];
        NSString *destination = [documents stringByAppendingPathComponent:filename];
        if (![resolvedPath isEqualToString:destination]) {
            NSString *extension = [[filename pathExtension] lowercaseString];
            NSUInteger suffix = 1;
            while ([[NSFileManager defaultManager] fileExistsAtPath:destination]) {
                filename = [NSString stringWithFormat:@"media-%lu.%@",
                            (unsigned long)suffix++, [extension length] == 0 ? @"img" : extension];
                destination = [documents stringByAppendingPathComponent:filename];
            }
            NSError *error = nil;
            if (![[NSFileManager defaultManager] copyItemAtPath:resolvedPath
                                                           toPath:destination
                                                            error:&error]) {
                UIAlertView *failed = [[[UIAlertView alloc] initWithTitle:@"Could not import media"
                                                                   message:[error localizedDescription]
                                                                  delegate:nil
                                                         cancelButtonTitle:@"OK"
                                                         otherButtonTitles:nil] autorelease];
                [failed show];
                return;
            }
        }
        [self updateMediaPath:filename];
        return;
    }
    NSString *name = [[alertView textFieldAtIndex:0].text
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([name length] == 0) return;

    NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:_machine];
    [updated setObject:name forKey:@"name"];
    [_machine release];
    _machine = [updated copy];
    self.title = name;
    [self.tableView reloadData];
    [_delegate machineSettingsController:self didUpdateMachine:_machine atIndex:_machineIndex];
}

- (void)runMachine:(id)sender {
    (void)sender;
    NSString *family = [[_machine objectForKey:@"osFamily"] lowercaseString];
    NSString *mediaPath = [_machine objectForKey:@"mediaPath"];
    NSString *extension = [[mediaPath pathExtension] lowercaseString];
    BOOL floppyImage = [extension isEqualToString:@"img"] ||
        [extension isEqualToString:@"ima"] || [extension isEqualToString:@"dsk"];
    if ([mediaPath length] != 0) {
        NSArray *directories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                    NSUserDomainMask, YES);
        NSString *resolvedPath = [mediaPath hasPrefix:@"/"]
            ? mediaPath
            : [[directories objectAtIndex:0] stringByAppendingPathComponent:mediaPath];
        if (![[NSFileManager defaultManager] fileExistsAtPath:resolvedPath]) {
            UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Media file not found"
                                                             message:@"Copy the installation image into A5VM Documents and select it again before starting the VM."
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil] autorelease];
            [alert show];
            return;
        }
    }

    if ([family isEqualToString:@"macos"]) {
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"MacOS backend not ready"
                                                         message:@"The MacOS preset is saved, but the Macintosh ROM/68k backend has not been connected to the iOS 6 runner yet."
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [alert show];
        return;
    }
    if ([family isEqualToString:@"windows"] && [mediaPath length] == 0) {
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Installation media required"
                                                         message:@"Choose a Windows IMG boot disk or ISO before starting this VM."
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [alert show];
        return;
    }
    if ([mediaPath length] != 0 && !floppyImage) {
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"ISO needs QEMU"
                                                         message:@"This iOS 6 build can boot IMG/IMA/DSK floppy media. ISO/CD-ROM boot will be enabled when the QEMU display backend is connected."
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [alert show];
        return;
    }
    NSString *capability = [_machine objectForKey:@"capability"];
    if ([capability rangeOfString:@"floppy boot"].location == NSNotFound) {
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Preset not available yet"
                                                         message:capability
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [alert show];
        return;
    }
    A5VMViewController *runner = [[[A5VMViewController alloc] initWithMachine:_machine] autorelease];
    [self.navigationController pushViewController:runner animated:YES];
}

- (void)dealloc {
    [_mediaChoices release];
    [_machine release];
    [super dealloc];
}

@end

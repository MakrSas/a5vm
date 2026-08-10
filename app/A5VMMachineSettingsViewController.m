#import "A5VMMachineSettingsViewController.h"
#import "A5VMViewController.h"
#import "A5VMDiskImageViewController.h"

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
                                                             message:@"This preset uses an IDE disk. Its storage controller is not available in the iOS 6 runner yet."
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
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;
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
    [_machine release];
    [super dealloc];
}

@end

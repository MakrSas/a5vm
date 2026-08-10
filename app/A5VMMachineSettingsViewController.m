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
    return 1 + (section == 0 ? 2 : (section == 1 ? 2 : 0));
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
    cell.detailTextLabel.textColor = [UIColor grayColor];

    NSString *key = nil;
    NSString *label = nil;
    if (indexPath.section == 2) {
        key = @"capability";
        label = @"Status";
        cell.textLabel.text = label;
        cell.detailTextLabel.text = [_machine objectForKey:key];
        cell.accessoryType = UITableViewCellAccessoryNone;
        if ([[_machine objectForKey:key] isEqualToString:@"Ready for floppy boot"]) {
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.10f green:0.55f blue:0.15f alpha:1.0f];
        } else {
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
    } else {
        key = @"storage";
        label = @"Storage";
    }
    cell.textLabel.text = label;
    cell.detailTextLabel.text = [_machine objectForKey:key];
    cell.accessoryType = (indexPath.section == 0 && indexPath.row == 0)
        ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
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
    if (![[_machine objectForKey:@"capability"] isEqualToString:@"Ready for floppy boot"]) {
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Preset not available yet"
                                                         message:[_machine objectForKey:@"capability"]
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

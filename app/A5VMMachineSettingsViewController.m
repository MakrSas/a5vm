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
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? 2 : 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? @"General" : @"Hardware & Devices";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * const CellIdentifier = @"MachineSettingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                       reuseIdentifier:CellIdentifier] autorelease];
        cell.textLabel.textColor = [UIColor darkTextColor];
        cell.detailTextLabel.textColor = [UIColor grayColor];
    }

    NSString *key = nil;
    NSString *label = nil;
    if (indexPath.section == 0 && indexPath.row == 0) {
        key = @"name";
        label = @"Name";
    } else if (indexPath.section == 0) {
        key = @"architecture";
        label = @"Architecture";
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
    A5VMViewController *runner = [[[A5VMViewController alloc] initWithMachine:_machine] autorelease];
    [self.navigationController pushViewController:runner animated:YES];
}

- (void)dealloc {
    [_machine release];
    [super dealloc];
}

@end

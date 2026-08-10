#import "A5VMMachinesViewController.h"

static NSString * const A5VMMachinesDefaultsKey = @"A5VM.Machines";

@interface A5VMMachinesViewController ()
@property(nonatomic, retain) NSMutableArray *machines;
@end

@implementation A5VMMachinesViewController

@synthesize machines = _machines;

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = @"Machines";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                             target:self
                             action:@selector(addMachine:)] autorelease];
    self.tableView.rowHeight = 72.0f;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.94f alpha:1.0f];

    NSArray *savedMachines = [[NSUserDefaults standardUserDefaults]
                              objectForKey:A5VMMachinesDefaultsKey];
    if ([savedMachines isKindOfClass:[NSArray class]] && [savedMachines count] != 0) {
        self.machines = [NSMutableArray arrayWithArray:savedMachines];
    } else {
        self.machines = [NSMutableArray arrayWithObject:[self defaultMachine]];
        [self saveMachines];
    }
}

- (NSDictionary *)defaultMachine {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            @"8086 Demo PC", @"name",
            @"8086", @"architecture",
            @"640 KB", @"ram",
            @"VGA Text", @"display",
            @"Virtual floppy", @"storage",
            nil];
}

- (void)saveMachines {
    [[NSUserDefaults standardUserDefaults] setObject:self.machines
                                                forKey:A5VMMachinesDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)addMachine:(id)sender {
    (void)sender;
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"New Machine"
                                                     message:@"Choose a name for the virtual machine."
                                                    delegate:self
                                           cancelButtonTitle:@"Cancel"
                                           otherButtonTitles:@"Create", nil] autorelease];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *field = [alert textFieldAtIndex:0];
    field.placeholder = @"My 8086 PC";
    field.autocapitalizationType = UITextAutocapitalizationTypeWords;
    [alert show];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return [self.machines count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * const CellIdentifier = @"MachineCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                       reuseIdentifier:CellIdentifier] autorelease];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:17.0f];
        cell.detailTextLabel.textColor = [UIColor grayColor];
    }

    NSDictionary *machine = [self.machines objectAtIndex:indexPath.row];
    cell.textLabel.text = [machine objectForKey:@"name"];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  -  %@  -  %@",
                                 [machine objectForKey:@"architecture"],
                                 [machine objectForKey:@"ram"],
                                 [machine objectForKey:@"display"]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *machine = [self.machines objectAtIndex:indexPath.row];
    A5VMMachineSettingsViewController *settings =
        [[[A5VMMachineSettingsViewController alloc] initWithMachine:machine
                                                               index:(NSUInteger)indexPath.row
                                                            delegate:self] autorelease];
    [self.navigationController pushViewController:settings animated:YES];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)machineSettingsController:(A5VMMachineSettingsViewController *)controller
              didUpdateMachine:(NSDictionary *)machine
                         atIndex:(NSUInteger)index {
    (void)controller;
    if (index >= [self.machines count]) return;
    [self.machines replaceObjectAtIndex:index withObject:machine];
    [self saveMachines];
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
 forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    if ([self.machines count] == 1) {
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Keep one machine"
                                                         message:@"The library needs at least one virtual machine."
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [alert show];
        return;
    }
    [self.machines removeObjectAtIndex:indexPath.row];
    [self saveMachines];
    [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                     withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;
    NSString *name = [[alertView textFieldAtIndex:0].text
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([name length] == 0) name = @"8086 PC";

    NSDictionary *machine = [NSDictionary dictionaryWithObjectsAndKeys:
                             name, @"name",
                             @"8086", @"architecture",
                             @"640 KB", @"ram",
                             @"VGA Text", @"display",
                             @"Virtual floppy", @"storage",
                             nil];
    [self.machines addObject:machine];
    [self saveMachines];
    [self.tableView reloadData];
}

- (void)dealloc {
    [_machines release];
    [super dealloc];
}

@end

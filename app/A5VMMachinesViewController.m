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
    [self migrateMachines];
}

- (void)migrateMachines {
    NSUInteger index;
    for (index = 0; index < [self.machines count]; ++index) {
        NSDictionary *source = [self.machines objectAtIndex:index];
        if (![source isKindOfClass:[NSDictionary class]]) source = [self defaultMachine];
        NSMutableDictionary *machine = [NSMutableDictionary dictionaryWithDictionary:source];
        if ([[machine objectForKey:@"storage"] length] == 0) {
            [machine setObject:@"1.44 MB floppy" forKey:@"storage"];
        }
        if ([[machine objectForKey:@"osFamily"] length] == 0) {
            [machine setObject:@"DOS" forKey:@"osFamily"];
        }
        if ([[machine objectForKey:@"osVersion"] length] == 0) {
            [machine setObject:@"8086 Demo" forKey:@"osVersion"];
        }
        if ([[machine objectForKey:@"capability"] length] == 0) {
            [machine setObject:@"Ready for floppy boot" forKey:@"capability"];
        }
        if ([machine objectForKey:@"mediaPath"] == nil) {
            [machine setObject:@"" forKey:@"mediaPath"];
        }
        if ([[machine objectForKey:@"diskImage"] length] == 0) {
            [machine setObject:[NSString stringWithFormat:@"machine-%lu.dsk",
                                (unsigned long)index + 1ul]
                         forKey:@"diskImage"];
        }
        [self.machines replaceObjectAtIndex:index withObject:machine];
    }
    [self saveMachines];
}

- (NSDictionary *)defaultMachine {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            @"8086 Demo PC", @"name",
            @"DOS", @"osFamily",
            @"8086 Demo", @"osVersion",
            @"8086", @"architecture",
            @"640 KB", @"ram",
            @"VGA Text", @"display",
            @"1.44 MB floppy", @"storage",
            @"8086-demo.dsk", @"diskImage",
            @"Ready for floppy boot", @"capability",
            nil];
}

- (void)saveMachines {
    [[NSUserDefaults standardUserDefaults] setObject:self.machines
                                                forKey:A5VMMachinesDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)addMachine:(id)sender {
    (void)sender;
    A5VMNewMachineViewController *wizard =
        [[[A5VMNewMachineViewController alloc] initWithDelegate:self] autorelease];
    [self.navigationController pushViewController:wizard animated:YES];
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
    NSString *name = [machine objectForKey:@"name"];
    if ([name length] == 0) name = @"Unnamed machine";
    cell.textLabel.text = name;
    NSString *family = [machine objectForKey:@"osFamily"];
    NSString *os = [machine objectForKey:@"osVersion"];
    if ([os length] == 0) os = [machine objectForKey:@"architecture"];
    if ([family length] == 0) family = @"Virtual machine";
    if ([os length] == 0) os = @"Unknown system";
    NSString *ram = [machine objectForKey:@"ram"];
    if ([ram length] == 0) ram = @"Memory unavailable";
    NSString *display = [machine objectForKey:@"display"];
    if ([display length] == 0) display = @"Display unavailable";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  -  %@  -  %@",
                                 [NSString stringWithFormat:@"%@ / %@", family, os],
                                 ram,
                                 display];
    return cell;
}

- (NSString *)uniqueDocumentFilenameWithPrefix:(NSString *)prefix suffix:(NSString *)suffix {
    NSArray *directories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                NSUserDomainMask, YES);
    NSString *documents = [directories objectAtIndex:0];
    NSUInteger number = 1;
    while (YES) {
        NSString *filename = [NSString stringWithFormat:@"%@%lu%@",
                              prefix, (unsigned long)number, suffix];
        if (![[NSFileManager defaultManager]
             fileExistsAtPath:[documents stringByAppendingPathComponent:filename]]) {
            return filename;
        }
        ++number;
    }
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

- (void)newMachineController:(A5VMNewMachineViewController *)controller
             didCreateMachine:(NSDictionary *)machine {
    (void)controller;
    NSMutableDictionary *created = [NSMutableDictionary dictionaryWithDictionary:machine];
    NSString *diskImage = [self uniqueDocumentFilenameWithPrefix:@"machine-" suffix:@".dsk"];
    NSString *sourcePath = [created objectForKey:@"mediaPath"];
    NSString *extension = [[sourcePath pathExtension] lowercaseString];
    if ([sourcePath length] != 0) {
        NSArray *directories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                    NSUserDomainMask, YES);
        NSString *filename = [self uniqueDocumentFilenameWithPrefix:@"machine-"
                                                                suffix:[NSString stringWithFormat:@"-media.%@",
                                                                        [extension length] == 0 ? @"img" : extension]];
        NSString *destination = [[directories objectAtIndex:0]
                                 stringByAppendingPathComponent:filename];
        NSError *error = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:sourcePath] &&
            [[NSFileManager defaultManager] copyItemAtPath:sourcePath
                                                     toPath:destination
                                                      error:&error]) {
            [created setObject:filename forKey:@"mediaPath"];
            if ([[created objectForKey:@"osFamily"] isEqualToString:@"DOS"] &&
                ([extension isEqualToString:@"img"] || [extension isEqualToString:@"ima"] ||
                 [extension isEqualToString:@"dsk"])) {
                diskImage = filename;
            }
        } else {
            [created setObject:@"File could not be copied" forKey:@"mediaStatus"];
        }
    }
    [created setObject:diskImage forKey:@"diskImage"];
    [self.machines addObject:created];
    [self saveMachines];
    [self.tableView reloadData];
    [self.navigationController popViewControllerAnimated:YES];
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

- (void)dealloc {
    [_machines release];
    [super dealloc];
}

@end

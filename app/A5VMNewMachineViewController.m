#import "A5VMNewMachineViewController.h"

static NSInteger const A5VMFamilyActionSheetTag = 1001;
static NSInteger const A5VMVersionActionSheetTag = 1002;
static NSInteger const A5VMCreateAlertTag = 1003;
static NSInteger const A5VMMediaAlertTag = 1004;

@implementation A5VMNewMachineViewController

- (id)initWithDelegate:(id <A5VMNewMachineDelegate>)delegate {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _delegate = delegate;
        self.title = @"New Machine";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                             target:self
                             action:@selector(createMachine:)] autorelease];
    self.navigationItem.rightBarButtonItem.enabled = NO;
}

- (NSArray *)versionsForFamily:(NSString *)family {
    if ([family isEqualToString:@"DOS"]) {
        return [NSArray arrayWithObjects:@"MS-DOS 6.22", @"MS-DOS 5.0", @"FreeDOS", nil];
    }
    if ([family isEqualToString:@"Windows"]) {
        return [NSArray arrayWithObjects:@"Windows 3.1", @"Windows 95", @"Windows 98", nil];
    }
    return [NSArray arrayWithObjects:@"System 7", @"Mac OS 8", @"Mac OS 9", nil];
}

- (void)rebuildProfile {
    if (!_osFamily || !_osVersion) {
        [_profile release];
        _profile = nil;
        self.navigationItem.rightBarButtonItem.enabled = NO;
        [self.tableView reloadData];
        return;
    }

    NSString *architecture;
    NSString *ram;
    NSString *display;
    NSString *storage;
    NSString *machineProfile;
    NSString *mediaType;
    NSString *mediaPath;
    NSString *capability;
    if ([_osFamily isEqualToString:@"DOS"]) {
        architecture = @"8086";
        ram = @"640 KB";
        display = @"VGA Text";
        storage = @"1.44 MB floppy";
        machineProfile = @"ibm-pc-xt";
        mediaType = @"IMG";
        capability = @"Ready for floppy boot";
    } else if ([_osFamily isEqualToString:@"Windows"]) {
        architecture = @"i386 (planned)";
        ram = [_osVersion isEqualToString:@"Windows 3.1"] ? @"16 MB" :
              ([_osVersion isEqualToString:@"Windows 95"] ? @"32 MB" : @"64 MB");
        display = @"VGA";
        storage = @"IDE disk + installation media";
        machineProfile = @"i386-pc";
        mediaType = @"ISO / IMG";
        capability = @"Requires protected-mode core";
    } else {
        architecture = [_osVersion isEqualToString:@"System 7"]
            ? @"68k Macintosh (planned)" : @"PowerPC Macintosh (planned)";
        ram = [_osVersion isEqualToString:@"System 7"] ? @"8 MB" : @"64 MB";
        display = @"Macintosh video";
        storage = @"ROM + disk image";
        machineProfile = [_osVersion isEqualToString:@"System 7"] ? @"mac-68k" : @"power-mac";
        mediaType = @"ROM + disk";
        capability = @"Requires Macintosh backend";
    }
    mediaPath = _mediaPath ? _mediaPath : @"";

    NSDictionary *newProfile = [NSDictionary dictionaryWithObjectsAndKeys:
                                _osFamily, @"osFamily",
                                _osVersion, @"osVersion",
                                architecture, @"architecture",
                                ram, @"ram",
                                display, @"display",
                                storage, @"storage",
                                machineProfile, @"machineProfile",
                                mediaType, @"mediaType",
                                mediaPath, @"mediaPath",
                                capability, @"capability",
                                nil];
    [_profile release];
    _profile = [newProfile copy];
    self.navigationItem.rightBarButtonItem.enabled = YES;
    [self.tableView reloadData];
}

- (void)chooseMedia:(id)sender {
    (void)sender;
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Installation media path"
                                                     message:@"Enter a full path to an IMG, ISO, ROM, or disk image. The file will be copied into A5VM Documents."
                                                    delegate:self
                                           cancelButtonTitle:@"Cancel"
                                           otherButtonTitles:@"Use", nil] autorelease];
    alert.tag = A5VMMediaAlertTag;
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alert textFieldAtIndex:0].text = _mediaPath ? _mediaPath : @"";
    [alert textFieldAtIndex:0].autocorrectionType = UITextAutocorrectionTypeNo;
    [alert textFieldAtIndex:0].autocapitalizationType = UITextAutocapitalizationTypeNone;
    [alert show];
}

- (void)chooseFamily:(id)sender {
    (void)sender;
    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Operating System"
                                                         delegate:self
                                                cancelButtonTitle:@"Cancel"
                                           destructiveButtonTitle:nil
                                                otherButtonTitles:@"DOS", @"Windows", @"MacOS", nil] autorelease];
    sheet.tag = A5VMFamilyActionSheetTag;
    [sheet showInView:self.view];
}

- (void)chooseVersion:(id)sender {
    (void)sender;
    if (!_osFamily) return;
    NSArray *versions = [self versionsForFamily:_osFamily];
    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:_osFamily
                                                         delegate:self
                                                cancelButtonTitle:@"Cancel"
                                           destructiveButtonTitle:nil
                                                otherButtonTitles:nil] autorelease];
    for (NSString *version in versions) [sheet addButtonWithTitle:version];
    sheet.tag = A5VMVersionActionSheetTag;
    [sheet showInView:self.view];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return 2;
    if (section == 1) return _profile ? 4 : 1;
    if (section == 2) return _profile ? 2 : 1;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Operating System";
    if (section == 1) return @"Generated Configuration";
    if (section == 2) return @"Installation Media";
    return @"Create";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * const CellIdentifier = @"NewMachineCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                       reuseIdentifier:CellIdentifier] autorelease];
        cell.detailTextLabel.textColor = [UIColor grayColor];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.textColor = [UIColor darkTextColor];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Family";
            cell.detailTextLabel.text = _osFamily ? _osFamily : @"Choose";
        } else {
            cell.textLabel.text = @"Version";
            cell.detailTextLabel.text = _osVersion ? _osVersion : @"Choose";
        }
    } else if (indexPath.section == 1 && _profile) {
        NSArray *keys = [NSArray arrayWithObjects:@"architecture", @"ram", @"display", @"storage", nil];
        NSArray *labels = [NSArray arrayWithObjects:@"CPU", @"Memory", @"Display", @"Storage", nil];
        cell.textLabel.text = [labels objectAtIndex:indexPath.row];
        cell.detailTextLabel.text = [_profile objectForKey:[keys objectAtIndex:indexPath.row]];
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else if (indexPath.section == 1) {
        cell.textLabel.text = @"Choose an OS first";
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else if (indexPath.section == 2 && _profile) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Format";
            cell.detailTextLabel.text = [_profile objectForKey:@"mediaType"];
            cell.accessoryType = UITableViewCellAccessoryNone;
        } else {
            cell.textLabel.text = @"Source file";
            cell.detailTextLabel.text = [_profile objectForKey:@"mediaPath"];
            if ([[cell.detailTextLabel text] length] == 0) cell.detailTextLabel.text = @"Not selected";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 2) {
        cell.textLabel.text = @"Choose an OS first";
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        cell.textLabel.text = @"Create VM";
        cell.detailTextLabel.text = _profile ? [_profile objectForKey:@"capability"] : @"Choose an OS first";
        cell.textLabel.textColor = [UIColor colorWithRed:0.10f green:0.35f blue:0.75f alpha:1.0f];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 0) [self chooseFamily:nil];
    else if (indexPath.section == 0 && indexPath.row == 1) [self chooseVersion:nil];
    else if (indexPath.section == 2 && indexPath.row == 1) [self chooseMedia:nil];
    else if (indexPath.section == 3) [self createMachine:nil];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.cancelButtonIndex) return;
    if (actionSheet.tag == A5VMFamilyActionSheetTag) {
        [_osFamily release];
        _osFamily = [[actionSheet buttonTitleAtIndex:buttonIndex] copy];
        [_osVersion release];
        _osVersion = nil;
        [self rebuildProfile];
    } else if (actionSheet.tag == A5VMVersionActionSheetTag) {
        [_osVersion release];
        _osVersion = [[actionSheet buttonTitleAtIndex:buttonIndex] copy];
        [self rebuildProfile];
    }
}

- (void)createMachine:(id)sender {
    (void)sender;
    if (!_profile) return;
    NSString *title = [NSString stringWithFormat:@"%@ VM", [_profile objectForKey:@"osVersion"]];
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Name your VM"
                                                     message:nil
                                                    delegate:self
                                           cancelButtonTitle:@"Cancel"
                                           otherButtonTitles:@"Create", nil] autorelease];
    alert.tag = A5VMCreateAlertTag;
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    [alert textFieldAtIndex:0].text = title;
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;
    if (alertView.tag == A5VMMediaAlertTag) {
        NSString *path = [[alertView textFieldAtIndex:0].text
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [_mediaPath release];
        _mediaPath = [path length] == 0 ? nil : [path copy];
        [self rebuildProfile];
        return;
    }
    if (alertView.tag != A5VMCreateAlertTag) return;
    NSString *name = [[alertView textFieldAtIndex:0].text
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([name length] == 0) name = [_profile objectForKey:@"osVersion"];
    NSMutableDictionary *machine = [NSMutableDictionary dictionaryWithDictionary:_profile];
    [machine setObject:name forKey:@"name"];
    [_delegate newMachineController:self didCreateMachine:machine];
}

- (void)dealloc {
    [_osFamily release];
    [_osVersion release];
    [_mediaPath release];
    [_profile release];
    [super dealloc];
}

@end

//
//  A5MachineViewController.m
//

#import "A5MachineViewController.h"

#import "A5DisplayViewController.h"
#import "A5Machine.h"
#import "A5Machine+QEMU.h"
#import "A5MachineStore.h"
#import "A5QemuRunner.h"
#import "A5ValuePickerViewController.h"

typedef NS_ENUM(NSInteger, A5MachineSection) {
    A5MachineSectionName,
    A5MachineSectionSystem,
    A5MachineSectionMedia,
    A5MachineSectionBoot,
    A5MachineSectionRun,
    A5MachineSectionCount
};

@interface A5MachineViewController () <UITextFieldDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) A5Machine *machine;
@property (nonatomic, strong) UITextField *nameField;
/// Размер, выбранный пользователем и ожидающий подтверждения на пересоздание
/// уже существующего образа диска.
@property (nonatomic, strong) NSNumber *pendingDiskSize;
@end

@implementation A5MachineViewController

- (instancetype)initWithMachine:(A5Machine *)machine
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _machine = machine;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.machine.name;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self commitName];
    [[A5MachineStore sharedStore] saveMachine:self.machine];
}

- (void)commitName
{
    NSString *name = [self.nameField.text
                      stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length > 0) {
        self.machine.name = name;
        self.title = name;
    }
}

- (void)saveAndReload
{
    [[A5MachineStore sharedStore] saveMachine:self.machine];
    [self.tableView reloadData];
}

#pragma mark - Запуск

- (void)runMachine
{
    [self commitName];
    [[A5MachineStore sharedStore] saveMachine:self.machine];

    NSError *error = nil;
    if (![[A5MachineStore sharedStore] prepareHardDiskForMachine:self.machine
                                                            error:&error]) {
        [self showError:error title:@"Не удалось подготовить диск"];
        return;
    }

    NSString *biosPath = [[[NSBundle mainBundle] bundlePath]
                          stringByAppendingPathComponent:@"pc-bios"];
    NSArray *arguments = [self.machine qemuArgumentsWithBIOSPath:biosPath error:&error];
    if (!arguments) {
        [self showError:error title:@"Нечего запускать"];
        return;
    }

    A5QemuRunner *runner = [A5QemuRunner runnerWithError:&error];
    if (!runner) {
        [self showError:error title:@"QEMU недоступен"];
        return;
    }

    A5DisplayViewController *display =
        [[A5DisplayViewController alloc] initWithMachine:self.machine
                                                  runner:runner
                                               arguments:arguments];
    [self.navigationController pushViewController:display animated:YES];
}

- (void)showError:(NSError *)error title:(NSString *)title
{
    NSString *message = error.localizedDescription ?: @"Неизвестная ошибка.";
    NSString *suggestion = error.userInfo[NSLocalizedRecoverySuggestionErrorKey];
    if (suggestion.length > 0) {
        message = [NSString stringWithFormat:@"%@\n%@", message, suggestion];
    }
    [[[UIAlertView alloc] initWithTitle:title
                                message:message
                               delegate:nil
                      cancelButtonTitle:@"OK"
                      otherButtonTitles:nil] show];
}

#pragma mark - Носители

- (NSString *)displayNameForMediaPath:(NSString *)path
{
    return path.length > 0 ? [path lastPathComponent] : @"Нет";
}

- (void)pickMediaForCDROM:(BOOL)isCDROM
{
    NSArray *extensions = isCDROM ? @[ @"iso", @"img", @"bin" ]
                                  : @[ @"img", @"ima", @"dsk", @"vfd", @"flp" ];
    NSArray *paths = [[A5MachineStore sharedStore]
                      availableImagePathsWithExtensions:extensions];

    NSMutableArray *titles = [NSMutableArray arrayWithObject:@"Нет"];
    NSMutableArray *values = [NSMutableArray arrayWithObject:@""];
    for (NSString *path in paths) {
        [titles addObject:[path lastPathComponent]];
        [values addObject:path];
    }

    NSString *current = isCDROM ? self.machine.cdromPath : self.machine.floppyPath;
    A5ValuePickerViewController *picker = [[A5ValuePickerViewController alloc]
        initWithTitle:(isCDROM ? @"CD/DVD" : @"Дискета")
               titles:titles
               values:values
        selectedValue:(current.length > 0 ? current : @"")
           completion:^(id selectedValue) {
               NSString *path = [selectedValue length] > 0 ? selectedValue : nil;
               if (isCDROM) {
                   self.machine.cdromPath = path;
               } else {
                   self.machine.floppyPath = path;
               }
               [self saveAndReload];
           }];
    picker.footerText = paths.count > 0
        ? @"Показаны образы из папки Documents."
        : @"В папке Documents нет подходящих образов. "
           "Скопируйте их на устройство и вернитесь сюда.";
    [self.navigationController pushViewController:picker animated:YES];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return A5MachineSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case A5MachineSectionName:   return 1;
        case A5MachineSectionSystem: return 2;   // процессор, память
        case A5MachineSectionMedia:  return 3;   // диск, CD, дискета
        case A5MachineSectionBoot:   return 2;   // источник загрузки, указатель
        case A5MachineSectionRun:    return 1;
        default:                     return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case A5MachineSectionName:   return @"Имя";
        case A5MachineSectionSystem: return @"Система";
        case A5MachineSectionMedia:  return @"Носители";
        case A5MachineSectionBoot:   return @"Загрузка";
        default:                     return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == A5MachineSectionBoot) {
        return @"Абсолютный указатель добавляет USB-планшет: тап попадает "
                "точно в точку касания. Windows 95 и 98 поддерживают его "
                "штатно, MS-DOS — нет.";
    }
    if (section == A5MachineSectionSystem) {
        return @"Больше памяти — больше шансов, что iOS завершит приложение. "
                "Для Windows 98 разумный предел — 64 МБ.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == A5MachineSectionName) {
        return [self nameCellForTableView:tableView];
    }

    if (indexPath.section == A5MachineSectionRun) {
        static NSString *const identifier = @"Run";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:identifier];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.font = [UIFont boldSystemFontOfSize:17.0f];
        }
        cell.textLabel.text = @"Запустить";
        return cell;
    }

    if (indexPath.section == A5MachineSectionBoot && indexPath.row == 1) {
        static NSString *const identifier = @"Switch";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:identifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *toggle = [[UISwitch alloc] init];
            [toggle addTarget:self
                       action:@selector(pointerModeChanged:)
             forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        }
        cell.textLabel.text = @"Абсолютный указатель";
        [(UISwitch *)cell.accessoryView setOn:self.machine.usesAbsolutePointer];
        return cell;
    }

    static NSString *const identifier = @"Value";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                      reuseIdentifier:identifier];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    switch (indexPath.section) {
        case A5MachineSectionSystem:
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Процессор";
                cell.detailTextLabel.text = self.machine.cpuModel;
            } else {
                cell.textLabel.text = @"Память";
                cell.detailTextLabel.text =
                    [NSString stringWithFormat:@"%lu МБ",
                     (unsigned long)self.machine.ramMegabytes];
            }
            break;

        case A5MachineSectionMedia:
            if (indexPath.row == 0) {
                cell.textLabel.text = @"Жёсткий диск";
                cell.detailTextLabel.text = self.machine.hardDiskMegabytes > 0
                    ? [NSString stringWithFormat:@"%lu МБ",
                       (unsigned long)self.machine.hardDiskMegabytes]
                    : @"Нет";
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"CD/DVD";
                cell.detailTextLabel.text =
                    [self displayNameForMediaPath:self.machine.cdromPath];
            } else {
                cell.textLabel.text = @"Дискета";
                cell.detailTextLabel.text =
                    [self displayNameForMediaPath:self.machine.floppyPath];
            }
            break;

        case A5MachineSectionBoot:
            cell.textLabel.text = @"Загружаться с";
            cell.detailTextLabel.text =
                [A5Machine displayNameForBootDevice:self.machine.bootDevice];
            break;

        default:
            break;
    }
    return cell;
}

- (UITableViewCell *)nameCellForTableView:(UITableView *)tableView
{
    static NSString *const identifier = @"Name";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UITextField *field = [[UITextField alloc]
            initWithFrame:CGRectMake(15.0f, 0.0f,
                                     CGRectGetWidth(cell.contentView.bounds) - 30.0f,
                                     CGRectGetHeight(cell.contentView.bounds))];
        field.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                 UIViewAutoresizingFlexibleHeight;
        field.font = [UIFont systemFontOfSize:17.0f];
        field.returnKeyType = UIReturnKeyDone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.delegate = self;
        [cell.contentView addSubview:field];
        self.nameField = field;
    }
    self.nameField.text = self.machine.name;
    return cell;
}

- (void)pointerModeChanged:(UISwitch *)toggle
{
    self.machine.usesAbsolutePointer = toggle.isOn;
    [[A5MachineStore sharedStore] saveMachine:self.machine];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.nameField resignFirstResponder];

    switch (indexPath.section) {
        case A5MachineSectionSystem:
            if (indexPath.row == 0) {
                [self pickCPU];
            } else {
                [self pickRAM];
            }
            break;

        case A5MachineSectionMedia:
            if (indexPath.row == 0) {
                [self pickDiskSize];
            } else {
                [self pickMediaForCDROM:(indexPath.row == 1)];
            }
            break;

        case A5MachineSectionBoot:
            if (indexPath.row == 0) {
                [self pickBootDevice];
            }
            break;

        case A5MachineSectionRun:
            [self runMachine];
            break;

        default:
            break;
    }
}

#pragma mark - Выбор значений

- (void)pickCPU
{
    NSArray *models = [A5Machine availableCPUModels];
    A5ValuePickerViewController *picker = [[A5ValuePickerViewController alloc]
        initWithTitle:@"Процессор"
               titles:models
               values:models
        selectedValue:self.machine.cpuModel
           completion:^(id selectedValue) {
               self.machine.cpuModel = selectedValue;
               [self saveAndReload];
           }];
    picker.footerText = @"486 — для MS-DOS и Windows 3.1, pentium — для "
                         "Windows 95, pentium2 — для Windows 98.";
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)pickRAM
{
    NSArray *sizes = [A5Machine availableRAMSizes];
    NSMutableArray *titles = [NSMutableArray array];
    for (NSNumber *size in sizes) {
        [titles addObject:[NSString stringWithFormat:@"%@ МБ", size]];
    }

    A5ValuePickerViewController *picker = [[A5ValuePickerViewController alloc]
        initWithTitle:@"Память"
               titles:titles
               values:sizes
        selectedValue:@(self.machine.ramMegabytes)
           completion:^(id selectedValue) {
               self.machine.ramMegabytes = [selectedValue unsignedIntegerValue];
               [self saveAndReload];
           }];
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)pickBootDevice
{
    NSArray *values = @[ A5BootHardDisk, A5BootCDROM, A5BootFloppy ];
    NSMutableArray *titles = [NSMutableArray array];
    for (NSString *value in values) {
        [titles addObject:[A5Machine displayNameForBootDevice:value]];
    }

    A5ValuePickerViewController *picker = [[A5ValuePickerViewController alloc]
        initWithTitle:@"Загружаться с"
               titles:titles
               values:values
        selectedValue:self.machine.bootDevice
           completion:^(id selectedValue) {
               self.machine.bootDevice = selectedValue;
               [self saveAndReload];
           }];
    picker.footerText = @"Если выбранного носителя не окажется, машина "
                         "загрузится с того, что подключено.";
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)pickDiskSize
{
    NSArray *sizes = [A5Machine availableDiskSizes];
    NSMutableArray *titles = [NSMutableArray array];
    for (NSNumber *size in sizes) {
        [titles addObject:(size.unsignedIntegerValue == 0
                           ? @"Нет"
                           : [NSString stringWithFormat:@"%@ МБ", size])];
    }

    A5ValuePickerViewController *picker = [[A5ValuePickerViewController alloc]
        initWithTitle:@"Жёсткий диск"
               titles:titles
               values:sizes
        selectedValue:@(self.machine.hardDiskMegabytes)
           completion:^(id selectedValue) {
               [self applyDiskSize:selectedValue];
           }];
    picker.footerText = @"Образ создаётся разреженным: место занимается по "
                         "мере записи, а не сразу целиком.";
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)applyDiskSize:(NSNumber *)size
{
    if (size.unsignedIntegerValue == self.machine.hardDiskMegabytes) {
        return;
    }

    BOOL imageExists = [[NSFileManager defaultManager]
                        fileExistsAtPath:self.machine.hardDiskPath];
    if (!imageExists) {
        self.machine.hardDiskMegabytes = size.unsignedIntegerValue;
        [self saveAndReload];
        return;
    }

    // Менять размер уже созданного образа нельзя незаметно для пользователя:
    // всё, что на нём установлено, будет потеряно.
    self.pendingDiskSize = size;
    [[[UIAlertView alloc] initWithTitle:@"Образ будет создан заново"
                                message:@"Всё содержимое жёсткого диска этой "
                                         "машины будет удалено. Продолжить?"
                               delegate:self
                      cancelButtonTitle:@"Отмена"
                      otherButtonTitles:@"Удалить", nil] show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex || !self.pendingDiskSize) {
        self.pendingDiskSize = nil;
        [self.tableView reloadData];
        return;
    }

    [[NSFileManager defaultManager] removeItemAtPath:self.machine.hardDiskPath
                                               error:NULL];
    self.machine.hardDiskMegabytes = self.pendingDiskSize.unsignedIntegerValue;
    self.pendingDiskSize = nil;
    [self saveAndReload];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    [self commitName];
    return NO;
}

@end

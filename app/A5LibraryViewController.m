//
//  A5LibraryViewController.m
//

#import "A5LibraryViewController.h"
#import "A5Machine.h"
#import "A5MachineStore.h"
#import "A5MachineViewController.h"
#import "A5NewMachineViewController.h"

@interface A5LibraryViewController () <A5NewMachineViewControllerDelegate>
@end

@implementation A5LibraryViewController

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"Машины";
    self.navigationItem.leftBarButtonItem = self.editButtonItem;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self
                                                      action:@selector(addMachine)];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // Список перечитывается с диска: машину могли переименовать на экране
    // настроек, а образы — добавить по SSH, пока приложение было в фоне.
    [[A5MachineStore sharedStore] reload];
    [self.tableView reloadData];
    [self updateEditButtonState];
}

- (void)updateEditButtonState
{
    BOOL hasMachines = [[A5MachineStore sharedStore] machines].count > 0;
    self.editButtonItem.enabled = hasMachines;
    if (!hasMachines && self.editing) {
        [self setEditing:NO animated:YES];
    }
}

#pragma mark - Создание

- (void)addMachine
{
    A5NewMachineViewController *controller = [[A5NewMachineViewController alloc] init];
    controller.delegate = self;
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:controller];
    [self presentViewController:navigation animated:YES completion:NULL];
}

- (void)newMachineViewController:(A5NewMachineViewController *)controller
                didCreateMachine:(A5Machine *)machine
{
    [[A5MachineStore sharedStore] addMachine:machine];
    [self dismissViewControllerAnimated:YES completion:^{
        [self.tableView reloadData];
        [self updateEditButtonState];
        // Сразу открываем настройки новой машины: там пользователь выбирает
        // образ, без которого запускать всё равно нечего.
        [self openMachine:machine];
    }];
}

- (void)newMachineViewControllerDidCancel:(A5NewMachineViewController *)controller
{
    [self dismissViewControllerAnimated:YES completion:NULL];
}

- (void)openMachine:(A5Machine *)machine
{
    A5MachineViewController *controller =
        [[A5MachineViewController alloc] initWithMachine:machine];
    [self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)[[A5MachineStore sharedStore] machines].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if ([[A5MachineStore sharedStore] machines].count == 0) {
        return @"Нажмите «+», чтобы создать виртуальную машину. "
                "Образы дисков положите в папку Documents — они появятся в списке носителей.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *const identifier = @"Machine";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    A5Machine *machine = [[A5MachineStore sharedStore] machines][(NSUInteger)indexPath.row];
    cell.textLabel.text = machine.name;
    cell.detailTextLabel.text = [machine summaryDescription];
    return cell;
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }
    A5Machine *machine = [[A5MachineStore sharedStore] machines][(NSUInteger)indexPath.row];
    [[A5MachineStore sharedStore] removeMachine:machine];
    [tableView deleteRowsAtIndexPaths:@[ indexPath ]
                     withRowAnimation:UITableViewRowAnimationAutomatic];
    [self updateEditButtonState];
    if ([[A5MachineStore sharedStore] machines].count == 0) {
        [tableView reloadData];   // чтобы вернулась поясняющая подпись
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self openMachine:[[A5MachineStore sharedStore] machines][(NSUInteger)indexPath.row]];
}

@end

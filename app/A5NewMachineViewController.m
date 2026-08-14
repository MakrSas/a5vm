//
//  A5NewMachineViewController.m
//

#import "A5NewMachineViewController.h"
#import "A5Machine.h"

@interface A5NewMachineViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, copy)   NSString *selectedTemplate;
@end

@implementation A5NewMachineViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _selectedTemplate = A5TemplateWindows98;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"Новая машина";
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                      target:self
                                                      action:@selector(save)];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.nameField becomeFirstResponder];
}

- (void)cancel
{
    [self.delegate newMachineViewControllerDidCancel:self];
}

- (void)save
{
    NSString *name = [self.nameField.text
                      stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) {
        name = [A5Machine displayNameForTemplate:self.selectedTemplate];
    }
    A5Machine *machine = [A5Machine machineWithTemplateIdentifier:self.selectedTemplate
                                                             name:name];
    [self.delegate newMachineViewController:self didCreateMachine:machine];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 1 : (NSInteger)[A5Machine allTemplateIdentifiers].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return section == 0 ? @"Имя" : @"Гостевая ОС";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 1) {
        return @"Шаблон задаёт процессор, объём памяти и размер диска. "
                "Всё это потом можно изменить.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
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
            field.placeholder = @"Windows 98";
            field.font = [UIFont systemFontOfSize:17.0f];
            field.returnKeyType = UIReturnKeyDone;
            field.autocorrectionType = UITextAutocorrectionTypeNo;
            field.clearButtonMode = UITextFieldViewModeWhileEditing;
            field.delegate = self;
            [cell.contentView addSubview:field];
            self.nameField = field;
        }
        return cell;
    }

    static NSString *const identifier = @"Template";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier];
    }

    NSString *templateIdentifier =
        [A5Machine allTemplateIdentifiers][(NSUInteger)indexPath.row];
    cell.textLabel.text = [A5Machine displayNameForTemplate:templateIdentifier];
    cell.accessoryType = [templateIdentifier isEqualToString:self.selectedTemplate]
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) {
        return;
    }
    self.selectedTemplate = [A5Machine allTemplateIdentifiers][(NSUInteger)indexPath.row];
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
             withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return NO;
}

@end

//
//  A5ValuePickerViewController.m
//

#import "A5ValuePickerViewController.h"

@interface A5ValuePickerViewController ()
@property (nonatomic, copy) NSArray *titles;
@property (nonatomic, copy) NSArray *values;
@property (nonatomic, strong) id selectedValue;
@property (nonatomic, copy) void (^completion)(id);
@end

@implementation A5ValuePickerViewController

- (instancetype)initWithTitle:(NSString *)title
                       titles:(NSArray *)titles
                       values:(NSArray *)values
                selectedValue:(id)selectedValue
                   completion:(void (^)(id))completion
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.title = title;
        _titles = [titles copy];
        _values = [values copy];
        _selectedValue = selectedValue;
        _completion = [completion copy];
    }
    return self;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.titles.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return self.footerText;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *const identifier = @"Value";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier];
    }

    cell.textLabel.text = self.titles[(NSUInteger)indexPath.row];
    id value = self.values[(NSUInteger)indexPath.row];
    cell.accessoryType = [value isEqual:self.selectedValue]
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    self.selectedValue = self.values[(NSUInteger)indexPath.row];
    [tableView reloadData];
    if (self.completion) {
        self.completion(self.selectedValue);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end

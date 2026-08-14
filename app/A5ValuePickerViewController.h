//
//  A5ValuePickerViewController.h
//  Список с одной галочкой — стандартный для iOS способ выбрать значение
//  на отдельном экране, вместо нестандартных выпадающих меню.
//

#import <UIKit/UIKit.h>

@interface A5ValuePickerViewController : UITableViewController

/// titles — то, что видит пользователь; values — то, что кладётся в конфиг.
/// Массивы должны быть одной длины.
- (instancetype)initWithTitle:(NSString *)title
                       titles:(NSArray *)titles
                       values:(NSArray *)values
                selectedValue:(id)selectedValue
                   completion:(void (^)(id selectedValue))completion;

/// Пояснение под списком.  Необязательно.
@property (nonatomic, copy) NSString *footerText;

@end

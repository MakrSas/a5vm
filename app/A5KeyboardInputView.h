//
//  A5KeyboardInputView.h
//  Невидимый первый респондер, поднимающий системную клавиатуру.
//
//  В iOS 6 нет доступа к событиям физических клавиш, поэтому текст
//  приходит уже готовыми символами через UIKeyInput, а обратно
//  восстанавливаются код клавиши и состояние Shift.
//
//  Клавиши, которых на экранной клавиатуре нет (Esc, Tab, стрелки) и
//  модификаторы Ctrl/Alt живут в inputAccessoryView — обычном UIToolbar.
//

#import <UIKit/UIKit.h>
#import "a5_qemu.h"

@class A5KeyboardInputView;

@protocol A5KeyboardInputViewDelegate <NSObject>
/// Нажатие и отпускание одной клавиши; модификаторы уже учтены.
- (void)keyboardInputView:(A5KeyboardInputView *)view
               didTapKey:(a5_qemu_key)key
                   shift:(BOOL)shift
                 control:(BOOL)control
                     alt:(BOOL)alt;
@end

@interface A5KeyboardInputView : UIView <UIKeyInput>

@property (nonatomic, weak) id<A5KeyboardInputViewDelegate> keyDelegate;

@end

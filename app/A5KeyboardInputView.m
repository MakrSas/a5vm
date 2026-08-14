//
//  A5KeyboardInputView.m
//

#import "A5KeyboardInputView.h"

@interface A5KeyboardInputView ()
@property (nonatomic, strong) UIToolbar *accessoryToolbar;
@property (nonatomic, strong) UIBarButtonItem *controlItem;
@property (nonatomic, strong) UIBarButtonItem *altItem;
@property (nonatomic, assign) BOOL controlHeld;
@property (nonatomic, assign) BOOL altHeld;
@end

@implementation A5KeyboardInputView

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

#pragma mark - Панель дополнительных клавиш

- (UIView *)inputAccessoryView
{
    if (_accessoryToolbar) {
        return _accessoryToolbar;
    }

    _accessoryToolbar = [[UIToolbar alloc]
        initWithFrame:CGRectMake(0.0f, 0.0f,
                                 CGRectGetWidth([[UIScreen mainScreen] bounds]), 44.0f)];
    _accessoryToolbar.barStyle = UIBarStyleBlack;
    _accessoryToolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    _controlItem = [self itemWithTitle:@"Ctrl" action:@selector(toggleControl)];
    _altItem     = [self itemWithTitle:@"Alt"  action:@selector(toggleAlt)];

    UIBarButtonItem *flexible = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                             target:nil action:nil];

    _accessoryToolbar.items = @[
        [self itemWithTitle:@"Esc" action:@selector(tapEscape)],
        [self itemWithTitle:@"Tab" action:@selector(tapTab)],
        _controlItem,
        _altItem,
        flexible,
        [self itemWithTitle:@"←" action:@selector(tapLeft)],
        [self itemWithTitle:@"↑" action:@selector(tapUp)],
        [self itemWithTitle:@"↓" action:@selector(tapDown)],
        [self itemWithTitle:@"→" action:@selector(tapRight)]
    ];
    return _accessoryToolbar;
}

- (UIBarButtonItem *)itemWithTitle:(NSString *)title action:(SEL)action
{
    return [[UIBarButtonItem alloc] initWithTitle:title
                                            style:UIBarButtonItemStyleBordered
                                           target:self
                                           action:action];
}

/// Активный модификатор показывается стилем Done — в iOS 6 это единственный
/// штатный способ выделить UIBarButtonItem, не рисуя свою кнопку.
- (void)updateModifierAppearance
{
    _controlItem.style = _controlHeld ? UIBarButtonItemStyleDone
                                      : UIBarButtonItemStyleBordered;
    _altItem.style     = _altHeld     ? UIBarButtonItemStyleDone
                                      : UIBarButtonItemStyleBordered;
}

- (void)toggleControl
{
    _controlHeld = !_controlHeld;
    [self updateModifierAppearance];
}

- (void)toggleAlt
{
    _altHeld = !_altHeld;
    [self updateModifierAppearance];
}

- (void)tapEscape { [self emitKey:A5_KEY_ESC shift:NO]; }
- (void)tapTab    { [self emitKey:A5_KEY_TAB shift:NO]; }
- (void)tapLeft   { [self emitKey:A5_KEY_LEFT shift:NO]; }
- (void)tapRight  { [self emitKey:A5_KEY_RIGHT shift:NO]; }
- (void)tapUp     { [self emitKey:A5_KEY_UP shift:NO]; }
- (void)tapDown   { [self emitKey:A5_KEY_DOWN shift:NO]; }

/// Отправляет клавишу и сбрасывает залипшие модификаторы: Ctrl и Alt здесь
/// одноразовые, как в системных панелях спецсимволов.
- (void)emitKey:(a5_qemu_key)key shift:(BOOL)shift
{
    if (key == A5_KEY_NONE) {
        return;
    }
    [self.keyDelegate keyboardInputView:self
                              didTapKey:key
                                  shift:shift
                                control:_controlHeld
                                    alt:_altHeld];
    if (_controlHeld || _altHeld) {
        _controlHeld = NO;
        _altHeld = NO;
        [self updateModifierAppearance];
    }
}

#pragma mark - UIKeyInput

- (BOOL)hasText
{
    // Всегда YES, иначе система не присылает deleteBackward.
    return YES;
}

- (UIKeyboardType)keyboardType
{
    return UIKeyboardTypeASCIICapable;
}

- (UITextAutocorrectionType)autocorrectionType
{
    // Автокоррекция подставила бы в гостя не то, что нажал пользователь.
    return UITextAutocorrectionTypeNo;
}

- (UITextAutocapitalizationType)autocapitalizationType
{
    return UITextAutocapitalizationTypeNone;
}

- (void)insertText:(NSString *)text
{
    for (NSUInteger index = 0; index < text.length; index++) {
        BOOL shift = NO;
        a5_qemu_key key = [A5KeyboardInputView keyForCharacter:[text characterAtIndex:index]
                                                          shift:&shift];
        [self emitKey:key shift:shift];
    }
}

- (void)deleteBackward
{
    [self emitKey:A5_KEY_BACKSPACE shift:NO];
}

/// Обратное преобразование символа в клавишу PC-раскладки.  Символы, которых
/// на американской раскладке нет (кириллица и прочее), отбрасываются: без
/// знания раскладки внутри гостя послать их осмысленно невозможно.
+ (a5_qemu_key)keyForCharacter:(unichar)character shift:(BOOL *)shift
{
    *shift = NO;

    if (character >= 'a' && character <= 'z') {
        return (a5_qemu_key)(A5_KEY_A + (character - 'a'));
    }
    if (character >= 'A' && character <= 'Z') {
        *shift = YES;
        return (a5_qemu_key)(A5_KEY_A + (character - 'A'));
    }
    if (character >= '0' && character <= '9') {
        return (a5_qemu_key)(A5_KEY_0 + (character - '0'));
    }

    switch (character) {
        case '\n': case '\r': return A5_KEY_RETURN;
        case ' ':  return A5_KEY_SPACE;
        case '\t': return A5_KEY_TAB;

        case '-':  return A5_KEY_MINUS;
        case '=':  return A5_KEY_EQUAL;
        case '[':  return A5_KEY_BRACKET_LEFT;
        case ']':  return A5_KEY_BRACKET_RIGHT;
        case '\\': return A5_KEY_BACKSLASH;
        case ';':  return A5_KEY_SEMICOLON;
        case '\'': return A5_KEY_APOSTROPHE;
        case '`':  return A5_KEY_GRAVE;
        case ',':  return A5_KEY_COMMA;
        case '.':  return A5_KEY_DOT;
        case '/':  return A5_KEY_SLASH;

        // Верхний регистр той же клавиши.
        case '!':  *shift = YES; return A5_KEY_1;
        case '@':  *shift = YES; return A5_KEY_2;
        case '#':  *shift = YES; return A5_KEY_3;
        case '$':  *shift = YES; return A5_KEY_4;
        case '%':  *shift = YES; return A5_KEY_5;
        case '^':  *shift = YES; return A5_KEY_6;
        case '&':  *shift = YES; return A5_KEY_7;
        case '*':  *shift = YES; return A5_KEY_8;
        case '(':  *shift = YES; return A5_KEY_9;
        case ')':  *shift = YES; return A5_KEY_0;
        case '_':  *shift = YES; return A5_KEY_MINUS;
        case '+':  *shift = YES; return A5_KEY_EQUAL;
        case '{':  *shift = YES; return A5_KEY_BRACKET_LEFT;
        case '}':  *shift = YES; return A5_KEY_BRACKET_RIGHT;
        case '|':  *shift = YES; return A5_KEY_BACKSLASH;
        case ':':  *shift = YES; return A5_KEY_SEMICOLON;
        case '"':  *shift = YES; return A5_KEY_APOSTROPHE;
        case '~':  *shift = YES; return A5_KEY_GRAVE;
        case '<':  *shift = YES; return A5_KEY_COMMA;
        case '>':  *shift = YES; return A5_KEY_DOT;
        case '?':  *shift = YES; return A5_KEY_SLASH;

        default:   return A5_KEY_NONE;
    }
}

@end

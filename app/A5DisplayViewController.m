//
//  A5DisplayViewController.m
//

#import "A5DisplayViewController.h"

#import "A5DisplayView.h"
#import "A5KeyboardInputView.h"
#import "A5Machine.h"
#import "A5QemuRunner.h"

/// Действия в меню кнопки питания.
typedef NS_ENUM(NSInteger, A5PowerAction) {
    A5PowerActionCtrlAltDelete,
    A5PowerActionShutdown,
    A5PowerActionForceQuit
};

@interface A5DisplayViewController () <A5QemuRunnerDelegate,
                                       A5KeyboardInputViewDelegate,
                                       UIActionSheetDelegate>

@property (nonatomic, strong) A5Machine *machine;
@property (nonatomic, strong) A5QemuRunner *runner;
@property (nonatomic, copy)   NSArray *arguments;

@property (nonatomic, strong) A5DisplayView *displayView;
@property (nonatomic, strong) A5KeyboardInputView *keyboardInput;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@property (nonatomic, strong) UIBarButtonItem *pauseItem;
@property (nonatomic, assign, getter=isPaused) BOOL paused;

/// Состояние жеста-указателя.  Первое касание ведёт левую кнопку, приход
/// второго пальца превращает жест в правый клик.
@property (nonatomic, weak)   UITouch *activeTouch;
@property (nonatomic, assign) BOOL rightClickGesture;
@property (nonatomic, assign) CGPoint lastGuestPoint;
@property (nonatomic, assign) BOOL hasLastGuestPoint;

@property (nonatomic, assign) BOOL leavingIntentionally;

@end

@implementation A5DisplayViewController

- (instancetype)initWithMachine:(A5Machine *)machine
                         runner:(A5QemuRunner *)runner
                      arguments:(NSArray *)arguments
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _machine = machine;
        _runner = runner;
        _arguments = [arguments copy];
        _runner.delegate = self;
    }
    return self;
}

#pragma mark - Жизненный цикл

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = self.machine.name;
    self.view.backgroundColor = [UIColor blackColor];

    self.displayView = [[A5DisplayView alloc] initWithFrame:self.view.bounds];
    self.displayView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                        UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.displayView];

    // Пока гость не отдал первый кадр, экран чёрный — без пояснения это
    // неотличимо от зависшего приложения.
    self.spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.center = CGPointMake(CGRectGetMidX(self.view.bounds),
                                      CGRectGetMidY(self.view.bounds) - 20.0f);
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleTopMargin |
                                    UIViewAutoresizingFlexibleBottomMargin |
                                    UIViewAutoresizingFlexibleLeftMargin |
                                    UIViewAutoresizingFlexibleRightMargin;
    [self.spinner startAnimating];
    [self.view addSubview:self.spinner];

    self.statusLabel = [[UILabel alloc] initWithFrame:
        CGRectMake(0.0f, CGRectGetMidY(self.view.bounds) + 16.0f,
                   CGRectGetWidth(self.view.bounds), 20.0f)];
    self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                        UIViewAutoresizingFlexibleTopMargin |
                                        UIViewAutoresizingFlexibleBottomMargin;
    self.statusLabel.backgroundColor = [UIColor clearColor];
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:14.0f];
    self.statusLabel.text = @"Запуск…";
    [self.view addSubview:self.statusLabel];

    self.keyboardInput = [[A5KeyboardInputView alloc] initWithFrame:CGRectZero];
    self.keyboardInput.keyDelegate = self;
    [self.view addSubview:self.keyboardInput];

    [self configureBars];
}

- (void)configureBars
{
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Выход"
                                         style:UIBarButtonItemStyleBordered
                                        target:self
                                        action:@selector(confirmExit)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Клавиатура"
                                         style:UIBarButtonItemStyleBordered
                                        target:self
                                        action:@selector(toggleKeyboard)];

    self.pauseItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemPause
                             target:self
                             action:@selector(togglePause)];

    UIBarButtonItem *reset = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                             target:self
                             action:@selector(confirmReset)];

    UIBarButtonItem *power = [[UIBarButtonItem alloc]
        initWithTitle:@"Питание"
                style:UIBarButtonItemStyleBordered
               target:self
               action:@selector(showPowerMenu)];

    UIBarButtonItem *flexible = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                             target:nil action:nil];

    self.toolbarItems = @[ flexible, self.pauseItem, flexible,
                           reset, flexible, power, flexible ];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:NO animated:animated];
    // Каждые 20 точек по вертикали заметны на экране 3.5": статусная строка
    // во время работы машины не нужна.
    [[UIApplication sharedApplication] setStatusBarHidden:YES
                                            withAnimation:UIStatusBarAnimationFade];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if (!self.runner.running) {
        NSError *error = nil;
        if (![self.runner startWithArguments:self.arguments error:&error]) {
            [self reportStop:error];
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.navigationController setToolbarHidden:YES animated:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:NO
                                            withAnimation:UIStatusBarAnimationFade];
    [self.keyboardInput resignFirstResponder];

    // Уход с экрана назад в список — это и есть завершение работы машины:
    // фонового режима для ВМ нет, а оставлять поток QEMU без экрана незачем.
    if (self.isMovingFromParentViewController && self.runner.running) {
        [self.runner requestQuit];
    }
}

#pragma mark - Управление

- (void)togglePause
{
    self.paused = !self.paused;
    [self.runner setPaused:self.paused];
    self.pauseItem.style = UIBarButtonItemStyleBordered;

    NSInteger index = [self.toolbarItems indexOfObject:self.pauseItem];
    UIBarButtonItem *replacement = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:(self.paused ? UIBarButtonSystemItemPlay
                                                 : UIBarButtonSystemItemPause)
                             target:self
                             action:@selector(togglePause)];
    NSMutableArray *items = [self.toolbarItems mutableCopy];
    items[(NSUInteger)index] = replacement;
    self.pauseItem = replacement;
    self.toolbarItems = items;
}

- (void)toggleKeyboard
{
    if ([self.keyboardInput isFirstResponder]) {
        [self.keyboardInput resignFirstResponder];
    } else {
        [self.keyboardInput becomeFirstResponder];
    }
}

- (void)confirmReset
{
    UIActionSheet *sheet = [[UIActionSheet alloc]
        initWithTitle:@"Перезагрузить машину? Несохранённые данные гостя будут потеряны."
             delegate:self
        cancelButtonTitle:@"Отмена"
        destructiveButtonTitle:@"Перезагрузить"
        otherButtonTitles:nil];
    sheet.tag = 1;
    [sheet showFromToolbar:self.navigationController.toolbar];
}

- (void)showPowerMenu
{
    UIActionSheet *sheet = [[UIActionSheet alloc]
        initWithTitle:nil
             delegate:self
        cancelButtonTitle:@"Отмена"
        destructiveButtonTitle:@"Завершить принудительно"
        otherButtonTitles:@"Ctrl+Alt+Del", @"Выключить (ACPI)", nil];
    sheet.tag = 2;
    [sheet showFromToolbar:self.navigationController.toolbar];
}

- (void)confirmExit
{
    UIActionSheet *sheet = [[UIActionSheet alloc]
        initWithTitle:@"Работа машины будет завершена."
             delegate:self
        cancelButtonTitle:@"Отмена"
        destructiveButtonTitle:@"Выйти"
        otherButtonTitles:nil];
    sheet.tag = 3;
    [sheet showFromBarButtonItem:self.navigationItem.leftBarButtonItem animated:YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == actionSheet.cancelButtonIndex) {
        return;
    }

    switch (actionSheet.tag) {
        case 1:
            [self.runner requestReset];
            break;

        case 2:
            // destructiveButtonIndex == 0, дальше идут otherButtonTitles.
            if (buttonIndex == actionSheet.destructiveButtonIndex) {
                [self.runner requestQuit];
            } else if (buttonIndex == 1) {
                [self sendCtrlAltDelete];
            } else {
                [self.runner requestShutdown];
            }
            break;

        case 3:
            self.leavingIntentionally = YES;
            [self.navigationController popViewControllerAnimated:YES];
            break;

        default:
            break;
    }
}

- (void)sendCtrlAltDelete
{
    [self.runner sendKey:A5_KEY_CTRL down:YES];
    [self.runner sendKey:A5_KEY_ALT down:YES];
    [self.runner sendKey:A5_KEY_DELETE down:YES];
    [self.runner sendKey:A5_KEY_DELETE down:NO];
    [self.runner sendKey:A5_KEY_ALT down:NO];
    [self.runner sendKey:A5_KEY_CTRL down:NO];
}

#pragma mark - A5QemuRunnerDelegate

- (void)qemuRunner:(A5QemuRunner *)runner didProduceFrame:(CGImageRef)image
{
    if (!self.spinner.hidden) {
        self.spinner.hidden = YES;
        [self.spinner stopAnimating];
        self.statusLabel.hidden = YES;
    }
    [self.displayView setFrameImage:image];
}

- (void)qemuRunner:(A5QemuRunner *)runner didStopWithError:(NSError *)error
{
    [self reportStop:error];
}

- (void)reportStop:(NSError *)error
{
    if (self.leavingIntentionally) {
        return;
    }

    self.spinner.hidden = YES;
    [self.spinner stopAnimating];

    NSString *message = error.localizedDescription;
    [[[UIAlertView alloc]
        initWithTitle:@"Машина остановлена"
              message:(message.length > 0 ? message : @"Гостевая система завершила работу.")
             delegate:nil
        cancelButtonTitle:@"OK"
        otherButtonTitles:nil] show];

    self.leavingIntentionally = YES;
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - A5KeyboardInputViewDelegate

- (void)keyboardInputView:(A5KeyboardInputView *)view
                didTapKey:(a5_qemu_key)key
                    shift:(BOOL)shift
                  control:(BOOL)control
                      alt:(BOOL)alt
{
    if (control) { [self.runner sendKey:A5_KEY_CTRL down:YES]; }
    if (alt)     { [self.runner sendKey:A5_KEY_ALT down:YES]; }
    if (shift)   { [self.runner sendKey:A5_KEY_SHIFT down:YES]; }

    [self.runner sendKey:key down:YES];
    [self.runner sendKey:key down:NO];

    if (shift)   { [self.runner sendKey:A5_KEY_SHIFT down:NO]; }
    if (alt)     { [self.runner sendKey:A5_KEY_ALT down:NO]; }
    if (control) { [self.runner sendKey:A5_KEY_CTRL down:NO]; }
}

#pragma mark - Указатель

- (void)sendPointerAtGuestPoint:(CGPoint)point buttons:(int)buttons
{
    if (self.machine.usesAbsolutePointer) {
        [self.runner sendPointerAtX:(int)point.x y:(int)point.y
                            buttons:buttons absolute:YES];
    } else {
        // В относительном режиме гостю нужны приращения, а не координаты.
        int deltaX = 0;
        int deltaY = 0;
        if (self.hasLastGuestPoint) {
            deltaX = (int)(point.x - self.lastGuestPoint.x);
            deltaY = (int)(point.y - self.lastGuestPoint.y);
        }
        [self.runner sendPointerAtX:deltaX y:deltaY buttons:buttons absolute:NO];
    }
    self.lastGuestPoint = point;
    self.hasLastGuestPoint = YES;
}

- (BOOL)guestPointForTouch:(UITouch *)touch point:(CGPoint *)point
{
    CGPoint viewPoint = [touch locationInView:self.displayView];
    return [self.displayView guestPoint:point forViewPoint:viewPoint];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches) {
        if (!self.activeTouch) {
            CGPoint point;
            if (![self guestPointForTouch:touch point:&point]) {
                continue;
            }
            self.activeTouch = touch;
            self.rightClickGesture = NO;
            [self sendPointerAtGuestPoint:point buttons:A5_BUTTON_LEFT];
        } else if (!self.rightClickGesture) {
            // Второй палец — значит это правый клик, а не перетаскивание.
            // Левую кнопку, уже нажатую первым касанием, надо отпустить.
            self.rightClickGesture = YES;
            [self sendPointerAtGuestPoint:self.lastGuestPoint buttons:0];
        }
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    if (self.rightClickGesture || !self.activeTouch) {
        return;
    }
    if (![touches containsObject:self.activeTouch]) {
        return;
    }
    CGPoint point;
    if ([self guestPointForTouch:self.activeTouch point:&point]) {
        [self sendPointerAtGuestPoint:point buttons:A5_BUTTON_LEFT];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self finishTouches:touches withEvent:event cancelled:NO];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self finishTouches:touches withEvent:event cancelled:YES];
}

- (void)finishTouches:(NSSet *)touches withEvent:(UIEvent *)event cancelled:(BOOL)cancelled
{
    if (!self.activeTouch) {
        return;
    }

    // Ждём, пока с экрана уйдут все пальцы: иначе правый клик сработает в
    // момент, когда второй палец ещё лежит на экране.
    for (UITouch *touch in [event allTouches]) {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) {
            return;
        }
    }

    if (self.rightClickGesture && !cancelled) {
        [self sendPointerAtGuestPoint:self.lastGuestPoint buttons:A5_BUTTON_RIGHT];
        [self sendPointerAtGuestPoint:self.lastGuestPoint buttons:0];
    } else {
        [self sendPointerAtGuestPoint:self.lastGuestPoint buttons:0];
    }

    self.activeTouch = nil;
    self.rightClickGesture = NO;
}

@end

#import "A5VMViewController.h"
#import "A5VMDisplayView.h"
#import "A5VMIconButton.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>

@implementation A5VMViewController

- (void)addSpecialKeyButtonWithTitle:(NSString *)title tag:(NSInteger)tag {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = tag;
    button.backgroundColor = [UIColor colorWithWhite:0.18f alpha:0.96f];
    button.opaque = YES;
    button.titleLabel.font = [UIFont boldSystemFontOfSize:13.0f];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:0.65f alpha:1.0f]
                  forState:UIControlStateHighlighted];
    button.accessibilityLabel = title;
    [button addTarget:self action:@selector(sendSpecialKey:)
     forControlEvents:UIControlEventTouchUpInside];
    [_keyPanel addSubview:button];
}

- (void)queueKeyboardByte:(uint8_t)value {
    if (_runtime) (void)a5vm_keyboard_push(&_runtime->keyboard, value);
}

- (void)sendSpecialKey:(UIButton *)sender {
    NSInteger tag = sender.tag;
    if (tag >= 0x100) {
        [self queueKeyboardByte:0x00];
        [self queueKeyboardByte:(uint8_t)(tag - 0x100)];
    } else {
        [self queueKeyboardByte:(uint8_t)tag];
    }
    _statusLabel.text = [NSString stringWithFormat:@"Key queued (%u)",
                         _runtime ? _runtime->keyboard.count : 0u];
}

- (void)keyboardFrameChanged:(NSNotification *)notification {
    CGRect frame = [[[notification userInfo]
                     objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect localFrame = [self.view convertRect:frame fromView:nil];
    if (!_keyboardVisible || CGRectGetMinY(localFrame) >= CGRectGetHeight(self.view.bounds)) {
        _keyboardTop = 0.0f;
    } else {
        _keyboardTop = CGRectGetMinY(localFrame);
    }
    [self layoutOverlayControls];
}

- (id)init {
    return [self initWithMachine:nil];
}

- (id)initWithMachine:(NSDictionary *)machine {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _machine = [machine copy];
        if (!_machine) {
            _machine = [[NSDictionary alloc] initWithObjectsAndKeys:
                        @"8086 Demo PC", @"name",
                        @"8086", @"architecture",
                        @"640 KB", @"ram",
                        @"VGA Text", @"display",
                        @"1.44 MB floppy", @"storage",
                        @"8086-demo.dsk", @"diskImage",
                        nil];
        }
        _machineName = [[_machine objectForKey:@"name"] copy];
        _runtime = (a5vm_machine *)calloc(1, sizeof(a5vm_machine));
        if (!a5vm_machine_init(_runtime)) {
            free(_runtime);
            _runtime = NULL;
        } else {
            [self loadDiskImage];
            [self loadHardDiskImage];
        }
    }
    return self;
}

- (void)loadView {
    UIView *rootView = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    rootView.backgroundColor = [UIColor blackColor];
    self.view = rootView;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [[UIApplication sharedApplication] setStatusBarHidden:YES
                                             withAnimation:UIStatusBarAnimationNone];

    self.title = _machineName;

    CGRect bounds = self.view.bounds;
    _screenTitle = [[UILabel alloc] initWithFrame:CGRectMake(10.0f, 8.0f,
                                                               bounds.size.width - 180.0f, 28.0f)];
    _screenTitle.textColor = [UIColor whiteColor];
    _screenTitle.backgroundColor = [UIColor clearColor];
    _screenTitle.font = [UIFont boldSystemFontOfSize:20.0f];
    NSString *architecture = [_machine objectForKey:@"architecture"];
    if ([architecture length] == 0) architecture = @"8086 PC";
    _screenTitle.text = [NSString stringWithFormat:@"A5VM  /  %@", architecture];
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(bounds.size.width - 168.0f, 8.0f,
                                                               150.0f, 24.0f)];
    _statusLabel.text = @"Stopped";
    _statusLabel.textColor = [UIColor colorWithRed:0.45f green:1.0f blue:0.55f alpha:1.0f];
    _statusLabel.textAlignment = NSTextAlignmentRight;
    _statusLabel.backgroundColor = [UIColor clearColor];
    _statusLabel.font = [UIFont systemFontOfSize:13.0f];
    _controlPanel = [[UIView alloc] initWithFrame:CGRectMake(6.0f, 6.0f,
                                                               bounds.size.width - 56.0f, 48.0f)];
    _controlPanel.backgroundColor = [UIColor colorWithWhite:0.05f alpha:0.92f];
    _screenTitle.hidden = YES;
    _statusLabel.hidden = YES;
    [_controlPanel addSubview:_screenTitle];
    [_controlPanel addSubview:_statusLabel];
    [self.view addSubview:_controlPanel];

    _menuButton = [[A5VMIconButton alloc] initWithFrame:CGRectZero];
    _menuButton.iconType = A5VMIconArrowRight;
    _menuButton.accessibilityLabel = @"Show VM controls";
    [_menuButton addTarget:self action:@selector(toggleControls:)
          forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_menuButton];

    _displayView = [[A5VMDisplayView alloc] initWithFrame:bounds];
    _displayView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:_displayView atIndex:0];

    _runButton = [[A5VMIconButton alloc] initWithFrame:CGRectZero];
    _runButton.iconType = A5VMIconRun;
    _runButton.accessibilityLabel = @"Run VM";
    [_runButton addTarget:self action:@selector(runDemo:)
          forControlEvents:UIControlEventTouchUpInside];
    [_controlPanel addSubview:_runButton];

    _resetButton = [[A5VMIconButton alloc] initWithFrame:CGRectZero];
    _resetButton.iconType = A5VMIconReset;
    _resetButton.accessibilityLabel = @"Reset VM";
    [_resetButton addTarget:self action:@selector(resetVM:)
          forControlEvents:UIControlEventTouchUpInside];
    [_controlPanel addSubview:_resetButton];

    _powerButton = [[A5VMIconButton alloc] initWithFrame:CGRectZero];
    _powerButton.iconType = A5VMIconPower;
    _powerButton.accessibilityLabel = @"Power VM";
    [_powerButton addTarget:self action:@selector(powerVM:)
           forControlEvents:UIControlEventTouchUpInside];
    [_controlPanel addSubview:_powerButton];

    _pauseButton = [[A5VMIconButton alloc] initWithFrame:CGRectZero];
    _pauseButton.iconType = A5VMIconPause;
    _pauseButton.accessibilityLabel = @"Pause or resume VM";
    [_pauseButton addTarget:self action:@selector(pauseVM:)
          forControlEvents:UIControlEventTouchUpInside];
    [_controlPanel addSubview:_pauseButton];

    _keyboardButton = [[A5VMIconButton alloc] initWithFrame:CGRectZero];
    _keyboardButton.iconType = A5VMIconKeyboard;
    _keyboardButton.accessibilityLabel = @"Show keyboard";
    [_keyboardButton addTarget:self action:@selector(showKeyboard:)
          forControlEvents:UIControlEventTouchUpInside];
    [_controlPanel addSubview:_keyboardButton];

    _inputField = [[UITextField alloc] initWithFrame:CGRectZero];
    _inputField.borderStyle = UITextBorderStyleRoundedRect;
    _inputField.placeholder = @"Type command";
    _inputField.returnKeyType = UIReturnKeySend;
    _inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    _inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _inputField.delegate = self;
    _inputField.hidden = YES;
    [self.view addSubview:_inputField];

    _keyPanel = [[UIView alloc] initWithFrame:CGRectZero];
    _keyPanel.backgroundColor = [UIColor colorWithWhite:0.04f alpha:0.94f];
    _keyPanel.hidden = YES;
    [self.view addSubview:_keyPanel];
    [self addSpecialKeyButtonWithTitle:@"Esc" tag:0x1B];
    [self addSpecialKeyButtonWithTitle:@"Tab" tag:0x09];
    [self addSpecialKeyButtonWithTitle:@"←" tag:0x100 + 0x4B];
    [self addSpecialKeyButtonWithTitle:@"↑" tag:0x100 + 0x48];
    [self addSpecialKeyButtonWithTitle:@"↓" tag:0x100 + 0x50];
    [self addSpecialKeyButtonWithTitle:@"→" tag:0x100 + 0x4D];
    [self addSpecialKeyButtonWithTitle:@"⌫" tag:0x08];
    [self addSpecialKeyButtonWithTitle:@"Enter" tag:0x0D];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardFrameChanged:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];

    _controlsVisible = YES;
    _keyboardVisible = NO;
    _poweredOn = YES;
    [self layoutOverlayControls];
    [self setControlsVisible:NO animated:NO];

    [self resetVM:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutOverlayControls];
}

- (void)layoutOverlayControls {
    CGRect bounds = self.view.bounds;
    CGFloat keyboardTop = _keyboardTop > 0.0f ? _keyboardTop : bounds.size.height;
    _controlPanel.frame = CGRectMake(6.0f, 6.0f, bounds.size.width - 56.0f, 48.0f);
    _menuButton.frame = CGRectMake(bounds.size.width - 46.0f, 6.0f, 40.0f, 40.0f);
    _screenTitle.frame = CGRectMake(8.0f, 3.0f, 116.0f, 24.0f);
    _statusLabel.frame = CGRectMake(124.0f, 3.0f,
                                    _controlPanel.bounds.size.width - 132.0f, 24.0f);
    _runButton.frame = CGRectMake(4.0f, 4.0f, 40.0f, 40.0f);
    _resetButton.frame = CGRectMake(48.0f, 4.0f, 40.0f, 40.0f);
    _powerButton.frame = CGRectMake(92.0f, 4.0f, 40.0f, 40.0f);
    _pauseButton.frame = CGRectMake(136.0f, 4.0f, 40.0f, 40.0f);
    _keyboardButton.frame = CGRectMake(180.0f, 4.0f, 40.0f, 40.0f);
    _keyPanel.frame = CGRectMake(6.0f, keyboardTop - 42.0f,
                                 bounds.size.width - 12.0f, 36.0f);
    CGFloat keyWidth = floorf((_keyPanel.bounds.size.width - 27.0f) / 8.0f);
    for (NSUInteger index = 0; index < [_keyPanel.subviews count]; ++index) {
        UIView *key = [_keyPanel.subviews objectAtIndex:index];
        key.frame = CGRectMake(3.0f + index * (keyWidth + 3.0f),
                               1.0f, keyWidth, 34.0f);
    }
    _inputField.frame = CGRectMake(8.0f, keyboardTop - 80.0f,
                                   bounds.size.width - 16.0f, 34.0f);
}

- (void)setControlsVisible:(BOOL)visible animated:(BOOL)animated {
    _controlsVisible = visible;
    _controlPanel.hidden = !visible;
    _menuButton.iconType = visible ? A5VMIconArrowLeft : A5VMIconArrowRight;
    _menuButton.accessibilityLabel = visible ? @"Hide VM controls" : @"Show VM controls";
    if (animated) {
        _menuButton.alpha = 0.0f;
        [UIView beginAnimations:nil context:nil];
        [UIView setAnimationDuration:0.20f];
        _menuButton.alpha = 1.0f;
        [UIView commitAnimations];
    }
}

- (void)toggleControls:(id)sender {
    (void)sender;
    [self setControlsVisible:!_controlsVisible animated:YES];
}

- (void)showKeyboard:(id)sender {
    (void)sender;
    _keyboardVisible = !_keyboardVisible;
    _inputField.hidden = !_keyboardVisible;
    _keyPanel.hidden = !_keyboardVisible;
    if (!_keyboardVisible) _keyboardTop = 0.0f;
    [self layoutOverlayControls];
    _keyboardButton.accessibilityValue = _keyboardVisible ? @"Keyboard visible" : @"Keyboard hidden";
    if (_keyboardVisible) [_inputField becomeFirstResponder];
    else [_inputField resignFirstResponder];
}

- (void)powerVM:(id)sender {
    (void)sender;
    if (_poweredOn) {
        [self stopRunner];
        if (_runtime) a5vm_machine_reset(_runtime);
        _poweredOn = NO;
        _keyboardVisible = NO;
        _inputField.hidden = YES;
        [_inputField resignFirstResponder];
        _powerButton.accessibilityValue = @"Off";
        _statusLabel.text = @"Off";
        [self renderVGA];
    } else {
        _poweredOn = YES;
        _powerButton.accessibilityValue = @"On";
        [self resetVM:nil];
    }
}

- (void)pauseVM:(id)sender {
    (void)sender;
    if (!_isRunning) return;
    if (_isPaused) {
        _isPaused = NO;
        _pauseButton.accessibilityValue = @"Running";
        _statusLabel.text = @"Running";
        _runTimer = [NSTimer scheduledTimerWithTimeInterval:0.02
                                                       target:self
                                                     selector:@selector(runSlice:)
                                                     userInfo:nil
                                                      repeats:YES];
    } else {
        _isPaused = YES;
        _pauseButton.accessibilityValue = @"Paused";
        _statusLabel.text = @"Paused";
        [_runTimer invalidate];
        [_runTimer release];
        _runTimer = nil;
    }
}

- (void)stopRunner {
    [_runTimer invalidate];
    [_runTimer release];
    _runTimer = nil;
    _isRunning = NO;
    _isPaused = NO;
    _pauseButton.accessibilityValue = @"Ready";
}

- (void)finishRunWithStatus:(a5vm_cpu_status)status {
    if (!_isRunning) return;
    [self stopRunner];
    [self writeLine:status == A5VM_CPU_HALTED ? @"Boot sector halted." : @"Boot failed."];
    if (_is386) {
        [self writeLine:[NSString stringWithFormat:@"EAX=%08X  EIP=%08X",
                         _runtime->cpu386.regs[A5VM_CPU386_REG_EAX],
                         _runtime->cpu386.eip]];
    } else {
        [self writeLine:[NSString stringWithFormat:@"AX=%04X  BX=%04X  IP=%04X",
                         _runtime->cpu.regs[A5VM_REG_AX],
                         _runtime->cpu.regs[A5VM_REG_BX],
                         _runtime->cpu.ip]];
    }
    if (status != A5VM_CPU_HALTED) {
        const char *fault = _is386 ? a5vm_cpu386_fault(&_runtime->cpu386) :
            a5vm_cpu8086_fault(&_runtime->cpu);
        [self writeLine:[NSString stringWithFormat:@"FAULT: %s", fault]];
    }
    a5vm_vga_text_write(&_runtime->vga, "A:\\>");
    [self renderVGA];
    _statusLabel.text = status == A5VM_CPU_HALTED ? @"Halted" : @"Fault";
}

- (void)runSlice:(NSTimer *)timer {
    a5vm_cpu_status status;
    (void)timer;
    if (!_isRunning || _isPaused || !_runtime) return;
    status = _is386 ? a5vm_machine_run386(_runtime, 250) :
        a5vm_machine_run(_runtime, 250);
    [self renderVGA];
    if (status != A5VM_CPU_RUNNING) [self finishRunWithStatus:status];
}

- (NSString *)diskImagePath {
    NSArray *directories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                NSUserDomainMask, YES);
    NSString *documents = [directories objectAtIndex:0];
    NSString *filename = [_machine objectForKey:@"diskImage"];
    if ([filename length] == 0) filename = @"a5vm-demo.dsk";
    return [documents stringByAppendingPathComponent:filename];
}

- (NSString *)bootImagePath {
    NSString *mediaPath = [_machine objectForKey:@"mediaPath"];
    NSString *extension = [[mediaPath pathExtension] lowercaseString];
    BOOL floppyImage = [extension isEqualToString:@"img"] ||
        [extension isEqualToString:@"ima"] || [extension isEqualToString:@"dsk"];
    if (!floppyImage || [mediaPath length] == 0) return [self diskImagePath];
    if ([mediaPath hasPrefix:@"/"]) return mediaPath;
    NSArray *directories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                NSUserDomainMask, YES);
    return [[directories objectAtIndex:0] stringByAppendingPathComponent:mediaPath];
}

- (void)loadDiskImage {
    NSData *image = [NSData dataWithContentsOfFile:[self bootImagePath]];
    if (image && [image length] <= _runtime->floppy.size) {
        memcpy(_runtime->floppy.bytes, [image bytes], [image length]);
    } else {
        [self saveDiskImage];
    }
}

- (void)loadHardDiskImage {
    NSString *diskPath = [self diskImagePath];
    NSString *bootPath = [self bootImagePath];
    if ([diskPath isEqualToString:bootPath]) return;
    _hasSeparateHardDisk = YES;

    NSData *image = [NSData dataWithContentsOfFile:diskPath];
    if (image && [image length] <= _runtime->disk.size) {
        memcpy(_runtime->disk.bytes, [image bytes], [image length]);
    }
}

- (void)saveDiskImage {
    if (!_runtime || !_runtime->floppy.bytes) return;
    NSData *image = [NSData dataWithBytes:_runtime->floppy.bytes
                                   length:_runtime->floppy.size];
    [image writeToFile:[self bootImagePath] atomically:YES];
}

- (void)saveHardDiskImage {
    if (!_hasSeparateHardDisk || !_runtime || !_runtime->disk.bytes) return;
    NSData *image = [NSData dataWithBytes:_runtime->disk.bytes
                                   length:_runtime->disk.size];
    [image writeToFile:[self diskImagePath] atomically:YES];
}

- (void)renderVGA {
    [_displayView setTextBuffer:a5vm_vga_text_cells(&_runtime->vga)];
}

- (void)writeLine:(NSString *)line {
    a5vm_vga_text_write(&_runtime->vga, [line UTF8String]);
    a5vm_vga_text_putc(&_runtime->vga, '\n');
}

- (void)runDemo:(id)sender {
    (void)sender;
    a5vm_cpu_status status;
    if (!_runtime || !_poweredOn) return;
    if (_isRunning) {
        if (_isPaused) [self pauseVM:nil];
        return;
    }
    _is386 = [[[_machine objectForKey:@"architecture"]
               lowercaseString] rangeOfString:@"i386"].location != NSNotFound;
    status = _is386 ? a5vm_machine_prepare_boot386(_runtime) :
        a5vm_machine_prepare_boot(_runtime);
    if (status != A5VM_CPU_RUNNING) {
        _isRunning = YES;
        [self writeLine:@"Boot failed."];
        [self finishRunWithStatus:status];
        return;
    }
    [self writeLine:@"A5VM BIOS 0.1"];
    [self writeLine:[NSString stringWithFormat:@"%@ / %@ / %@",
                     [_machine objectForKey:@"architecture"],
                     [_machine objectForKey:@"ram"],
                     [_machine objectForKey:@"display"]]];
    [self writeLine:@"VGA TEXT 80x25  KEYBOARD READY"];
    [self writeLine:@" "];
    [self writeLine:@"Booting sector 0 from virtual floppy..."];
    [self renderVGA];
    _isRunning = YES;
    _isPaused = NO;
    _pauseButton.accessibilityValue = @"Running";
    _statusLabel.text = @"Running";
    _runTimer = [NSTimer scheduledTimerWithTimeInterval:0.02
                                                   target:self
                                                 selector:@selector(runSlice:)
                                                 userInfo:nil
                                                  repeats:YES];
    [self runSlice:_runTimer];
}

- (void)resetVM:(id)sender {
    (void)sender;
    if (!_runtime) return;
    [self stopRunner];
    _poweredOn = YES;
    _powerButton.accessibilityValue = @"On";
    a5vm_machine_reset(_runtime);
    BOOL is386 = [[[_machine objectForKey:@"architecture"]
                   lowercaseString] rangeOfString:@"i386"].location != NSNotFound;
    a5vm_vga_text_write(&_runtime->vga, is386 ? "A5VM BIOS 0.1\ni386 PC READY\n\nA:\\>" :
                        "A5VM BIOS 0.1\n8086 PC READY\n\nA:\\>");
    [self renderVGA];
    _statusLabel.text = @"Ready";
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (!_runtime) return YES;
    NSString *command = textField.text;
    const char *bytes = [command UTF8String];
    while (*bytes != '\0') {
        if (a5vm_keyboard_push(&_runtime->keyboard, (uint8_t)*bytes)) {
            a5vm_vga_text_putc(&_runtime->vga, (uint8_t)*bytes);
        }
        bytes++;
    }
    [self queueKeyboardByte:0x0D];
    a5vm_vga_text_putc(&_runtime->vga, '\n');
    a5vm_vga_text_write(&_runtime->vga, "A:\\>");
    [self renderVGA];
    _statusLabel.text = [NSString stringWithFormat:@"Input queued (%u)", _runtime->keyboard.count];
    textField.text = @"";
    [textField resignFirstResponder];
    return YES;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return interfaceOrientation == UIInterfaceOrientationPortrait ||
           interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown ||
           interfaceOrientation == UIInterfaceOrientationLandscapeLeft ||
           interfaceOrientation == UIInterfaceOrientationLandscapeRight;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait |
           UIInterfaceOrientationMaskLandscapeLeft |
           UIInterfaceOrientationMaskLandscapeRight;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopRunner];
    [self saveDiskImage];
    [self saveHardDiskImage];
    [_machine release];
    [_machineName release];
    [_screenTitle release];
    [_displayView release];
    [_statusLabel release];
    [_runButton release];
    [_resetButton release];
    [_powerButton release];
    [_pauseButton release];
    [_keyboardButton release];
    [_menuButton release];
    [_controlPanel release];
    [_keyPanel release];
    [_inputField release];
    if (_runtime) {
        a5vm_machine_deinit(_runtime);
        free(_runtime);
    }
    [super dealloc];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopRunner];
    [self saveDiskImage];
    [self saveHardDiskImage];
    [[UIApplication sharedApplication] setStatusBarHidden:NO
                                             withAnimation:UIStatusBarAnimationNone];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

@end

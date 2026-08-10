#import "A5VMViewController.h"
#import "A5VMDisplayView.h"

#include <stdlib.h>
#include <string.h>

@implementation A5VMViewController

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
    [_controlPanel addSubview:_screenTitle];
    [_controlPanel addSubview:_statusLabel];
    [self.view addSubview:_controlPanel];

    _menuButton = [[UIButton buttonWithType:UIButtonTypeRoundedRect] retain];
    _menuButton.frame = CGRectMake(bounds.size.width - 48.0f, 6.0f, 42.0f, 48.0f);
    [_menuButton setTitle:@"›" forState:UIControlStateNormal];
    _menuButton.titleLabel.font = [UIFont boldSystemFontOfSize:32.0f];
    [_menuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _menuButton.backgroundColor = [UIColor colorWithWhite:0.05f alpha:0.92f];
    [_menuButton addTarget:self action:@selector(toggleControls:)
          forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_menuButton];

    _displayView = [[A5VMDisplayView alloc] initWithFrame:bounds];
    _displayView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:_displayView atIndex:0];

    _runButton = [[UIButton buttonWithType:UIButtonTypeRoundedRect] retain];
    [_runButton setTitle:@"Run" forState:UIControlStateNormal];
    [_runButton addTarget:self action:@selector(runDemo:)
          forControlEvents:UIControlEventTouchUpInside];
    [_controlPanel addSubview:_runButton];

    _resetButton = [[UIButton buttonWithType:UIButtonTypeRoundedRect] retain];
    [_resetButton setTitle:@"Reset" forState:UIControlStateNormal];
    [_resetButton addTarget:self action:@selector(resetVM:)
          forControlEvents:UIControlEventTouchUpInside];
    [_controlPanel addSubview:_resetButton];

    _pauseButton = [[UIButton buttonWithType:UIButtonTypeRoundedRect] retain];
    [_pauseButton setTitle:@"Pause" forState:UIControlStateNormal];
    [_pauseButton addTarget:self action:@selector(pauseVM:)
          forControlEvents:UIControlEventTouchUpInside];
    [_controlPanel addSubview:_pauseButton];

    _keyboardButton = [[UIButton buttonWithType:UIButtonTypeRoundedRect] retain];
    [_keyboardButton setTitle:@"Keyboard" forState:UIControlStateNormal];
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

    _controlsVisible = YES;
    _keyboardVisible = NO;
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
    _controlPanel.frame = CGRectMake(6.0f, 6.0f, bounds.size.width - 56.0f, 48.0f);
    _menuButton.frame = CGRectMake(bounds.size.width - 48.0f, 6.0f, 42.0f, 48.0f);
    _screenTitle.frame = CGRectMake(8.0f, 3.0f, 116.0f, 24.0f);
    _statusLabel.frame = CGRectMake(124.0f, 3.0f,
                                    _controlPanel.bounds.size.width - 132.0f, 24.0f);
    _runButton.frame = CGRectMake(6.0f, 25.0f, 52.0f, 22.0f);
    _resetButton.frame = CGRectMake(62.0f, 25.0f, 58.0f, 22.0f);
    _pauseButton.frame = CGRectMake(124.0f, 25.0f, 58.0f, 22.0f);
    _keyboardButton.frame = CGRectMake(186.0f, 25.0f,
                                       _controlPanel.bounds.size.width - 192.0f, 22.0f);
    _inputField.frame = CGRectMake(8.0f, bounds.size.height - 42.0f,
                                   bounds.size.width - 16.0f, 34.0f);
}

- (void)setControlsVisible:(BOOL)visible animated:(BOOL)animated {
    _controlsVisible = visible;
    _controlPanel.hidden = !visible;
    [_menuButton setTitle:visible ? @"‹" : @"›" forState:UIControlStateNormal];
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
    [_keyboardButton setTitle:_keyboardVisible ? @"Hide keyboard" : @"Keyboard"
                      forState:UIControlStateNormal];
    if (_keyboardVisible) [_inputField becomeFirstResponder];
    else [_inputField resignFirstResponder];
}

- (void)pauseVM:(id)sender {
    (void)sender;
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Pause"
                                                     message:@"The current boot runner executes a bounded boot session. Background pause will be enabled with continuous execution."
                                                    delegate:nil
                                           cancelButtonTitle:@"OK"
                                           otherButtonTitles:nil] autorelease];
    [alert show];
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

- (void)saveDiskImage {
    if (!_runtime || !_runtime->floppy.bytes) return;
    NSData *image = [NSData dataWithBytes:_runtime->floppy.bytes
                                   length:_runtime->floppy.size];
    [image writeToFile:[self bootImagePath] atomically:YES];
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
    BOOL is386;
    if (!_runtime) return;
    is386 = [[[_machine objectForKey:@"architecture"]
              lowercaseString] rangeOfString:@"i386"].location != NSNotFound;
    status = is386 ? a5vm_machine_boot386(_runtime, 1000) :
        a5vm_machine_boot(_runtime, 1000);
    [self writeLine:@"A5VM BIOS 0.1"];
    [self writeLine:[NSString stringWithFormat:@"%@ / %@ / %@",
                     [_machine objectForKey:@"architecture"],
                     [_machine objectForKey:@"ram"],
                     [_machine objectForKey:@"display"]]];
    [self writeLine:@"VGA TEXT 80x25  KEYBOARD READY"];
    [self writeLine:@" "];
    [self writeLine:@"Booting sector 0 from virtual floppy..."];
    [self writeLine:status == A5VM_CPU_HALTED ? @"Boot sector halted." : @"Boot failed."];
    if (is386) {
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
        const char *fault = is386 ? a5vm_cpu386_fault(&_runtime->cpu386) :
            a5vm_cpu8086_fault(&_runtime->cpu);
        [self writeLine:[NSString stringWithFormat:@"FAULT: %s", fault]];
    }
    a5vm_vga_text_write(&_runtime->vga, "A:\\>");
    [self renderVGA];
    _statusLabel.text = status == A5VM_CPU_HALTED ? @"Halted" : @"Fault";
}

- (void)resetVM:(id)sender {
    (void)sender;
    if (!_runtime) return;
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
    [self saveDiskImage];
    [_machine release];
    [_machineName release];
    [_screenTitle release];
    [_displayView release];
    [_statusLabel release];
    [_runButton release];
    [_resetButton release];
    [_pauseButton release];
    [_keyboardButton release];
    [_menuButton release];
    [_controlPanel release];
    [_inputField release];
    if (_runtime) {
        a5vm_machine_deinit(_runtime);
        free(_runtime);
    }
    [super dealloc];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

@end

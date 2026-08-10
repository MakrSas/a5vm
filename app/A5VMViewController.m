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

    self.title = _machineName;

    CGRect bounds = self.view.bounds;
    _screenTitle = [[UILabel alloc] initWithFrame:CGRectMake(8.0f, 5.0f,
                                                               bounds.size.width - 180.0f, 30.0f)];
    _screenTitle.textColor = [UIColor whiteColor];
    _screenTitle.backgroundColor = [UIColor clearColor];
    _screenTitle.font = [UIFont boldSystemFontOfSize:20.0f];
    NSString *architecture = [_machine objectForKey:@"architecture"];
    if ([architecture length] == 0) architecture = @"8086 PC";
    _screenTitle.text = [NSString stringWithFormat:@"A5VM  /  %@", architecture];
    [self.view addSubview:_screenTitle];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(bounds.size.width - 168.0f, 8.0f,
                                                               160.0f, 24.0f)];
    _statusLabel.text = @"Stopped";
    _statusLabel.textColor = [UIColor colorWithRed:0.45f green:1.0f blue:0.55f alpha:1.0f];
    _statusLabel.textAlignment = NSTextAlignmentRight;
    _statusLabel.backgroundColor = [UIColor clearColor];
    _statusLabel.font = [UIFont systemFontOfSize:13.0f];
    [self.view addSubview:_statusLabel];

    _displayView = [[A5VMDisplayView alloc] initWithFrame:CGRectMake(6.0f, 38.0f,
                                                                       bounds.size.width - 12.0f, 240.0f)];
    [self.view addSubview:_displayView];

    _runButton = [[UIButton buttonWithType:UIButtonTypeRoundedRect] retain];
    _runButton.frame = CGRectMake(6.0f, 284.0f, 78.0f, 30.0f);
    [_runButton setTitle:@"Run" forState:UIControlStateNormal];
    [_runButton addTarget:self action:@selector(runDemo:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_runButton];

    _resetButton = [[UIButton buttonWithType:UIButtonTypeRoundedRect] retain];
    _resetButton.frame = CGRectMake(90.0f, 284.0f, 78.0f, 30.0f);
    [_resetButton setTitle:@"Reset" forState:UIControlStateNormal];
    [_resetButton addTarget:self action:@selector(resetVM:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_resetButton];

    _inputLabel = [[UILabel alloc] initWithFrame:CGRectMake(178.0f, 286.0f, 52.0f, 26.0f)];
    _inputLabel.text = @"Input:";
    _inputLabel.textColor = [UIColor lightGrayColor];
    _inputLabel.backgroundColor = [UIColor clearColor];
    _inputLabel.font = [UIFont systemFontOfSize:12.0f];
    [self.view addSubview:_inputLabel];

    _inputField = [[UITextField alloc] initWithFrame:CGRectMake(228.0f, 284.0f,
                                                                 bounds.size.width - 234.0f, 30.0f)];
    _inputField.borderStyle = UITextBorderStyleRoundedRect;
    _inputField.placeholder = @"type command";
    _inputField.returnKeyType = UIReturnKeySend;
    _inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    _inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _inputField.delegate = self;
    [self.view addSubview:_inputField];

    [self resetVM:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat controlsY = bounds.size.height - 42.0f;
    CGFloat displayHeight = controlsY - 38.0f - 8.0f;
    if (displayHeight > 240.0f) displayHeight = 240.0f;
    if (displayHeight < 120.0f) displayHeight = 120.0f;

    _screenTitle.frame = CGRectMake(8.0f, 5.0f,
                                    bounds.size.width - 180.0f, 30.0f);
    _statusLabel.frame = CGRectMake(bounds.size.width - 168.0f, 8.0f,
                                    160.0f, 24.0f);
    _displayView.frame = CGRectMake(6.0f, 38.0f,
                                    bounds.size.width - 12.0f, displayHeight);
    _runButton.frame = CGRectMake(6.0f, controlsY, 78.0f, 30.0f);
    _resetButton.frame = CGRectMake(90.0f, controlsY, 78.0f, 30.0f);
    _inputLabel.frame = CGRectMake(178.0f, controlsY + 2.0f, 52.0f, 26.0f);
    _inputField.frame = CGRectMake(228.0f, controlsY,
                                   bounds.size.width - 234.0f, 30.0f);
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
    [_inputLabel release];
    [_runButton release];
    [_resetButton release];
    [_inputField release];
    if (_runtime) {
        a5vm_machine_deinit(_runtime);
        free(_runtime);
    }
    [super dealloc];
}

@end

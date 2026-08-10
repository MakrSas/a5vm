#import "A5VMViewController.h"
#import "A5VMDisplayView.h"

#include <stdlib.h>

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
                        @"Virtual floppy", @"storage",
                        nil];
        }
        _machineName = [[_machine objectForKey:@"name"] copy];
        _memory = (a5vm_memory *)calloc(1, sizeof(a5vm_memory));
        _cpu = (a5vm_cpu8086 *)calloc(1, sizeof(a5vm_cpu8086));
        _keyboard = (a5vm_keyboard *)calloc(1, sizeof(a5vm_keyboard));
        _vga = (a5vm_vga_text *)calloc(1, sizeof(a5vm_vga_text));
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
    UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(8.0f, 5.0f,
                                                                  bounds.size.width - 180.0f, 30.0f)] autorelease];
    title.text = @"A5VM  /  8086 PC";
    title.textColor = [UIColor whiteColor];
    title.backgroundColor = [UIColor clearColor];
    title.font = [UIFont boldSystemFontOfSize:20.0f];
    [self.view addSubview:title];

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

    UILabel *inputLabel = [[[UILabel alloc] initWithFrame:CGRectMake(178.0f, 286.0f, 52.0f, 26.0f)] autorelease];
    inputLabel.text = @"Input:";
    inputLabel.textColor = [UIColor lightGrayColor];
    inputLabel.backgroundColor = [UIColor clearColor];
    inputLabel.font = [UIFont systemFontOfSize:12.0f];
    [self.view addSubview:inputLabel];

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

- (void)renderVGA {
    [_displayView setTextBuffer:a5vm_vga_text_cells(_vga)];
}

- (void)writeLine:(NSString *)line {
    a5vm_vga_text_write(_vga, [line UTF8String]);
    a5vm_vga_text_putc(_vga, '\n');
}

- (void)runDemo:(id)sender {
    (void)sender;
    static const uint8_t program[] = {
        0xB8, 0x02, 0x00,       /* mov ax, 2 */
        0xBB, 0x03, 0x00,       /* mov bx, 3 */
        0x01, 0xD8,             /* add ax, bx */
        0xF4                    /* hlt */
    };

    a5vm_memory_init(_memory);
    a5vm_memory_load(_memory, 0x1000, program, sizeof(program));
    a5vm_cpu8086_init(_cpu, _memory);
    _cpu->segs[A5VM_SEG_CS] = 0;
    _cpu->ip = 0x1000;
    _cpu->regs[A5VM_REG_SP] = 0xFFFE;
    (void)a5vm_cpu8086_run(_cpu, 100);

    a5vm_vga_text_clear(_vga);
    [self writeLine:@"A5VM BIOS 0.1"];
    [self writeLine:@"8086 PC / 640 KB RAM"];
    [self writeLine:@"VGA TEXT 80x25  KEYBOARD READY"];
    [self writeLine:@" "];
    [self writeLine:@"Booting from virtual disk..."];
    [self writeLine:@"CPU halted after demo program."];
    [self writeLine:[NSString stringWithFormat:@"AX=%04X  BX=%04X  IP=%04X",
                     _cpu->regs[A5VM_REG_AX], _cpu->regs[A5VM_REG_BX], _cpu->ip]];
    a5vm_vga_text_write(_vga, "A:\\>");
    [self renderVGA];
    _statusLabel.text = @"Halted";
}

- (void)resetVM:(id)sender {
    (void)sender;
    a5vm_memory_init(_memory);
    a5vm_cpu8086_init(_cpu, _memory);
    a5vm_keyboard_init(_keyboard);
    a5vm_vga_text_init(_vga);
    a5vm_vga_text_write(_vga, "A5VM BIOS 0.1\n8086 PC READY\n\nA:\\>");
    [self renderVGA];
    _statusLabel.text = @"Ready";
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    NSString *command = textField.text;
    const char *bytes = [command UTF8String];
    while (*bytes != '\0') {
        if (a5vm_keyboard_push(_keyboard, (uint8_t)*bytes)) {
            a5vm_vga_text_putc(_vga, (uint8_t)*bytes);
        }
        bytes++;
    }
    a5vm_vga_text_putc(_vga, '\n');
    a5vm_vga_text_write(_vga, "A:\\>");
    [self renderVGA];
    _statusLabel.text = [NSString stringWithFormat:@"Input queued (%u)", _keyboard->count];
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

- (void)dealloc {
    [_machine release];
    [_machineName release];
    [_displayView release];
    [_statusLabel release];
    [_runButton release];
    [_resetButton release];
    [_inputField release];
    free(_memory);
    free(_cpu);
    free(_keyboard);
    free(_vga);
    [super dealloc];
}

@end

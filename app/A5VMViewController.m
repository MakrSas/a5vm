#import "A5VMViewController.h"
#import "A5VMDisplayView.h"

#include <stdlib.h>

@implementation A5VMViewController

- (id)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _memory = (a5vm_memory *)calloc(1, sizeof(a5vm_memory));
        _cpu = (a5vm_cpu8086 *)calloc(1, sizeof(a5vm_cpu8086));
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

    CGRect bounds = self.view.bounds;
    UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(16.0f, 18.0f,
                                                                  bounds.size.width - 32.0f, 34.0f)] autorelease];
    title.text = @"A5VM  •  iPhone 4S  •  8086 PC";
    title.textColor = [UIColor whiteColor];
    title.backgroundColor = [UIColor clearColor];
    title.font = [UIFont boldSystemFontOfSize:20.0f];
    [self.view addSubview:title];

    _displayView = [[A5VMDisplayView alloc] initWithFrame:CGRectMake(16.0f, 64.0f,
                                                                       bounds.size.width - 32.0f, 240.0f)];
    [self.view addSubview:_displayView];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16.0f, 312.0f,
                                                               bounds.size.width - 32.0f, 30.0f)];
    _statusLabel.text = @"Status: stopped";
    _statusLabel.textColor = [UIColor lightGrayColor];
    _statusLabel.backgroundColor = [UIColor clearColor];
    _statusLabel.font = [UIFont systemFontOfSize:14.0f];
    [self.view addSubview:_statusLabel];

    _runButton = [[UIButton buttonWithType:UIButtonTypeRoundedRect] retain];
    _runButton.frame = CGRectMake(16.0f, 356.0f, 140.0f, 44.0f);
    [_runButton setTitle:@"Run demo" forState:UIControlStateNormal];
    [_runButton addTarget:self action:@selector(runDemo:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_runButton];

    _resetButton = [[UIButton buttonWithType:UIButtonTypeRoundedRect] retain];
    _resetButton.frame = CGRectMake(172.0f, 356.0f, 140.0f, 44.0f);
    [_resetButton setTitle:@"Reset" forState:UIControlStateNormal];
    [_resetButton addTarget:self action:@selector(resetVM:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_resetButton];
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

    _displayView.displayText = [NSString stringWithFormat:
        @"A5VM\n\n8086 PC halted\n\nAX  = %04X\nBX  = %04X\nIP  = %04X\nSTEPS = %llu",
        _cpu->regs[A5VM_REG_AX], _cpu->regs[A5VM_REG_BX], _cpu->ip,
        (unsigned long long)_cpu->steps];
    _statusLabel.text = _cpu->status == A5VM_CPU_HALTED ?
        @"Status: halted successfully" : @"Status: fault";
}

- (void)resetVM:(id)sender {
    (void)sender;
    a5vm_memory_init(_memory);
    a5vm_cpu8086_reset(_cpu);
    _displayView.displayText = @"A5VM\n\n8086 PC is ready\nPress Run demo";
    _statusLabel.text = @"Status: reset";
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (void)dealloc {
    [_displayView release];
    [_statusLabel release];
    [_runButton release];
    [_resetButton release];
    free(_memory);
    free(_cpu);
    [super dealloc];
}

@end

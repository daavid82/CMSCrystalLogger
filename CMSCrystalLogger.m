
#import <UIKit/UIKit.h>

@interface CMSLogger : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, assign) NSInteger spinCount;
+ (instancetype)shared;
- (void)addEvent:(NSString *)event;
@end

@implementation CMSLogger

+ (instancetype)shared {
    static CMSLogger *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [CMSLogger new];
    });
    return instance;
}

- (void)addEvent:(NSString *)event {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateFormat = @"HH:mm:ss.SSS";

        NSString *time = [formatter stringFromDate:[NSDate date]];
        NSString *line = [NSString stringWithFormat:
                          @"%@  %@\n", time, event];

        self.logView.text =
            [self.logView.text stringByAppendingString:line];
    });
}

- (void)showPanel {
    UIWindowScene *scene = nil;

    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:[UIWindowScene class]] &&
            candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }

    if (!scene) return;

    self.window = [[UIWindow alloc] initWithWindowScene:scene];
    self.window.frame = CGRectMake(15, 100, 320, 270);
    self.window.windowLevel = UIWindowLevelAlert + 1;

    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor =
        [[UIColor blackColor] colorWithAlphaComponent:0.85];

    self.window.rootViewController = controller;

    UILabel *title = [[UILabel alloc]
        initWithFrame:CGRectMake(10, 5, 300, 30)];

    title.text = @"CMSCrystal Logger";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:17];
    [controller.view addSubview:title];

    self.logView = [[UITextView alloc]
        initWithFrame:CGRectMake(10, 40, 300, 170)];

    self.logView.backgroundColor = UIColor.clearColor;
    self.logView.textColor = UIColor.greenColor;
    self.logView.editable = NO;
    self.logView.font = [UIFont monospacedSystemFontOfSize:12
                                                    weight:UIFontWeightRegular];
    [controller.view addSubview:self.logView];

    UIButton *spin = [UIButton buttonWithType:UIButtonTypeSystem];
    spin.frame = CGRectMake(10, 215, 90, 40);
    [spin setTitle:@"SPIN +1" forState:UIControlStateNormal];
    [spin addTarget:self
             action:@selector(testSpin)
   forControlEvents:UIControlEventTouchUpInside];
    [controller.view addSubview:spin];

    UIButton *attack = [UIButton buttonWithType:UIButtonTypeSystem];
    attack.frame = CGRectMake(110, 215, 90, 40);
    [attack setTitle:@"ATTACK" forState:UIControlStateNormal];
    [attack addTarget:self
               action:@selector(testAttack)
     forControlEvents:UIControlEventTouchUpInside];
    [controller.view addSubview:attack];

    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    copy.frame = CGRectMake(210, 215, 90, 40);
    [copy setTitle:@"COPY" forState:UIControlStateNormal];
    [copy addTarget:self
             action:@selector(copyLog)
   forControlEvents:UIControlEventTouchUpInside];
    [controller.view addSubview:copy];

    self.window.hidden = NO;
    [self addEvent:@"Logger started (manual mode)"];
}

- (void)testSpin {
    self.spinCount++;
    [self addEvent:[NSString stringWithFormat:
        @"SPIN count=%ld", (long)self.spinCount]];
}

- (void)testAttack {
    [self addEvent:[NSString stringWithFormat:
        @"ATTACK previous=%ld", (long)self.spinCount]];
    self.spinCount = 0;
    [self addEvent:@"NEW ROUND count=0"];
}

- (void)copyLog {
    UIPasteboard.generalPasteboard.string = self.logView.text;
}

@end

__attribute__((constructor))
static void CMSLoggerInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[CMSLogger shared] showPanel];
    });
}

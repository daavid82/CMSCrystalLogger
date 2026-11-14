
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdint.h>

extern int DobbyHook(void *address, void *replace_call, void **origin_call);

__attribute__((noinline, used))
static int CMSDiagnosticTarget(int value) {
    volatile int result = value + 7;
    return result;
}

static int (*CMSOriginalTarget)(int) = NULL;
static volatile int CMSHookCalls = 0;

__attribute__((noinline))
static int CMSDiagnosticReplacement(int value) {
    CMSHookCalls++;

    if (CMSOriginalTarget) {
        return CMSOriginalTarget(value) + 100;
    }

    return -999;
}

@interface CMSLogger : NSObject

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) NSMutableArray<NSString *> *events;
@property (nonatomic, assign) NSInteger spinCount;
@property (nonatomic, assign) NSInteger totalSpins;
@property (nonatomic, assign) NSInteger attackCount;
@property (nonatomic, assign) NSInteger attempts;
@property (nonatomic, assign) BOOL hookInstalled;

+ (instancetype)shared;
- (void)start;
- (void)addEvent:(NSString *)event;

@end

@implementation CMSLogger

+ (instancetype)shared {
    static CMSLogger *logger;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        logger = [CMSLogger new];
        logger.events = [NSMutableArray new];
    });

    return logger;
}

- (void)addEvent:(NSString *)event {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateFormat = @"HH:mm:ss.SSS";

        NSString *line = [NSString stringWithFormat:
            @"%@ %@",
            [formatter stringFromDate:[NSDate date]],
            event];

        [self.events addObject:line];

        if (self.events.count > 300) {
            [self.events removeObjectAtIndex:0];
        }

        NSString *content =
            [self.events componentsJoinedByString:@"\n"];

        NSString *path =
            [NSTemporaryDirectory()
                stringByAppendingPathComponent:
                    @"CMSCrystalLogger.log"];

        [content writeToFile:path
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];

        self.logView.text = content;

        if (self.logView.text.length > 0) {
            [self.logView scrollRangeToVisible:
                NSMakeRange(self.logView.text.length - 1, 1)];
        }

        NSLog(@"[CMSCrystalLogger] %@", line);
    });
}

- (void)updateCounter {
    self.counterLabel.text = [NSString stringWithFormat:
        @"SPIN: %ld  TOTAL: %ld  ATTACK: %ld",
        (long)self.spinCount,
        (long)self.totalSpins,
        (long)self.attackCount];
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self addEvent:@"LOGGER V5 INITIALIZED"];
        [self addEvent:@"MODE: DOBBY SELF TEST"];
        [self tryShowPanel];
    });
}

- (void)runDiagnostics {
    [self addEvent:@"DIAGNOSTICS START"];

    BOOL foundUnity = NO;

    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);

        if (!name) continue;

        NSString *imageName =
            [NSString stringWithUTF8String:name];

        if ([imageName containsString:@"UnityFramework"]) {
            foundUnity = YES;

            const struct mach_header *header =
                _dyld_get_image_header(i);

            intptr_t slide =
                _dyld_get_image_vmaddr_slide(i);

            [self addEvent:@"UNITYFRAMEWORK FOUND"];

            [self addEvent:[NSString stringWithFormat:
                @"IMAGE HEADER: %p", (void *)header]];

            [self addEvent:[NSString stringWithFormat:
                @"ASLR SLIDE: 0x%llx",
                (unsigned long long)(uint64_t)slide]];
        }
    }

    if (!foundUnity) {
        [self addEvent:@"UNITYFRAMEWORK NOT FOUND"];
    }

    [self addEvent:@"DOBBY: STATIC LINK TEST AVAILABLE"];
    [self addEvent:@"PRESS DOBBY TEST"];
    [self addEvent:@"DIAGNOSTICS COMPLETE"];
}

- (void)testDobby {
    [self addEvent:@"DOBBY SELF TEST START"];

    if (self.hookInstalled) {
        int result = CMSDiagnosticTarget(5);

        [self addEvent:[NSString stringWithFormat:
            @"RETEST RESULT: %d", result]];

        [self addEvent:[NSString stringWithFormat:
            @"HOOK CALLS: %d", CMSHookCalls]];

        return;
    }

    int before = CMSDiagnosticTarget(5);

    [self addEvent:[NSString stringWithFormat:
        @"BEFORE HOOK: %d", before]];

    int status = DobbyHook(
        (void *)&CMSDiagnosticTarget,
        (void *)&CMSDiagnosticReplacement,
        (void **)&CMSOriginalTarget
    );

    [self addEvent:[NSString stringWithFormat:
        @"DOBBY STATUS: %d", status]];

    if (status != 0) {
        [self addEvent:@"DOBBY HOOK FAILED"];
        return;
    }

    self.hookInstalled = YES;

    int after = CMSDiagnosticTarget(5);

    [self addEvent:[NSString stringWithFormat:
        @"AFTER HOOK: %d", after]];

    [self addEvent:[NSString stringWithFormat:
        @"HOOK CALLS: %d", CMSHookCalls]];

    if (before == 12 && after == 112 && CMSHookCalls > 0) {
        [self addEvent:@"DOBBY SELF TEST PASSED"];
    } else {
        [self addEvent:@"DOBBY SELF TEST INCONCLUSIVE"];
    }
}

- (void)tryShowPanel {
    if (self.window) return;

    self.attempts++;

    UIWindowScene *activeScene = nil;

    for (UIScene *scene in
         UIApplication.sharedApplication.connectedScenes) {

        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState ==
                UISceneActivationStateForegroundActive) {

            activeScene = (UIWindowScene *)scene;
            break;
        }
    }

    if (!activeScene) {
        if (self.attempts < 60) {
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)NSEC_PER_SEC),
                dispatch_get_main_queue(), ^{
                    [self tryShowPanel];
                });
        } else {
            [self addEvent:@"WINDOW NOT FOUND"];
        }
        return;
    }

    [self createPanelInScene:activeScene];
}

- (void)createPanelInScene:(UIWindowScene *)scene {
    CGRect screen = scene.coordinateSpace.bounds;

    CGFloat width = MIN(330, screen.size.width - 24);
    CGFloat height = 280;

    self.window =
        [[UIWindow alloc] initWithWindowScene:scene];

    self.window.frame = CGRectMake(12, 90, width, height);
    self.window.windowLevel = UIWindowLevelAlert + 1;

    UIViewController *controller = [UIViewController new];

    controller.view.backgroundColor =
        [UIColor colorWithRed:0.07
                       green:0.09
                        blue:0.13
                       alpha:0.94];

    controller.view.layer.cornerRadius = 14;
    controller.view.clipsToBounds = YES;

    self.window.rootViewController = controller;

    UILabel *title = [[UILabel alloc]
        initWithFrame:CGRectMake(12, 8, width - 24, 28)];

    title.text = @"CMSCrystalLogger v5";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:16];
    title.userInteractionEnabled = YES;

    [controller.view addSubview:title];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(movePanel:)];

    [title addGestureRecognizer:pan];

    self.counterLabel = [[UILabel alloc]
        initWithFrame:CGRectMake(12, 38, width - 24, 24)];

    self.counterLabel.textColor = UIColor.whiteColor;
    self.counterLabel.font =
        [UIFont monospacedSystemFontOfSize:12
                                   weight:UIFontWeightBold];

    [controller.view addSubview:self.counterLabel];
    [self updateCounter];

    self.logView = [[UITextView alloc]
        initWithFrame:CGRectMake(10, 68, width - 20, 145)];

    self.logView.backgroundColor = UIColor.clearColor;
    self.logView.textColor = UIColor.greenColor;
    self.logView.font =
        [UIFont monospacedSystemFontOfSize:11
                                   weight:UIFontWeightRegular];

    self.logView.editable = NO;
    self.logView.text =
        [self.events componentsJoinedByString:@"\n"];

    [controller.view addSubview:self.logView];

    NSArray *titles =
        @[@"DIAGNOSE", @"DOBBY TEST", @"COPY"];

    SEL actions[] = {
        @selector(runDiagnostics),
        @selector(testDobby),
        @selector(copyLog)
    };

    CGFloat buttonWidth = (width - 48) / 3.0;

    for (NSInteger i = 0; i < 3; i++) {
        UIButton *button =
            [UIButton buttonWithType:UIButtonTypeSystem];

        button.frame = CGRectMake(
            12 + i * (buttonWidth + 6),
            224, buttonWidth, 42);

        [button setTitle:titles[i]
               forState:UIControlStateNormal];

        [button setTitleColor:UIColor.whiteColor
                    forState:UIControlStateNormal];

        button.backgroundColor =
            [UIColor colorWithWhite:0.22 alpha:1];

        button.layer.cornerRadius = 8;

        [button addTarget:self
                   action:actions[i]
         forControlEvents:UIControlEventTouchUpInside];

        [controller.view addSubview:button];
    }

    self.window.hidden = NO;
    [self.window makeKeyAndVisible];

    [self addEvent:@"PANEL VISIBLE"];
    [self runDiagnostics];
}

- (void)movePanel:(UIPanGestureRecognizer *)gesture {
    CGPoint translation =
        [gesture translationInView:self.window];

    CGRect frame = self.window.frame;

    frame.origin.x += translation.x;
    frame.origin.y += translation.y;

    self.window.frame = frame;

    [gesture setTranslation:CGPointZero
                    inView:self.window];
}

- (void)copyLog {
    UIPasteboard.generalPasteboard.string =
        [self.events componentsJoinedByString:@"\n"];

    [self addEvent:@"LOG COPIED"];
}

@end

__attribute__((constructor))
static void CMSLoggerInitialize(void) {
    NSLog(@"[CMSCrystalLogger] DYLIB LOADED");

    dispatch_async(dispatch_get_main_queue(), ^{
        [[CMSLogger shared] start];
    });
}

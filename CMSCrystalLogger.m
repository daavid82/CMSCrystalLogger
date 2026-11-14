
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

@interface CMSLogger : NSObject

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) NSMutableArray<NSString *> *events;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *history;
@property (nonatomic, strong) NSMutableArray<NSString *> *targets;
@property (nonatomic, assign) NSInteger spinCount;
@property (nonatomic, assign) NSInteger totalSpins;
@property (nonatomic, assign) NSInteger attackCount;
@property (nonatomic, assign) NSInteger attempts;

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
        logger.history = [NSMutableArray new];
        logger.targets = [NSMutableArray new];
    });
    return logger;
}

- (NSString *)logPath {
    return [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"CMSCrystalLogger.log"];
}

- (void)addEvent:(NSString *)event {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateFormat = @"HH:mm:ss.SSS";

        NSString *line = [NSString stringWithFormat:@"%@ %@",
            [formatter stringFromDate:[NSDate date]], event];

        [self.events addObject:line];

        NSString *content =
            [self.events componentsJoinedByString:@"\n"];

        [content writeToFile:[self logPath]
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
        @"SPIN: %ld   TOTAL: %ld   ATTACK: %ld",
        (long)self.spinCount,
        (long)self.totalSpins,
        (long)self.attackCount];
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self addEvent:@"LOGGER V3 INITIALIZED"];
        [self addEvent:@"MODE: MANUAL DIAGNOSTIC"];
        [self tryShowPanel];
    });
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
                    (int64_t)(NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    [self tryShowPanel];
                });
        } else {
            [self addEvent:@"ERROR WINDOW NOT FOUND"];
        }
        return;
    }

    [self addEvent:@"ACTIVE WINDOW SCENE FOUND"];
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
        [UIColor colorWithRed:0.07 green:0.09
                        blue:0.13 alpha:0.94];

    controller.view.layer.cornerRadius = 14;
    controller.view.clipsToBounds = YES;

    self.window.rootViewController = controller;

    UILabel *title = [[UILabel alloc]
        initWithFrame:CGRectMake(12, 8, width - 24, 26)];

    title.text = @"CMSCrystalLogger v3";
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

    NSArray *titles = @[@"SPIN +1", @"ATTACK", @"COPY"];
    SEL actions[] = {
        @selector(testSpin),
        @selector(testAttack),
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

        [button addTarget:self action:actions[i]
         forControlEvents:UIControlEventTouchUpInside];

        [controller.view addSubview:button];
    }

    self.window.hidden = NO;
    [self.window makeKeyAndVisible];

    [self addEvent:@"PANEL VISIBLE"];
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

- (void)testSpin {
    self.spinCount++;
    self.totalSpins++;

    [self updateCounter];

    [self addEvent:[NSString stringWithFormat:
        @"TEST SPIN round=%ld total=%ld",
        (long)self.spinCount,
        (long)self.totalSpins]];
}

- (void)testAttack {
    [self.history addObject:@(self.spinCount)];
    self.attackCount++;

    [self addEvent:[NSString stringWithFormat:
        @"TEST ATTACK history=%ld attack=%ld",
        (long)self.spinCount,
        (long)self.attackCount]];

    self.spinCount = 0;
    [self updateCounter];
    [self addEvent:@"NEW ROUND count=0"];
}

- (void)copyLog {
    NSString *content =
        [self.events componentsJoinedByString:@"\n"];

    UIPasteboard.generalPasteboard.string = content;
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

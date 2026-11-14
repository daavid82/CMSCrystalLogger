
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface CMSLogger : NSObject

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) NSMutableArray<NSString *> *events;
@property (nonatomic, assign) NSInteger spinCount;
@property (nonatomic, assign) NSInteger attempts;

+ (instancetype)shared;
- (void)start;
- (void)addEvent:(NSString *)event;

@end

@implementation CMSLogger

+ (instancetype)shared {
    static CMSLogger *logger;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        logger = [CMSLogger new];
        logger.events = [NSMutableArray new];
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

        NSString *line = [NSString stringWithFormat:
            @"%@ %@",
            [formatter stringFromDate:[NSDate date]],
            event
        ];

        [self.events addObject:line];

        NSString *content =
            [self.events componentsJoinedByString:@"\n"];

        [content writeToFile:[self logPath]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];

        if (self.logView) {
            self.logView.text = content;
        }

        NSLog(@"[CMSCrystalLogger] %@", line);
    });
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self addEvent:@"LOGGER INITIALIZED"];
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
        [self addEvent:[NSString stringWithFormat:
            @"WAITING FOR WINDOW attempt=%ld",
            (long)self.attempts]];

        if (self.attempts < 60) {
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                              (int64_t)(1 * NSEC_PER_SEC)),
                dispatch_get_main_queue(),
                ^{
                    [self tryShowPanel];
                }
            );
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

    CGFloat width = MIN(310, screen.size.width - 24);
    CGFloat height = 240;

    self.window =
        [[UIWindow alloc] initWithWindowScene:scene];

    self.window.frame =
        CGRectMake(12, 90, width, height);

    self.window.windowLevel = UIWindowLevelAlert + 1;

    UIViewController *controller =
        [UIViewController new];

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

    title.text = @"CMSCrystalLogger v2";
    title.textColor = UIColor.whiteColor;
    title.font =
        [UIFont boldSystemFontOfSize:16];

    [controller.view addSubview:title];

    self.logView = [[UITextView alloc]
        initWithFrame:CGRectMake(10, 42,
                                width - 20, 140)];

    self.logView.backgroundColor =
        UIColor.clearColor;

    self.logView.textColor =
        UIColor.greenColor;

    self.logView.font =
        [UIFont monospacedSystemFontOfSize:11
                                   weight:UIFontWeightRegular];

    self.logView.editable = NO;

    self.logView.text =
        [self.events componentsJoinedByString:@"\n"];

    [controller.view addSubview:self.logView];

    NSArray *titles =
        @[@"SPIN +1", @"ATTACK", @"COPY"];

    SEL actions[] = {
        @selector(testSpin),
        @selector(testAttack),
        @selector(copyLog)
    };

    CGFloat buttonWidth = (width - 32) / 3.0;

    for (NSInteger i = 0; i < 3; i++) {

        UIButton *button =
            [UIButton buttonWithType:UIButtonTypeSystem];

        button.frame =
            CGRectMake(8 + i * (buttonWidth + 8),
                       190, buttonWidth, 38);

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

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(movePanel:)];

    [title addGestureRecognizer:pan];
    title.userInteractionEnabled = YES;

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

    [self addEvent:[NSString stringWithFormat:
        @"SPIN count=%ld",
        (long)self.spinCount]];
}

- (void)testAttack {
    [self addEvent:[NSString stringWithFormat:
        @"ATTACK history=%ld",
        (long)self.spinCount]];

    self.spinCount = 0;

    [self addEvent:@"NEW ROUND count=0"];
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

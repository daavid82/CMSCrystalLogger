
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <mach-o/dyld.h>

@interface CMSLogger : NSObject

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) UILabel *raidLabel;
@property (nonatomic, strong) NSMutableArray<NSString *> *events;

@property (nonatomic, strong) UIImage *lastImage;
@property (nonatomic, strong) UIView *imageOverlay;

@property (nonatomic, assign) NSInteger spins;
@property (nonatomic, assign) NSInteger attacks;
@property (nonatomic, assign) NSInteger raids;
@property (nonatomic, assign) NSInteger symbols;
@property (nonatomic, assign) NSInteger raidStack;
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

        if (self.logView) {
            self.logView.text = content;

            if (content.length > 0) {
                [self.logView scrollRangeToVisible:
                    NSMakeRange(content.length - 1, 1)];
            }
        }

        NSLog(@"[CMSCrystalLogger] %@", line);
    });
}

- (void)updateCounters {
    self.counterLabel.text = [NSString stringWithFormat:
        @"SPIN: %ld  ATTACK: %ld  RAID: %ld",
        (long)self.spins,
        (long)self.attacks,
        (long)self.raids];

    self.raidLabel.text = [NSString stringWithFormat:
        @"STACK: %ld  SYMBOLS: %ld",
        (long)self.raidStack,
        (long)self.symbols];
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self addEvent:@"CMSCRYSTALLOGGER V8"];
        [self addEvent:@"SCREEN VIEWER MODE"];
        [self addEvent:@"NO DOBBY HOOKS"];
        [self tryShowPanel];
    });
}

- (void)runDiagnostics {
    [self addEvent:@"DIAGNOSTICS START"];

    BOOL foundUnity = NO;

    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);

        if (!name) continue;

        NSString *imageName =
            [NSString stringWithUTF8String:name];

        if ([imageName containsString:@"UnityFramework"]) {
            foundUnity = YES;

            [self addEvent:@"UNITYFRAMEWORK FOUND"];

            [self addEvent:[NSString stringWithFormat:
                @"ASLR SLIDE: 0x%llx",
                (unsigned long long)(uint64_t)
                    _dyld_get_image_vmaddr_slide(i)]];

            break;
        }
    }

    if (!foundUnity) {
        [self addEvent:@"UNITYFRAMEWORK NOT FOUND"];
    }

    [self addEvent:@"HOOKING DISABLED"];
    [self addEvent:@"DIAGNOSTICS COMPLETE"];
}

- (UIWindow *)findGameWindow {
    UIWindow *gameWindow = nil;

    for (UIScene *scene in
         UIApplication.sharedApplication.connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        for (UIWindow *candidate in windowScene.windows) {
            if (candidate == self.window) continue;
            if (candidate.hidden) continue;
            if (candidate.bounds.size.width < 100) continue;

            if (!gameWindow ||
                candidate.windowLevel < gameWindow.windowLevel) {
                gameWindow = candidate;
            }
        }
    }

    return gameWindow;
}

- (void)screenTest {
    [self addEvent:@"SCREEN TEST START"];

    UIWindow *gameWindow = [self findGameWindow];

    if (!gameWindow) {
        [self addEvent:@"GAME WINDOW NOT FOUND"];
        return;
    }

    CGSize size = gameWindow.bounds.size;

    if (size.width <= 0 || size.height <= 0) {
        [self addEvent:@"INVALID WINDOW SIZE"];
        return;
    }

    [self addEvent:[NSString stringWithFormat:
        @"GAME WINDOW: %.0f x %.0f",
        size.width, size.height]];

    UIGraphicsImageRendererFormat *format =
        [UIGraphicsImageRendererFormat defaultFormat];

    format.scale = 1.0;
    format.opaque = YES;

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc]
            initWithSize:size format:format];

    UIImage *image = [renderer imageWithActions:
        ^(UIGraphicsImageRendererContext *context) {

        [gameWindow drawViewHierarchyInRect:
            CGRectMake(0, 0, size.width, size.height)
            afterScreenUpdates:NO];
    }];

    if (!image) {
        [self addEvent:@"SCREEN TEST: IMAGE FAILED"];
        return;
    }

    NSData *data = UIImagePNGRepresentation(image);

    if (!data) {
        [self addEvent:@"SCREEN TEST: PNG FAILED"];
        return;
    }

    NSString *path =
        [NSTemporaryDirectory()
            stringByAppendingPathComponent:
                @"CMSCrystalScreenTest.png"];

    BOOL saved = [data writeToFile:path atomically:YES];

    if (!saved) {
        [self addEvent:@"SCREEN TEST: SAVE FAILED"];
        return;
    }

    self.lastImage = image;

    [self addEvent:@"SCREEN TEST: IMAGE SAVED"];

    [self addEvent:[NSString stringWithFormat:
        @"IMAGE BYTES: %lu",
        (unsigned long)data.length]];

    [self addEvent:@"PRESS VIEW IMAGE"];
}

- (void)viewImage {
    if (!self.lastImage) {
        [self addEvent:@"NO IMAGE - PRESS SCREEN TEST"];
        return;
    }

    if (self.imageOverlay) {
        [self.imageOverlay removeFromSuperview];
        self.imageOverlay = nil;
    }

    UIView *parent =
        self.window.rootViewController.view;

    UIView *overlay =
        [[UIView alloc] initWithFrame:parent.bounds];

    overlay.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    overlay.backgroundColor =
        [UIColor colorWithWhite:0.02 alpha:0.98];

    UIImageView *imageView =
        [[UIImageView alloc] initWithFrame:
            CGRectMake(8, 8,
                overlay.bounds.size.width - 16,
                overlay.bounds.size.height - 66)];

    imageView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    imageView.image = self.lastImage;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.backgroundColor = UIColor.blackColor;

    [overlay addSubview:imageView];

    UIButton *closeButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    closeButton.frame = CGRectMake(
        12,
        overlay.bounds.size.height - 50,
        overlay.bounds.size.width - 24,
        40);

    closeButton.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleTopMargin;

    [closeButton setTitle:@"CLOSE IMAGE"
                forState:UIControlStateNormal];

    [closeButton setTitleColor:UIColor.whiteColor
                     forState:UIControlStateNormal];

    closeButton.backgroundColor =
        [UIColor colorWithRed:0.24
                       green:0.29
                        blue:0.38
                       alpha:1];

    closeButton.layer.cornerRadius = 8;

    [closeButton addTarget:self
                    action:@selector(closeImage)
          forControlEvents:UIControlEventTouchUpInside];

    [overlay addSubview:closeButton];
    [parent addSubview:overlay];

    self.imageOverlay = overlay;

    [self addEvent:@"IMAGE VIEW OPENED"];
}

- (void)closeImage {
    [self.imageOverlay removeFromSuperview];
    self.imageOverlay = nil;

    [self addEvent:@"IMAGE VIEW CLOSED"];
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

- (UIButton *)makeButton:(NSString *)title
                  frame:(CGRect)frame
                 action:(SEL)action
                 parent:(UIView *)parent {

    UIButton *button =
        [UIButton buttonWithType:UIButtonTypeSystem];

    button.frame = frame;

    [button setTitle:title
           forState:UIControlStateNormal];

    [button setTitleColor:UIColor.whiteColor
                forState:UIControlStateNormal];

    button.titleLabel.font =
        [UIFont boldSystemFontOfSize:11];

    button.backgroundColor =
        [UIColor colorWithWhite:0.22 alpha:1];

    button.layer.cornerRadius = 8;

    [button addTarget:self
               action:action
     forControlEvents:UIControlEventTouchUpInside];

    [parent addSubview:button];

    return button;
}

- (void)createPanelInScene:(UIWindowScene *)scene {
    CGRect screen = scene.coordinateSpace.bounds;

    CGFloat width = MIN(350, screen.size.width - 24);
    CGFloat height = 410;

    self.window =
        [[UIWindow alloc] initWithWindowScene:scene];

    self.window.frame =
        CGRectMake(12, 70, width, height);

    self.window.windowLevel =
        UIWindowLevelAlert + 1;

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

    title.text = @"CMSCrystalLogger v8 SCREEN";
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
        [UIFont monospacedSystemFontOfSize:11
                                   weight:UIFontWeightBold];

    [controller.view addSubview:self.counterLabel];

    self.raidLabel = [[UILabel alloc]
        initWithFrame:CGRectMake(12, 62, width - 24, 24)];

    self.raidLabel.textColor = UIColor.systemGreenColor;
    self.raidLabel.font =
        [UIFont monospacedSystemFontOfSize:12
                                   weight:UIFontWeightBold];

    [controller.view addSubview:self.raidLabel];

    [self updateCounters];

    self.logView = [[UITextView alloc]
        initWithFrame:CGRectMake(10, 92, width - 20, 145)];

    self.logView.backgroundColor = UIColor.clearColor;
    self.logView.textColor = UIColor.greenColor;
    self.logView.font =
        [UIFont monospacedSystemFontOfSize:11
                                   weight:UIFontWeightRegular];

    self.logView.editable = NO;
    self.logView.text =
        [self.events componentsJoinedByString:@"\n"];

    [controller.view addSubview:self.logView];

    CGFloat gap = 6;
    CGFloat buttonWidth = (width - 36 - gap * 2) / 3;

    NSArray *titles1 =
        @[@"SPIN +1", @"ATTACK", @"RAID"];

    SEL actions1[] = {
        @selector(addSpin),
        @selector(addAttack),
        @selector(addRaid)
    };

    NSArray *titles2 =
        @[@"SYMBOL +1", @"STACK +1", @"STACK -1"];

    SEL actions2[] = {
        @selector(addSymbol),
        @selector(addStack),
        @selector(removeStack)
    };

    NSArray *titles3 =
        @[@"SCREEN TEST", @"VIEW IMAGE", @"COPY"];

    SEL actions3[] = {
        @selector(screenTest),
        @selector(viewImage),
        @selector(copyLog)
    };

    for (NSInteger i = 0; i < 3; i++) {
        CGFloat x = 12 + i * (buttonWidth + gap);

        [self makeButton:titles1[i]
                  frame:CGRectMake(x, 245, buttonWidth, 34)
                 action:actions1[i]
                 parent:controller.view];

        [self makeButton:titles2[i]
                  frame:CGRectMake(x, 285, buttonWidth, 34)
                 action:actions2[i]
                 parent:controller.view];

        [self makeButton:titles3[i]
                  frame:CGRectMake(x, 325, buttonWidth, 34)
                 action:actions3[i]
                 parent:controller.view];
    }

    [self makeButton:@"RESET COUNTERS"
              frame:CGRectMake(12, 365, width - 24, 34)
             action:@selector(resetCounters)
             parent:controller.view];

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

- (void)addSpin {
    self.spins++;
    [self updateCounters];
    [self addEvent:@"SPIN +1"];
}

- (void)addAttack {
    self.attacks++;
    [self updateCounters];
    [self addEvent:@"ATTACK +1"];
}

- (void)addRaid {
    self.raids++;
    [self updateCounters];
    [self addEvent:@"RAID +1"];
}

- (void)addSymbol {
    self.symbols++;
    [self updateCounters];
    [self addEvent:@"SYMBOL +1"];
}

- (void)addStack {
    self.raidStack++;
    [self updateCounters];
    [self addEvent:@"RAID STACK +1"];
}

- (void)removeStack {
    if (self.raidStack > 0) {
        self.raidStack--;
    }

    [self updateCounters];
    [self addEvent:@"RAID STACK -1"];
}

- (void)resetCounters {
    self.spins = 0;
    self.attacks = 0;
    self.raids = 0;
    self.symbols = 0;
    self.raidStack = 0;

    [self updateCounters];
    [self addEvent:@"COUNTERS RESET"];
}

- (void)copyLog {
    UIPasteboard.generalPasteboard.string =
        [self.events componentsJoinedByString:@"\n"];

    [self addEvent:@"LOG COPIED"];
}

@end

__attribute__((constructor))
static void CMSLoggerInitialize(void) {
    NSLog(@"[CMSCrystalLogger] V8 DYLIB LOADED");

    dispatch_async(dispatch_get_main_queue(), ^{
        [[CMSLogger shared] start];
    });
}

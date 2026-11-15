
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

#pragma mark - CMSCrystalBridge v13

@interface CMSBridgeWindow : UIWindow
@property(nonatomic, weak) UIView *panel;
@end

@implementation CMSBridgeWindow

- (UIView *)hitTest:(CGPoint)point
          withEvent:(UIEvent *)event {
    UIView *panel = self.panel;
    if (!panel || panel.hidden) return nil;

    CGPoint local =
        [panel convertPoint:point fromView:self];

    if (![panel pointInside:local withEvent:event])
        return nil;

    UIView *hit =
        [super hitTest:point withEvent:event];

    if (hit == self ||
        hit == self.rootViewController.view)
        return nil;

    return hit;
}
@end

#pragma mark - Logger helpers

static id CMSObjectGetter(id obj, NSString *name) {
    if (!obj) return nil;

    SEL sel = NSSelectorFromString(name);
    NSMethodSignature *sig =
        [obj methodSignatureForSelector:sel];

    if (!sig ||
        sig.numberOfArguments != 2 ||
        strcmp(sig.methodReturnType, "@") != 0)
        return nil;

    IMP imp = [obj methodForSelector:sel];
    if (!imp) return nil;

    id (*fn)(id, SEL) = (id (*)(id, SEL))imp;
    return fn(obj, sel);
}

static BOOL CMSIntegerGetter(
    id obj, NSString *name, long long *out) {

    if (!obj || !out) return NO;

    SEL sel = NSSelectorFromString(name);
    NSMethodSignature *sig =
        [obj methodSignatureForSelector:sel];

    if (!sig || sig.numberOfArguments != 2)
        return NO;

    const char *type = sig.methodReturnType;

    if (!type || (strcmp(type, "q") != 0 &&
                  strcmp(type, "Q") != 0))
        return NO;

    IMP imp = [obj methodForSelector:sel];
    if (!imp) return NO;

    long long (*fn)(id, SEL) =
        (long long (*)(id, SEL))imp;

    *out = fn(obj, sel);
    return YES;
}

static id CMSLogger(void) {
    Class cls = objc_getClass("CMSCrystalLogger");
    if (!cls) return nil;
    return CMSObjectGetter(cls, @"shared");
}

static NSString *CMSValue(id obj) {
    if (!obj) return @"—";

    if ([obj isKindOfClass:NSString.class])
        return (NSString *)obj;

    if ([obj isKindOfClass:NSNumber.class])
        return [(NSNumber *)obj stringValue];

    return NSStringFromClass([obj class]);
}

static NSString *CMSCounter(
    NSDictionary *dict, NSString *key) {

    if (!dict) return @"—";

    id value = dict[key];
    return value ? CMSValue(value) : @"0";
}

#pragma mark - Panel

@interface CMSBridgePanel : UIView
<UIGestureRecognizerDelegate>

@property(nonatomic,strong) UIButton *header;
@property(nonatomic,strong) UILabel *counterLabel;
@property(nonatomic,strong) UILabel *spinLabel;
@property(nonatomic,strong) UITextView *details;
@property(nonatomic,strong) UIButton *refreshButton;
@property(nonatomic,strong) UIButton *dataButton;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,copy) NSString *fullReport;
@property(nonatomic,assign) BOOL expanded;

- (void)refreshCounters;

@end

static CMSBridgeWindow *gWindow = nil;
static CMSBridgePanel *gPanel = nil;

@implementation CMSBridgePanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor =
        [[UIColor blackColor]
            colorWithAlphaComponent:0.92];

    self.layer.cornerRadius = 10;
    self.layer.borderWidth = 1;
    self.layer.borderColor =
        UIColor.cyanColor.CGColor;

    self.clipsToBounds = YES;
    self.fullReport = @"";
    self.expanded = NO;

    self.header =
        [UIButton buttonWithType:UIButtonTypeSystem];
    self.header.frame = CGRectMake(0, 0, 200, 32);

    [self.header setTitle:@"CMS v13  ▼"
                 forState:UIControlStateNormal];
    [self.header setTitleColor:UIColor.cyanColor
                     forState:UIControlStateNormal];
    self.header.titleLabel.font =
        [UIFont boldSystemFontOfSize:13];

    [self.header addTarget:self
                    action:@selector(togglePanel)
          forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.header];

    self.counterLabel =
        [[UILabel alloc]
            initWithFrame:CGRectMake(10, 36, 180, 48)];

    self.counterLabel.numberOfLines = 2;
    self.counterLabel.font =
        [UIFont monospacedSystemFontOfSize:12
                                   weight:UIFontWeightMedium];
    self.counterLabel.textColor = UIColor.whiteColor;
    self.counterLabel.text =
        @"ATTACK  —   STEAL  —\n"
         "SHIELD  —   POINT  —";
    [self addSubview:self.counterLabel];

    self.spinLabel =
        [[UILabel alloc]
            initWithFrame:CGRectMake(10, 88, 180, 22)];

    self.spinLabel.font =
        [UIFont monospacedSystemFontOfSize:10
                                   weight:UIFontWeightRegular];
    self.spinLabel.textColor = UIColor.lightGrayColor;
    self.spinLabel.text = @"Spins ~—  Rörelse —";
    [self addSubview:self.spinLabel];

    self.details =
        [[UITextView alloc]
            initWithFrame:CGRectMake(8, 116, 294, 155)];

    self.details.backgroundColor = UIColor.clearColor;
    self.details.textColor = UIColor.whiteColor;
    self.details.font =
        [UIFont monospacedSystemFontOfSize:10
                                   weight:UIFontWeightRegular];
    self.details.editable = NO;
    self.details.selectable = YES;
    self.details.hidden = YES;
    [self addSubview:self.details];

    self.refreshButton =
        [UIButton buttonWithType:UIButtonTypeSystem];
    self.refreshButton.frame =
        CGRectMake(10, 278, 282, 38);
    self.refreshButton.backgroundColor =
        [UIColor colorWithRed:0.12
                        green:0.36
                         blue:0.68
                        alpha:1];
    self.refreshButton.layer.cornerRadius = 7;
    [self.refreshButton setTitle:@"UPPDATERA"
                       forState:UIControlStateNormal];
    [self.refreshButton setTitleColor:UIColor.whiteColor
                            forState:UIControlStateNormal];
    [self.refreshButton addTarget:self
                           action:@selector(refreshCounters)
                 forControlEvents:UIControlEventTouchUpInside];
    self.refreshButton.hidden = YES;
    [self addSubview:self.refreshButton];

    self.dataButton =
        [UIButton buttonWithType:UIButtonTypeSystem];
    self.dataButton.frame =
        CGRectMake(10, 322, 282, 38);
    self.dataButton.backgroundColor =
        [UIColor colorWithRed:0.10
                        green:0.52
                         blue:0.26
                        alpha:1];
    self.dataButton.layer.cornerRadius = 7;
    [self.dataButton setTitle:@"KOPIERA ALL DATA"
                    forState:UIControlStateNormal];
    [self.dataButton setTitleColor:UIColor.whiteColor
                         forState:UIControlStateNormal];
    [self.dataButton addTarget:self
                        action:@selector(exportData)
              forControlEvents:UIControlEventTouchUpInside];
    self.dataButton.hidden = YES;
    [self addSubview:self.dataButton];

    self.statusLabel =
        [[UILabel alloc]
            initWithFrame:CGRectMake(10, 365, 282, 18)];
    self.statusLabel.font =
        [UIFont systemFontOfSize:10];
    self.statusLabel.textColor = UIColor.whiteColor;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.hidden = YES;
    [self addSubview:self.statusLabel];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(drag:)];
    pan.delegate = self;
    pan.cancelsTouchesInView = NO;
    [self addGestureRecognizer:pan];

    return self;
}

- (void)togglePanel {
    self.expanded = !self.expanded;

    CGRect frame = self.frame;
    frame.size = self.expanded
        ? CGSizeMake(302, 390)
        : CGSizeMake(200, 115);

    if (self.superview) {
        CGFloat maxX = MAX(
            0, self.superview.bounds.size.width -
            frame.size.width);
        CGFloat maxY = MAX(
            0, self.superview.bounds.size.height -
            frame.size.height);

        frame.origin.x = MAX(0, MIN(frame.origin.x, maxX));
        frame.origin.y = MAX(0, MIN(frame.origin.y, maxY));
    }

    self.frame = frame;
    self.header.frame =
        CGRectMake(0, 0, frame.size.width, 32);

    self.details.hidden = !self.expanded;
    self.refreshButton.hidden = !self.expanded;
    self.dataButton.hidden = !self.expanded;
    self.statusLabel.hidden = !self.expanded;

    [self.header setTitle:self.expanded
        ? @"CMS v13  ▲" : @"CMS v13  ▼"
                 forState:UIControlStateNormal];
}

- (void)drag:(UIPanGestureRecognizer *)gesture {
    if (!self.superview) return;

    CGPoint delta =
        [gesture translationInView:self.superview];
    CGRect frame = self.frame;

    CGFloat maxX = MAX(
        0, self.superview.bounds.size.width -
        frame.size.width);
    CGFloat maxY = MAX(
        0, self.superview.bounds.size.height -
        frame.size.height);

    frame.origin.x =
        MAX(0, MIN(frame.origin.x + delta.x, maxX));
    frame.origin.y =
        MAX(0, MIN(frame.origin.y + delta.y, maxY));

    self.frame = frame;
    [gesture setTranslation:CGPointZero
                    inView:self.superview];
}

- (BOOL)gestureRecognizerShouldBegin:
    (UIGestureRecognizer *)gestureRecognizer {

    if ([gestureRecognizer isKindOfClass:
            UIPanGestureRecognizer.class]) {
        CGPoint p =
            [gestureRecognizer locationInView:self];
        return p.y <= 32;
    }
    return YES;
}

- (void)exportData {
    if (self.fullReport.length == 0) {
        self.statusLabel.text = @"Ingen data";
        return;
    }

    [UIPasteboard generalPasteboard].string =
        self.fullReport;

    self.statusLabel.text =
        [NSString stringWithFormat:@"Kopierat: %lu tecken",
            (unsigned long)self.fullReport.length];
}

- (void)refreshCounters {

    id logger = CMSLogger();

    NSMutableString *report =
        [NSMutableString stringWithString:
            @"CMSCrystalBridge v13\n"
             "AUTO COUNTER SNAPSHOT\n\n"];

    if (!logger) {
        self.counterLabel.text =
            @"ATTACK  —   STEAL  —\n"
             "SHIELD  —   POINT  —";
        self.spinLabel.text = @"Logger saknas";

        [report appendString:
            @"LOGGER INSTANCE: NOT FOUND\n"];
    } else {
        [report appendString:
            @"LOGGER INSTANCE: FOUND\n"];

        id countsObject =
            CMSObjectGetter(logger, @"counts");
        NSDictionary *counts = nil;

        if ([countsObject
                isKindOfClass:NSDictionary.class]) {
            counts = [(NSDictionary *)countsObject copy];
        }

        NSString *attack =
            CMSCounter(counts, @"ATTACK");
        NSString *steal =
            CMSCounter(counts, @"STEAL");
        NSString *shield =
            CMSCounter(counts, @"SHIELD");
        NSString *point =
            CMSCounter(counts, @"POINT");

        self.counterLabel.text =
            [NSString stringWithFormat:
                @"ATTACK %@   STEAL %@\n"
                 "SHIELD %@   POINT %@",
                attack, steal, shield, point];

        [report appendFormat:
            @"ATTACK: %@\n"
             "STEAL: %@\n"
             "SHIELD: %@\n"
             "POINT: %@\n",
            attack, steal, shield, point];

        id lastSymbol =
            CMSObjectGetter(logger, @"lastSymbol");

        [report appendFormat:
            @"LAST SYMBOL: %@\n",
            CMSValue(lastSymbol)];

        long long estimated = 0;
        long long candidates = 0;

        BOOL hasEstimated =
            CMSIntegerGetter(
                logger, @"estimatedSpins", &estimated);

        BOOL hasCandidates =
            CMSIntegerGetter(
                logger, @"spinCandidates", &candidates);

        NSString *estimatedText = hasEstimated
            ? [NSString stringWithFormat:@"%lld", estimated]
            : @"—";

        NSString *candidatesText = hasCandidates
            ? [NSString stringWithFormat:@"%lld", candidates]
            : @"—";

        self.spinLabel.text =
            [NSString stringWithFormat:
                @"Spins ~%@  Rörelse %@",
                estimatedText, candidatesText];

        [report appendFormat:
            @"\nESTIMATED SPINS: %@\n"
             "SPIN CANDIDATES: %@\n",
            estimatedText, candidatesText];

        [report appendString:
            @"\n=== ALL COUNTS ===\n"];

        if (counts) {
            NSArray *keys = [[counts allKeys]
                sortedArrayUsingComparator:
                    ^NSComparisonResult(id a, id b) {
                        return [[a description]
                            compare:[b description]];
                    }];

            for (id key in keys) {
                [report appendFormat:@"%@: %@\n",
                    CMSValue(key),
                    CMSValue(counts[key])];
            }
        } else {
            [report appendString:
                @"COUNTS NOT AVAILABLE\n"];
        }

        id logsObject =
            CMSObjectGetter(logger, @"logs");

        [report appendString:
            @"\n=== RECENT LOGS ===\n"];

        if ([logsObject isKindOfClass:NSArray.class]) {
            NSArray *logs = [(NSArray *)logsObject copy];
            NSUInteger start =
                logs.count > 12 ? logs.count - 12 : 0;

            for (NSUInteger i = start;
                 i < logs.count; i++) {
                NSString *line = CMSValue(logs[i]);
                if (line.length > 240) {
                    line = [[line substringToIndex:240]
                        stringByAppendingString:@"..."];
                }
                [report appendFormat:@"%@\n", line];
            }
        } else {
            [report appendString:
                @"Logs unavailable\n"];
        }
    }

    [report appendString:
        @"\n=== STATUS ===\n"
         "Read-only Logger data\n"
         "Spin estimates unverified\n"
         "Motion candidates unverified\n"
         "Raid stack not verified\n"
         "AutoSpeed unchanged\n"];

    self.fullReport = [report copy];
    self.details.text = report;
    self.statusLabel.text = @"Uppdaterad";
}

@end

#pragma mark - Startup

static UIWindowScene *CMSForegroundScene(void) {
    for (UIScene *scene in
         UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] &&
            scene.activationState ==
                UISceneActivationStateForegroundActive)
            return (UIWindowScene *)scene;
    }
    return nil;
}

static void CMSSetup(void) {
    if (gPanel) return;

    UIWindowScene *scene = CMSForegroundScene();
    if (!scene) return;

    gWindow =
        [[CMSBridgeWindow alloc]
            initWithWindowScene:scene];

    gWindow.frame = scene.coordinateSpace.bounds;
    gWindow.windowLevel = UIWindowLevelAlert + 10;

    UIViewController *controller =
        [UIViewController new];
    controller.view.backgroundColor = UIColor.clearColor;
    gWindow.rootViewController = controller;

    gPanel =
        [[CMSBridgePanel alloc]
            initWithFrame:CGRectMake(12, 90, 200, 115)];

    [controller.view addSubview:gPanel];

    gWindow.panel = gPanel;
    gWindow.hidden = NO;

    [gPanel refreshCounters];

    NSTimer *timer =
        [NSTimer timerWithTimeInterval:1.0
                               repeats:YES
                                 block:^(NSTimer *t) {
        if (gPanel && !gPanel.hidden &&
            UIApplication.sharedApplication.applicationState ==
                UIApplicationStateActive) {
            [gPanel refreshCounters];
        }
    }];

    [[NSRunLoop mainRunLoop]
        addTimer:timer
        forMode:NSRunLoopCommonModes];
}

__attribute__((constructor))
static void CMSBridgeV13Start(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        const int delays[] = {3, 10, 25};

        for (unsigned i = 0; i < 3; i++) {
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)delays[i] * NSEC_PER_SEC),
                dispatch_get_main_queue(), ^{
                    CMSSetup();
                });
        }
    });
}

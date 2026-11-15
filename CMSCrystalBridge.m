
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <string.h>

#pragma mark - CMSCrystalBridge v14

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

#pragma mark - Runtime helpers

static id CMSGetObject(id object, NSString *name) {

    if (!object) return nil;

    SEL selector = NSSelectorFromString(name);

    NSMethodSignature *signature =
        [object methodSignatureForSelector:selector];

    if (!signature ||
        signature.numberOfArguments != 2 ||
        strcmp(signature.methodReturnType, "@") != 0)
        return nil;

    IMP imp = [object methodForSelector:selector];
    if (!imp) return nil;

    id (*getter)(id, SEL) =
        (id (*)(id, SEL))imp;

    return getter(object, selector);
}

static BOOL CMSGetInteger(
    id object,
    NSString *name,
    long long *output) {

    if (!object || !output) return NO;

    SEL selector = NSSelectorFromString(name);

    NSMethodSignature *signature =
        [object methodSignatureForSelector:selector];

    if (!signature ||
        signature.numberOfArguments != 2)
        return NO;

    const char *type = signature.methodReturnType;

    if (!type ||
        (strcmp(type, "q") != 0 &&
         strcmp(type, "Q") != 0))
        return NO;

    IMP imp = [object methodForSelector:selector];
    if (!imp) return NO;

    long long (*getter)(id, SEL) =
        (long long (*)(id, SEL))imp;

    *output = getter(object, selector);
    return YES;
}

static id CMSLogger(void) {

    Class cls = objc_getClass("CMSCrystalLogger");

    if (!cls) return nil;

    return CMSGetObject(cls, @"shared");
}

static NSString *CMSString(id value) {

    if (!value) return @"—";

    if ([value isKindOfClass:NSString.class])
        return (NSString *)value;

    if ([value isKindOfClass:NSNumber.class])
        return [(NSNumber *)value stringValue];

    return NSStringFromClass([value class]);
}

static NSString *CMSCountText(
    NSDictionary *counts,
    NSString *symbol) {

    if (!counts) return @"—";

    id value = counts[symbol];

    return value ? CMSString(value) : @"0";
}

static BOOL CMSCountNumber(
    NSDictionary *counts,
    NSString *symbol,
    long long *output) {

    if (!counts || !output) return NO;

    id value = counts[symbol];

    if (!value) {
        *output = 0;
        return YES;
    }

    if (![value isKindOfClass:NSNumber.class])
        return NO;

    *output = [value longLongValue];
    return YES;
}

#pragma mark - Panel interface

@interface CMSBridgePanel : UIView
<UIGestureRecognizerDelegate>

@property(nonatomic,strong) UIButton *header;
@property(nonatomic,strong) UILabel *counterLabel;
@property(nonatomic,strong) UILabel *spinLabel;
@property(nonatomic,strong) UILabel *lastLabel;
@property(nonatomic,strong) UILabel *alertLabel;

@property(nonatomic,strong) UITextView *details;
@property(nonatomic,strong) UIButton *refreshButton;
@property(nonatomic,strong) UIButton *dataButton;
@property(nonatomic,strong) UILabel *statusLabel;

@property(nonatomic,copy) NSString *fullReport;
@property(nonatomic,copy) NSString *previousSymbol;

@property(nonatomic,assign) BOOL expanded;
@property(nonatomic,assign) BOOL hasBaseline;
@property(nonatomic,assign) BOOL loggerAvailable;

@property(nonatomic,assign) long long previousAttack;
@property(nonatomic,assign) long long previousSteal;
@property(nonatomic,assign) long long previousShield;
@property(nonatomic,assign) long long previousPoint;

@property(nonatomic,assign) NSUInteger alertGeneration;

- (void)refreshCounters;
- (void)buildReport;

@end

static CMSBridgeWindow *gWindow = nil;
static CMSBridgePanel *gPanel = nil;

#pragma mark - Panel implementation

@implementation CMSBridgePanel

- (instancetype)initWithFrame:(CGRect)frame {

    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor =
        [[UIColor blackColor]
            colorWithAlphaComponent:0.93];

    self.layer.cornerRadius = 11;
    self.layer.borderWidth = 1;
    self.layer.borderColor =
        UIColor.cyanColor.CGColor;

    self.clipsToBounds = YES;

    self.expanded = NO;
    self.hasBaseline = NO;
    self.loggerAvailable = NO;
    self.fullReport = @"";
    self.previousSymbol = @"";

    self.header =
        [UIButton buttonWithType:UIButtonTypeSystem];

    self.header.frame =
        CGRectMake(0, 0, 205, 32);

    [self.header
        setTitle:@"CMS v14 ▼"
        forState:UIControlStateNormal];

    [self.header
        setTitleColor:UIColor.cyanColor
        forState:UIControlStateNormal];

    self.header.titleLabel.font =
        [UIFont boldSystemFontOfSize:13];

    [self.header
        addTarget:self
        action:@selector(togglePanel)
        forControlEvents:UIControlEventTouchUpInside];

    [self addSubview:self.header];

    self.counterLabel =
        [[UILabel alloc]
            initWithFrame:CGRectMake(10, 35, 185, 42)];

    self.counterLabel.numberOfLines = 2;
    self.counterLabel.textColor = UIColor.whiteColor;

    self.counterLabel.font =
        [UIFont monospacedSystemFontOfSize:11
                                   weight:UIFontWeightMedium];

    self.counterLabel.text =
        @"ATTACK —  STEAL —\n"
         "SHIELD —  POINT —";

    [self addSubview:self.counterLabel];

    self.spinLabel =
        [[UILabel alloc]
            initWithFrame:CGRectMake(10, 78, 185, 18)];

    self.spinLabel.font =
        [UIFont monospacedSystemFontOfSize:10
                                   weight:UIFontWeightRegular];

    self.spinLabel.textColor =
        UIColor.lightGrayColor;

    self.spinLabel.text =
        @"Spins ~—  Rörelse —";

    [self addSubview:self.spinLabel];

    self.lastLabel =
        [[UILabel alloc]
            initWithFrame:CGRectMake(10, 98, 185, 17)];

    self.lastLabel.font =
        [UIFont systemFontOfSize:10];

    self.lastLabel.textColor =
        UIColor.cyanColor;

    self.lastLabel.text =
        @"Senaste: —";

    [self addSubview:self.lastLabel];

    self.alertLabel =
        [[UILabel alloc]
            initWithFrame:CGRectMake(8, 118, 189, 20)];

    self.alertLabel.font =
        [UIFont boldSystemFontOfSize:11];

    self.alertLabel.textColor =
        UIColor.greenColor;

    self.alertLabel.textAlignment =
        NSTextAlignmentCenter;

    self.alertLabel.text = @"";
    [self addSubview:self.alertLabel];

    self.details =
        [[UITextView alloc]
            initWithFrame:CGRectMake(8, 145, 294, 160)];

    self.details.backgroundColor =
        UIColor.clearColor;

    self.details.textColor =
        UIColor.whiteColor;

    self.details.font =
        [UIFont monospacedSystemFontOfSize:10
                                   weight:UIFontWeightRegular];

    self.details.editable = NO;
    self.details.selectable = YES;
    self.details.scrollEnabled = YES;
    self.details.hidden = YES;

    [self addSubview:self.details];

    self.refreshButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    self.refreshButton.frame =
        CGRectMake(10, 312, 282, 38);

    self.refreshButton.backgroundColor =
        [UIColor colorWithRed:0.12
                        green:0.36
                         blue:0.68
                        alpha:1];

    self.refreshButton.layer.cornerRadius = 7;

    [self.refreshButton
        setTitle:@"UPPDATERA RAPPORT"
        forState:UIControlStateNormal];

    [self.refreshButton
        setTitleColor:UIColor.whiteColor
        forState:UIControlStateNormal];

    [self.refreshButton
        addTarget:self
        action:@selector(buildReport)
        forControlEvents:UIControlEventTouchUpInside];

    self.refreshButton.hidden = YES;

    [self addSubview:self.refreshButton];

    self.dataButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    self.dataButton.frame =
        CGRectMake(10, 357, 282, 38);

    self.dataButton.backgroundColor =
        [UIColor colorWithRed:0.10
                        green:0.52
                         blue:0.26
                        alpha:1];

    self.dataButton.layer.cornerRadius = 7;

    [self.dataButton
        setTitle:@"KOPIERA ALL DATA"
        forState:UIControlStateNormal];

    [self.dataButton
        setTitleColor:UIColor.whiteColor
        forState:UIControlStateNormal];

    [self.dataButton
        addTarget:self
        action:@selector(exportData)
        forControlEvents:UIControlEventTouchUpInside];

    self.dataButton.hidden = YES;

    [self addSubview:self.dataButton];

    self.statusLabel =
        [[UILabel alloc]
            initWithFrame:CGRectMake(10, 400, 282, 18)];

    self.statusLabel.font =
        [UIFont systemFontOfSize:10];

    self.statusLabel.textColor =
        UIColor.whiteColor;

    self.statusLabel.textAlignment =
        NSTextAlignmentCenter;

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

#pragma mark - Panel interaction

- (void)togglePanel {

    self.expanded = !self.expanded;

    CGRect frame = self.frame;

    frame.size = self.expanded
        ? CGSizeMake(302, 425)
        : CGSizeMake(205, 142);

    if (self.superview) {

        CGFloat maxX = MAX(
            0,
            self.superview.bounds.size.width -
            frame.size.width);

        CGFloat maxY = MAX(
            0,
            self.superview.bounds.size.height -
            frame.size.height);

        frame.origin.x =
            MAX(0, MIN(frame.origin.x, maxX));

        frame.origin.y =
            MAX(0, MIN(frame.origin.y, maxY));
    }

    self.frame = frame;

    self.header.frame =
        CGRectMake(0, 0, frame.size.width, 32);

    self.details.hidden = !self.expanded;
    self.refreshButton.hidden = !self.expanded;
    self.dataButton.hidden = !self.expanded;
    self.statusLabel.hidden = !self.expanded;

    [self.header
        setTitle:self.expanded
            ? @"CMS v14 ▲"
            : @"CMS v14 ▼"
        forState:UIControlStateNormal];

    if (self.expanded)
        [self buildReport];
}

- (void)drag:(UIPanGestureRecognizer *)gesture {

    if (!self.superview) return;

    CGPoint delta =
        [gesture translationInView:self.superview];

    CGRect frame = self.frame;

    CGFloat maxX = MAX(
        0,
        self.superview.bounds.size.width -
        frame.size.width);

    CGFloat maxY = MAX(
        0,
        self.superview.bounds.size.height -
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

    if ([gestureRecognizer
            isKindOfClass:UIPanGestureRecognizer.class]) {

        CGPoint point =
            [gestureRecognizer locationInView:self];

        return point.y <= 32;
    }

    return YES;
}

#pragma mark - Alerts

- (void)showAlert:(NSString *)message {

    self.alertGeneration++;

    NSUInteger generation =
        self.alertGeneration;

    self.alertLabel.text = message;
    self.alertLabel.alpha = 1.0;

    self.layer.borderColor =
        UIColor.greenColor.CGColor;

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(2.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{

            if (generation != self.alertGeneration)
                return;

            self.alertLabel.text = @"";

            self.layer.borderColor =
                UIColor.cyanColor.CGColor;
        });
}

#pragma mark - Live counter

- (void)refreshCounters {

    id logger = CMSLogger();

    if (!logger) {

        self.loggerAvailable = NO;
        self.hasBaseline = NO;

        self.counterLabel.text =
            @"ATTACK —  STEAL —\n"
             "SHIELD —  POINT —";

        self.spinLabel.text =
            @"Logger saknas";

        self.lastLabel.text =
            @"Senaste: —";

        return;
    }

    self.loggerAvailable = YES;

    id countsObject =
        CMSGetObject(logger, @"counts");

    NSDictionary *counts = nil;

    if ([countsObject
            isKindOfClass:NSDictionary.class]) {

        counts =
            [(NSDictionary *)countsObject copy];
    }

    NSString *attackText =
        CMSCountText(counts, @"ATTACK");

    NSString *stealText =
        CMSCountText(counts, @"STEAL");

    NSString *shieldText =
        CMSCountText(counts, @"SHIELD");

    NSString *pointText =
        CMSCountText(counts, @"POINT");

    NSString *newCounterText =
        [NSString stringWithFormat:
            @"ATTACK %@  STEAL %@\n"
             "SHIELD %@  POINT %@",
            attackText,
            stealText,
            shieldText,
            pointText];

    if (![self.counterLabel.text
            isEqualToString:newCounterText]) {

        self.counterLabel.text =
            newCounterText;
    }

    long long attack = 0;
    long long steal = 0;
    long long shield = 0;
    long long point = 0;

    BOOL valid =
        CMSCountNumber(counts, @"ATTACK", &attack) &&
        CMSCountNumber(counts, @"STEAL", &steal) &&
        CMSCountNumber(counts, @"SHIELD", &shield) &&
        CMSCountNumber(counts, @"POINT", &point);

    if (valid) {

        if (self.hasBaseline) {

            if (attack > self.previousAttack) {

                [self showAlert:
                    [NSString stringWithFormat:
                        @"ATTACK +%lld",
                        attack - self.previousAttack]];

            } else if (steal > self.previousSteal) {

                [self showAlert:
                    [NSString stringWithFormat:
                        @"STEAL +%lld",
                        steal - self.previousSteal]];

            } else if (shield > self.previousShield) {

                [self showAlert:
                    @"NY SHIELD"];

            } else if (point > self.previousPoint) {

                [self showAlert:
                    @"NY POINT"];
            }
        }

        self.previousAttack = attack;
        self.previousSteal = steal;
        self.previousShield = shield;
        self.previousPoint = point;

        self.hasBaseline = YES;

    } else {

        self.hasBaseline = NO;
    }

    id lastSymbol =
        CMSGetObject(logger, @"lastSymbol");

    NSString *symbol =
        CMSString(lastSymbol);

    NSString *newLastText =
        [NSString stringWithFormat:
            @"Senaste: %@",
            symbol];

    if (![self.lastLabel.text
            isEqualToString:newLastText]) {

        self.lastLabel.text = newLastText;
    }

    long long estimated = 0;
    long long candidates = 0;

    BOOL hasEstimated =
        CMSGetInteger(
            logger,
            @"estimatedSpins",
            &estimated);

    BOOL hasCandidates =
        CMSGetInteger(
            logger,
            @"spinCandidates",
            &candidates);

    NSString *estimatedText =
        hasEstimated
            ? [NSString stringWithFormat:
                @"%lld", estimated]
            : @"—";

    NSString *candidatesText =
        hasCandidates
            ? [NSString stringWithFormat:
                @"%lld", candidates]
            : @"—";

    NSString *newSpinText =
        [NSString stringWithFormat:
            @"Spins ~%@  Rörelse %@",
            estimatedText,
            candidatesText];

    if (![self.spinLabel.text
            isEqualToString:newSpinText]) {

        self.spinLabel.text = newSpinText;
    }
}

#pragma mark - Diagnostics

- (void)buildReport {

    [self refreshCounters];

    NSMutableString *report =
        [NSMutableString stringWithString:
            @"CMSCrystalBridge v14\n"
             "LIVE COUNTER DIAGNOSTICS\n\n"];

    id logger = CMSLogger();

    [report appendFormat:
        @"LOGGER: %@\n",
        logger ? @"FOUND" : @"NOT FOUND"];

    if (logger) {

        id countsObject =
            CMSGetObject(logger, @"counts");

        NSDictionary *counts = nil;

        if ([countsObject
                isKindOfClass:NSDictionary.class]) {

            counts =
                [(NSDictionary *)countsObject copy];
        }

        [report appendString:
            @"\n=== SYMBOL COUNTER ===\n"];

        for (NSString *key in
             @[@"ATTACK", @"STEAL",
               @"SHIELD", @"POINT"]) {

            [report appendFormat:
                @"%@: %@\n",
                key,
                CMSCountText(counts, key)];
        }

        id lastSymbol =
            CMSGetObject(logger, @"lastSymbol");

        [report appendFormat:
            @"\nLAST SYMBOL: %@\n",
            CMSString(lastSymbol)];

        long long estimated = 0;
        long long candidates = 0;

        BOOL hasEstimated =
            CMSGetInteger(
                logger,
                @"estimatedSpins",
                &estimated);

        BOOL hasCandidates =
            CMSGetInteger(
                logger,
                @"spinCandidates",
                &candidates);

        [report appendString:
            @"\n=== SPIN DIAGNOSTICS ===\n"];

        [report appendFormat:
            @"ESTIMATED SPINS: %@\n",
            hasEstimated
                ? [NSString stringWithFormat:
                    @"%lld", estimated]
                : @"N/A"];

        [report appendFormat:
            @"MOTION CANDIDATES: %@\n",
            hasCandidates
                ? [NSString stringWithFormat:
                    @"%lld", candidates]
                : @"N/A"];

        [report appendString:
            @"\n=== ALL COUNT KEYS ===\n"];

        if (counts) {

            NSArray *keys =
                [[counts allKeys]
                    sortedArrayUsingComparator:
                    ^NSComparisonResult(id a, id b) {

                        return [[a description]
                            compare:[b description]];
                    }];

            for (id key in keys) {

                [report appendFormat:
                    @"%@: %@\n",
                    CMSString(key),
                    CMSString(counts[key])];
            }
        }

        id logsObject =
            CMSGetObject(logger, @"logs");

        [report appendString:
            @"\n=== RECENT LOGGER EVENTS ===\n"];

        if ([logsObject
                isKindOfClass:NSArray.class]) {

            NSArray *logs =
                [(NSArray *)logsObject copy];

            NSUInteger start =
                logs.count > 15
                    ? logs.count - 15
                    : 0;

            for (NSUInteger i = start;
                 i < logs.count;
                 i++) {

                NSString *line =
                    CMSString(logs[i]);

                if (line.length > 240) {

                    line =
                        [[line substringToIndex:240]
                            stringByAppendingString:
                                @"..."];
                }

                [report appendFormat:
                    @"%@\n", line];
            }

        } else {

            [report appendString:
                @"Logs unavailable\n"];
        }
    }

    [report appendString:
        @"\n=== STATUS ===\n"
         "Read-only Logger counters\n"
         "Automatic refresh: 1 second\n"
         "Spin estimates not confirmed\n"
         "Motion candidates not confirmed\n"
         "Raid stack not yet verified\n"
         "AutoSpeed unchanged\n"];

    self.fullReport = [report copy];

    self.details.text = report;

    self.statusLabel.text =
        @"Rapport uppdaterad";
}

- (void)exportData {

    [self buildReport];

    if (self.fullReport.length == 0) {
        self.statusLabel.text = @"Ingen data";
        return;
    }

    [UIPasteboard generalPasteboard].string =
        self.fullReport;

    self.statusLabel.text =
        [NSString stringWithFormat:
            @"Kopierat: %lu tecken",
            (unsigned long)self.fullReport.length];

    [self.dataButton
        setTitle:@"KOPIERAT!"
        forState:UIControlStateNormal];
}

@end

#pragma mark - Window setup

static UIWindowScene *CMSForegroundScene(void) {

    for (UIScene *scene in
         UIApplication.sharedApplication.connectedScenes) {

        if ([scene isKindOfClass:UIWindowScene.class] &&
            scene.activationState ==
                UISceneActivationStateForegroundActive) {

            return (UIWindowScene *)scene;
        }
    }

    return nil;
}

static void CMSSetup(void) {

    if (gPanel) return;

    UIWindowScene *scene =
        CMSForegroundScene();

    if (!scene) return;

    gWindow =
        [[CMSBridgeWindow alloc]
            initWithWindowScene:scene];

    gWindow.frame =
        scene.coordinateSpace.bounds;

    gWindow.windowLevel =
        UIWindowLevelAlert + 10;

    UIViewController *controller =
        [UIViewController new];

    controller.view.backgroundColor =
        UIColor.clearColor;

    gWindow.rootViewController =
        controller;

    gPanel =
        [[CMSBridgePanel alloc]
            initWithFrame:
                CGRectMake(12, 90, 205, 142)];

    [controller.view addSubview:gPanel];

    gWindow.panel = gPanel;
    gWindow.hidden = NO;

    [gPanel refreshCounters];

    NSTimer *timer =
        [NSTimer
            timerWithTimeInterval:1.0
            repeats:YES
            block:^(NSTimer *t) {

                if (!gPanel ||
                    gPanel.hidden)
                    return;

                if (UIApplication
                        .sharedApplication
                        .applicationState !=
                    UIApplicationStateActive)
                    return;

                [gPanel refreshCounters];
            }];

    [[NSRunLoop mainRunLoop]
        addTimer:timer
        forMode:NSRunLoopCommonModes];
}

#pragma mark - Startup

__attribute__((constructor))
static void CMSBridgeV14Start(void) {

    dispatch_async(
        dispatch_get_main_queue(), ^{

            const int delays[] = {3, 10, 25};

            for (unsigned i = 0; i < 3; i++) {

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)delays[i] *
                            NSEC_PER_SEC),
                    dispatch_get_main_queue(), ^{

                        CMSSetup();
                    });
            }
        });
}


#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <string.h>

#pragma mark - CMSCrystalBridge v15

@interface CMSBridgeWindow : UIWindow
@property(nonatomic, weak) UIView *panel;
@end

@implementation CMSBridgeWindow

- (UIView *)hitTest:(CGPoint)point
          withEvent:(UIEvent *)event {
    UIView *panel = self.panel;
    if (!panel || panel.hidden) return nil;

    CGPoint p = [panel convertPoint:point fromView:self];
    if (![panel pointInside:p withEvent:event]) return nil;

    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view)
        return nil;
    return hit;
}
@end

#pragma mark - Logger access

static id CMSGetObject(id obj, NSString *name) {
    if (!obj) return nil;

    SEL sel = NSSelectorFromString(name);
    NSMethodSignature *sig =
        [obj methodSignatureForSelector:sel];

    if (!sig || sig.numberOfArguments != 2 ||
        strcmp(sig.methodReturnType, "@") != 0)
        return nil;

    IMP imp = [obj methodForSelector:sel];
    if (!imp) return nil;

    id (*fn)(id, SEL) = (id (*)(id, SEL))imp;
    return fn(obj, sel);
}

static BOOL CMSGetInteger(id obj,
                          NSString *name,
                          long long *out) {
    if (!obj || !out) return NO;

    SEL sel = NSSelectorFromString(name);
    NSMethodSignature *sig =
        [obj methodSignatureForSelector:sel];

    if (!sig || sig.numberOfArguments != 2)
        return NO;

    const char *type = sig.methodReturnType;
    if (!type ||
        (strcmp(type, "q") != 0 &&
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
    return cls ? CMSGetObject(cls, @"shared") : nil;
}

static BOOL CMSReadCount(NSDictionary *dict,
                         NSString *key,
                         long long *out) {
    if (!dict || !out) return NO;

    id value = dict[key];
    if (!value) {
        *out = 0;
        return YES;
    }

    if (![value isKindOfClass:NSNumber.class])
        return NO;

    *out = [value longLongValue];
    return YES;
}

#pragma mark - Symbol state

@interface CMSSymbolState : NSObject
@property(nonatomic,copy) NSString *name;
@property(nonatomic,copy) NSString *key;
@property(nonatomic,assign) long long previousCount;
@property(nonatomic,assign) long long lastSpin;
@property(nonatomic,assign) BOOL hasBaseline;
@property(nonatomic,assign) BOOL hasOccurrence;
@property(nonatomic,strong) UILabel *label;
@end

@implementation CMSSymbolState
@end

#pragma mark - Main panel

@interface CMSBridgePanel : UIView
<UIGestureRecognizerDelegate>

@property(nonatomic,strong) UILabel *heading;
@property(nonatomic,strong) UILabel *spinLabel;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UIButton *hideButton;

@property(nonatomic,strong) NSArray<CMSSymbolState *> *symbols;

@property(nonatomic,assign) long long currentSpin;
@property(nonatomic,assign) BOOL hasSpin;
@property(nonatomic,assign) BOOL loggerReady;

- (void)refresh;
@end

static CMSBridgeWindow *gBridgeWindow = nil;
static CMSBridgePanel *gBridgePanel = nil;

static CMSSymbolState *CMSMakeSymbol(
    NSString *name,
    NSString *key) {

    CMSSymbolState *s = [CMSSymbolState new];
    s.name = name;
    s.key = key;
    s.previousCount = 0;
    s.lastSpin = 0;
    s.hasBaseline = NO;
    s.hasOccurrence = NO;
    return s;
}

#pragma mark - Old overlay visibility

static BOOL CMSHasDiagnosticText(
    UIView *view,
    NSUInteger depth) {

    if (!view || depth > 12) return NO;

    NSString *text = nil;

    if ([view isKindOfClass:UILabel.class])
        text = ((UILabel *)view).text;

    if ([view isKindOfClass:UITextView.class])
        text = ((UITextView *)view).text;

    if ([view isKindOfClass:UIButton.class])
        text = [((UIButton *)view)
            titleForState:UIControlStateNormal];

    if (text.length) {
        if ([text containsString:@"CMSCrystalLogger"] ||
            [text containsString:@"RESULT QUIET"] ||
            [text containsString:@"CMSCrystal History"] ||
            [text containsString:@"CMSCrystalBridge v14"])
            return YES;
    }

    for (UIView *child in view.subviews) {
        if (CMSHasDiagnosticText(child, depth + 1))
            return YES;
    }

    return NO;
}

static NSUInteger CMSHideOldOverlayWindows(void) {

    NSUInteger hidden = 0;

    for (UIScene *scene in
         UIApplication.sharedApplication.connectedScenes) {

        if (![scene isKindOfClass:UIWindowScene.class])
            continue;

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        for (UIWindow *window in windowScene.windows) {

            if (window == gBridgeWindow ||
                window.hidden ||
                !window.rootViewController)
                continue;

            // Only hide distinct floating alert-level
            // windows. Never hide the game's main window.
            if (window.windowLevel < UIWindowLevelAlert)
                continue;

            if (!CMSHasDiagnosticText(
                    window.rootViewController.view, 0))
                continue;

            window.hidden = YES;
            hidden++;
        }
    }

    return hidden;
}

#pragma mark - Panel implementation

@implementation CMSBridgePanel

- (instancetype)initWithFrame:(CGRect)frame {

    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor =
        [[UIColor blackColor] colorWithAlphaComponent:0.94];

    self.layer.cornerRadius = 12;
    self.layer.borderWidth = 1;
    self.layer.borderColor = UIColor.cyanColor.CGColor;
    self.clipsToBounds = YES;

    self.symbols = @[
        CMSMakeSymbol(@"ATTACK", @"ATTACK"),
        CMSMakeSymbol(@"STEAL", @"STEAL"),
        CMSMakeSymbol(@"POINT", @"POINT"),
        CMSMakeSymbol(@"GRÖN FLASKA", @"GREEN_BOTTLE")
    ];

    self.heading =
        [[UILabel alloc] initWithFrame:
            CGRectMake(10, 8, 210, 24)];

    self.heading.text = @"CMS BRIDGE v15";
    self.heading.textColor = UIColor.cyanColor;
    self.heading.font =
        [UIFont boldSystemFontOfSize:14];

    [self addSubview:self.heading];

    UILabel *subtitle =
        [[UILabel alloc] initWithFrame:
            CGRectMake(10, 32, 210, 18)];

    subtitle.text = @"Spins sedan senaste symbol";
    subtitle.textColor = UIColor.lightGrayColor;
    subtitle.font = [UIFont systemFontOfSize:10];

    [self addSubview:subtitle];

    NSArray *colors = @[
        UIColor.systemRedColor,
        UIColor.systemOrangeColor,
        UIColor.systemYellowColor,
        UIColor.systemGreenColor
    ];

    for (NSUInteger i = 0; i < self.symbols.count; i++) {

        CMSSymbolState *symbol = self.symbols[i];

        UILabel *label =
            [[UILabel alloc] initWithFrame:
                CGRectMake(10, 56 + i * 34, 210, 30)];

        label.font =
            [UIFont monospacedSystemFontOfSize:12
                                       weight:UIFontWeightSemibold];

        label.textColor = colors[i];
        label.text = [NSString stringWithFormat:
            @"%@   —", symbol.name];

        symbol.label = label;
        [self addSubview:label];
    }

    self.spinLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(10, 195, 210, 20)];

    self.spinLabel.text = @"Spins ~—";
    self.spinLabel.textColor = UIColor.whiteColor;
    self.spinLabel.font =
        [UIFont monospacedSystemFontOfSize:11
                                   weight:UIFontWeightRegular];

    [self addSubview:self.spinLabel];

    self.statusLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(10, 216, 210, 20)];

    self.statusLabel.text = @"Väntar på Logger";
    self.statusLabel.textColor = UIColor.lightGrayColor;
    self.statusLabel.font = [UIFont systemFontOfSize:10];

    [self addSubview:self.statusLabel];

    self.hideButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    self.hideButton.frame =
        CGRectMake(10, 241, 210, 33);

    self.hideButton.backgroundColor =
        [UIColor colorWithRed:0.12
                        green:0.32
                         blue:0.45
                        alpha:1];

    self.hideButton.layer.cornerRadius = 7;

    [self.hideButton
        setTitle:@"DÖLJ GAMLA RUTOR"
        forState:UIControlStateNormal];

    [self.hideButton
        setTitleColor:UIColor.whiteColor
        forState:UIControlStateNormal];

    self.hideButton.titleLabel.font =
        [UIFont boldSystemFontOfSize:11];

    [self.hideButton
        addTarget:self
        action:@selector(hideOldOverlays)
        forControlEvents:UIControlEventTouchUpInside];

    [self addSubview:self.hideButton];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
            action:@selector(drag:)];

    pan.delegate = self;
    pan.cancelsTouchesInView = NO;

    [self addGestureRecognizer:pan];

    return self;
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
        MAX(0, MIN(maxX, frame.origin.x + delta.x));

    frame.origin.y =
        MAX(0, MIN(maxY, frame.origin.y + delta.y));

    self.frame = frame;

    [gesture setTranslation:CGPointZero
                    inView:self.superview];
}

- (BOOL)gestureRecognizerShouldBegin:
    (UIGestureRecognizer *)gestureRecognizer {

    if ([gestureRecognizer
            isKindOfClass:UIPanGestureRecognizer.class]) {

        CGPoint p =
            [gestureRecognizer locationInView:self];

        return p.y <= 32;
    }

    return YES;
}

- (void)hideOldOverlays {

    NSUInteger hidden = CMSHideOldOverlayWindows();

    self.statusLabel.text =
        [NSString stringWithFormat:
            @"Dolda äldre fönster: %lu",
            (unsigned long)hidden];
}

- (void)refresh {

    id logger = CMSLogger();

    if (!logger) {
        self.loggerReady = NO;
        self.statusLabel.text = @"Logger saknas";
        return;
    }

    id countsObject =
        CMSGetObject(logger, @"counts");

    if (![countsObject isKindOfClass:NSDictionary.class]) {
        self.loggerReady = NO;
        self.statusLabel.text = @"Väntar på symboldata";
        return;
    }

    NSDictionary *counts =
        [(NSDictionary *)countsObject copy];

    long long spins = 0;

    BOOL spinValid =
        CMSGetInteger(
            logger, @"estimatedSpins", &spins);

    if (spinValid && spins >= 0) {
        if (self.hasSpin && spins < self.currentSpin) {
            // Logger's spin estimate reset.
            // Previous occurrence positions are no
            // longer comparable.
            for (CMSSymbolState *s in self.symbols)
                s.hasOccurrence = NO;
        }

        self.currentSpin = spins;
        self.hasSpin = YES;
    } else {
        self.hasSpin = NO;
    }

    self.spinLabel.text = self.hasSpin
        ? [NSString stringWithFormat:
            @"Spins ~%lld", self.currentSpin]
        : @"Spins ~—";

    for (CMSSymbolState *symbol in self.symbols) {

        long long count = 0;

        BOOL valid =
            CMSReadCount(counts, symbol.key, &count);

        if (!valid) {
            symbol.label.text =
                [NSString stringWithFormat:
                    @"%@   —", symbol.name];
            continue;
        }

        if (!symbol.hasBaseline) {
            symbol.previousCount = count;
            symbol.hasBaseline = YES;

            // Existing historical counts have no
            // known occurrence spin. Wait for a
            // new symbol to establish a baseline.
        } else if (count > symbol.previousCount) {

            symbol.lastSpin = self.currentSpin;
            symbol.hasOccurrence = self.hasSpin;
            symbol.previousCount = count;

        } else if (count < symbol.previousCount) {

            // Logger restarted or counters reset.
            symbol.previousCount = count;
            symbol.hasOccurrence = NO;
        }

        NSString *since = @"—";

        if (symbol.hasOccurrence && self.hasSpin) {

            long long difference =
                self.currentSpin - symbol.lastSpin;

            if (difference >= 0)
                since = [NSString stringWithFormat:
                    @"%lld", difference];
        }

        symbol.label.text =
            [NSString stringWithFormat:
                @"%@   %@",
                symbol.name, since];
    }

    self.loggerReady = YES;

    // Bottle is not yet confirmed as a Logger key.
    if (!counts[@"GREEN_BOTTLE"]) {
        self.statusLabel.text =
            @"Grön flaska: ej identifierad";
    } else {
        self.statusLabel.text =
            @"Symbolräknare aktiva";
    }
}

@end

#pragma mark - Setup

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

    if (gBridgePanel) return;

    UIWindowScene *scene = CMSForegroundScene();
    if (!scene) return;

    gBridgeWindow =
        [[CMSBridgeWindow alloc]
            initWithWindowScene:scene];

    gBridgeWindow.frame =
        scene.coordinateSpace.bounds;

    gBridgeWindow.windowLevel =
        UIWindowLevelAlert + 10;

    UIViewController *controller =
        [UIViewController new];

    controller.view.backgroundColor =
        UIColor.clearColor;

    gBridgeWindow.rootViewController = controller;

    gBridgePanel =
        [[CMSBridgePanel alloc]
            initWithFrame:
                CGRectMake(12, 85, 230, 282)];

    [controller.view addSubview:gBridgePanel];

    gBridgeWindow.panel = gBridgePanel;
    gBridgeWindow.hidden = NO;

    [gBridgePanel refresh];

    NSTimer *timer =
        [NSTimer timerWithTimeInterval:1.0
                              repeats:YES
                                block:^(NSTimer *t) {

        if (gBridgePanel &&
            !gBridgePanel.hidden &&
            UIApplication.sharedApplication.applicationState ==
                UIApplicationStateActive)
            [gBridgePanel refresh];
    }];

    [[NSRunLoop mainRunLoop]
        addTimer:timer
        forMode:NSRunLoopCommonModes];
}

__attribute__((constructor))
static void CMSBridgeV15Start(void) {

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

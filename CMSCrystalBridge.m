
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <string.h>

#pragma mark - CMSCrystalBridge v18

static const NSTimeInterval kRefresh = 0.1;

// 0.20 = 80% transparent
static const CGFloat kPanelOpacity = 0.20;

#pragma mark - Touch-through window

@interface CMSBridgeWindow : UIWindow
@property(nonatomic,weak) UIView *panel;
@end

@implementation CMSBridgeWindow

- (UIView *)hitTest:(CGPoint)point
          withEvent:(UIEvent *)event {

    UIView *panel = self.panel;

    if (!panel || panel.hidden)
        return nil;

    CGPoint local =
        [panel convertPoint:point fromView:self];

    // Only the top 32 points capture touches.
    // All other touches pass through to the game.
    if (local.x < 0 ||
        local.x > panel.bounds.size.width ||
        local.y < 0 ||
        local.y > 32)
        return nil;

    return [super hitTest:point withEvent:event];
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

    id (*fn)(id, SEL) =
        (id (*)(id, SEL))imp;

    return fn(obj, sel);
}

static BOOL CMSGetInteger(
    id obj,
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

    return cls
        ? CMSGetObject(cls, @"shared")
        : nil;
}

static BOOL CMSReadCount(
    NSDictionary *counts,
    NSString *key,
    long long *out) {

    if (!counts || !out) return NO;

    id value = counts[key];

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

@property(nonatomic,strong) UIColor *color;
@property(nonatomic,strong) NSArray<UILabel *> *cells;

@property(nonatomic,assign) long long observedCount;
@property(nonatomic,assign) long long lastSpin;

@property(nonatomic,assign) BOOL hasBaseline;
@property(nonatomic,assign) BOOL hasOccurrence;

@property(nonatomic,strong)
NSMutableArray<NSNumber *> *history;

@end

@implementation CMSSymbolState
@end

static CMSSymbolState *CMSMakeSymbol(
    NSString *name,
    NSString *key,
    UIColor *color) {

    CMSSymbolState *s = [CMSSymbolState new];

    s.name = name;
    s.key = key;
    s.color = color;

    s.history = [NSMutableArray array];

    return s;
}

#pragma mark - Panel

@interface CMSBridgePanel : UIView
<UIGestureRecognizerDelegate>

@property(nonatomic,strong) UILabel *spinLabel;
@property(nonatomic,strong) UILabel *statusLabel;

@property(nonatomic,strong)
NSArray<CMSSymbolState *> *symbols;

@property(nonatomic,assign) long long currentSpin;
@property(nonatomic,assign) BOOL hasSpin;

- (void)refresh;

@end

static CMSBridgeWindow *gWindow = nil;
static CMSBridgePanel *gPanel = nil;

@implementation CMSBridgePanel

- (instancetype)initWithFrame:(CGRect)frame {

    self = [super initWithFrame:frame];

    if (!self) return nil;

    // Transparent background, readable text.
    self.backgroundColor =
        [[UIColor blackColor]
            colorWithAlphaComponent:kPanelOpacity];

    self.layer.cornerRadius = 12;
    self.layer.borderWidth = 1;

    self.layer.borderColor =
        [[UIColor cyanColor]
            colorWithAlphaComponent:0.65].CGColor;

    self.clipsToBounds = YES;

    self.symbols = @[
        CMSMakeSymbol(
            @"ATTACK", @"ATTACK",
            UIColor.systemRedColor),

        CMSMakeSymbol(
            @"STEAL", @"STEAL",
            UIColor.systemOrangeColor),

        CMSMakeSymbol(
            @"POINT", @"POINT",
            UIColor.systemYellowColor),

        CMSMakeSymbol(
            @"FLASKA", @"GREEN_BOTTLE",
            UIColor.systemGreenColor)
    ];

    UILabel *title =
        [[UILabel alloc]
            initWithFrame:
                CGRectMake(10, 8, 300, 24)];

    title.text = @"CMS BRIDGE v18";
    title.textColor = UIColor.cyanColor;

    title.font =
        [UIFont boldSystemFontOfSize:14];

    [self addSubview:title];

    NSArray *headers =
        @[@"SYMBOL", @"NU", @"FÖRRA", @"-2", @"-3"];

    CGFloat x[] = {10, 119, 167, 224, 271};
    CGFloat w[] = {103, 43, 51, 41, 39};

    for (NSUInteger j = 0; j < 5; j++) {

        UILabel *label =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(x[j], 39, w[j], 18)];

        label.text = headers[j];

        label.font =
            [UIFont systemFontOfSize:10];

        label.textColor = UIColor.whiteColor;

        label.textAlignment =
            j == 0
                ? NSTextAlignmentLeft
                : NSTextAlignmentRight;

        [self addSubview:label];
    }

    for (NSUInteger i = 0;
         i < self.symbols.count;
         i++) {

        CMSSymbolState *s = self.symbols[i];

        CGFloat y = 62 + i * 38;

        UILabel *name =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(10, y, 103, 28)];

        name.text = s.name;
        name.textColor = s.color;

        name.font =
            [UIFont boldSystemFontOfSize:12];

        [self addSubview:name];

        NSMutableArray *cells =
            [NSMutableArray array];

        for (NSUInteger j = 1; j < 5; j++) {

            UILabel *cell =
                [[UILabel alloc]
                    initWithFrame:
                        CGRectMake(x[j], y, w[j], 28)];

            cell.text = @"—";

            cell.textAlignment =
                NSTextAlignmentRight;

            cell.textColor =
                j == 1
                    ? UIColor.whiteColor
                    : UIColor.lightGrayColor;

            cell.font =
                [UIFont monospacedDigitSystemFontOfSize:
                    j == 1 ? 17 : 13
                    weight:
                    j == 1
                        ? UIFontWeightBold
                        : UIFontWeightRegular];

            [self addSubview:cell];

            [cells addObject:cell];
        }

        s.cells = [cells copy];
    }

    UIView *line =
        [[UIView alloc]
            initWithFrame:
                CGRectMake(10, 218, 300, 1)];

    line.backgroundColor =
        [[UIColor whiteColor]
            colorWithAlphaComponent:0.35];

    [self addSubview:line];

    self.spinLabel =
        [[UILabel alloc]
            initWithFrame:
                CGRectMake(10, 224, 300, 23)];

    self.spinLabel.text = @"Spins ~—";
    self.spinLabel.textColor = UIColor.cyanColor;

    self.spinLabel.font =
        [UIFont monospacedDigitSystemFontOfSize:13
                                        weight:UIFontWeightMedium];

    [self addSubview:self.spinLabel];

    self.statusLabel =
        [[UILabel alloc]
            initWithFrame:
                CGRectMake(10, 251, 300, 20)];

    self.statusLabel.text =
        @"Väntar på Logger";

    self.statusLabel.textColor =
        UIColor.whiteColor;

    self.statusLabel.font =
        [UIFont systemFontOfSize:10];

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

#pragma mark - Dragging

- (void)drag:(UIPanGestureRecognizer *)gesture {

    if (!self.superview) return;

    CGPoint delta =
        [gesture translationInView:self.superview];

    CGRect f = self.frame;

    CGFloat maxX = MAX(
        0,
        self.superview.bounds.size.width -
        f.size.width);

    CGFloat maxY = MAX(
        0,
        self.superview.bounds.size.height -
        f.size.height);

    f.origin.x =
        MAX(0, MIN(maxX, f.origin.x + delta.x));

    f.origin.y =
        MAX(0, MIN(maxY, f.origin.y + delta.y));

    self.frame = f;

    [gesture setTranslation:CGPointZero
                    inView:self.superview];
}

- (BOOL)gestureRecognizerShouldBegin:
    (UIGestureRecognizer *)gesture {

    if ([gesture
            isKindOfClass:UIPanGestureRecognizer.class]) {

        CGPoint p =
            [gesture locationInView:self];

        return p.y <= 32;
    }

    return YES;
}

#pragma mark - Refresh

- (void)refresh {

    id logger = CMSLogger();

    if (!logger) {
        self.statusLabel.text = @"Logger saknas";
        return;
    }

    id obj = CMSGetObject(logger, @"counts");

    if (![obj isKindOfClass:NSDictionary.class]) {
        self.statusLabel.text =
            @"Väntar på symboldata";
        return;
    }

    NSDictionary *counts =
        [(NSDictionary *)obj copy];

    long long spins = 0;

    BOOL valid =
        CMSGetInteger(
            logger, @"estimatedSpins", &spins)
        && spins >= 0;

    if (valid) {

        if (self.hasSpin &&
            spins < self.currentSpin) {

            for (CMSSymbolState *s in self.symbols) {
                s.hasOccurrence = NO;
                [s.history removeAllObjects];
            }
        }

        self.currentSpin = spins;
        self.hasSpin = YES;

    } else {
        self.hasSpin = NO;
    }

    self.spinLabel.text =
        self.hasSpin
            ? [NSString stringWithFormat:
                @"Spins ~%lld", self.currentSpin]
            : @"Spins ~—";

    for (CMSSymbolState *s in self.symbols) {

        if ([s.key
                isEqualToString:@"GREEN_BOTTLE"] &&
            !counts[s.key]) {

            for (UILabel *cell in s.cells)
                cell.text = @"—";

            s.hasBaseline = NO;
            s.hasOccurrence = NO;
            [s.history removeAllObjects];

            continue;
        }

        long long count = 0;

        if (!CMSReadCount(counts, s.key, &count))
            continue;

        if (!s.hasBaseline) {

            s.observedCount = count;
            s.hasBaseline = YES;

        } else if (count < s.observedCount) {

            s.observedCount = count;
            s.hasOccurrence = NO;
            [s.history removeAllObjects];

        } else if (count > s.observedCount) {

            // Reset only this symbol.

            if (self.hasSpin) {

                if (s.hasOccurrence) {

                    long long interval =
                        self.currentSpin - s.lastSpin;

                    if (interval >= 0) {

                        [s.history
                            insertObject:@(interval)
                            atIndex:0];

                        while (s.history.count > 3)
                            [s.history removeLastObject];
                    }
                }

                s.lastSpin = self.currentSpin;
                s.hasOccurrence = YES;

            } else {
                s.hasOccurrence = NO;
            }

            s.observedCount = count;
        }

        NSString *now = @"—";

        if (self.hasSpin && s.hasOccurrence) {

            long long elapsed =
                self.currentSpin - s.lastSpin;

            if (elapsed >= 0)
                now = [NSString stringWithFormat:
                    @"%lld", elapsed];
        }

        s.cells[0].text = now;

        for (NSUInteger i = 0; i < 3; i++) {

            s.cells[i + 1].text =
                i < s.history.count
                    ? [s.history[i] stringValue]
                    : @"—";
        }
    }

    self.statusLabel.text =
        counts[@"GREEN_BOTTLE"]
            ? @"10 Hz · transparent · touch-through"
            : @"10 Hz · flaska ej identifierad";
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

    gWindow.rootViewController = controller;

    gPanel =
        [[CMSBridgePanel alloc]
            initWithFrame:
                CGRectMake(12, 90, 320, 280)];

    [controller.view addSubview:gPanel];

    gWindow.panel = gPanel;
    gWindow.hidden = NO;

    [gPanel refresh];

    NSTimer *timer =
        [NSTimer timerWithTimeInterval:kRefresh
                              repeats:YES
                                block:^(NSTimer *t) {

        if (!gPanel || gPanel.hidden)
            return;

        if (UIApplication.sharedApplication.applicationState !=
            UIApplicationStateActive)
            return;

        [gPanel refresh];
    }];

    [[NSRunLoop mainRunLoop]
        addTimer:timer
        forMode:NSRunLoopCommonModes];
}

__attribute__((constructor))
static void CMSBridgeV18Start(void) {

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

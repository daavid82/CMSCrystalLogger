
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <string.h>

#pragma mark - CMSCrystalBridge v17

// Update interval: 0.1 seconds
static const NSTimeInterval kCMSRefreshInterval = 0.1;

#pragma mark - Pass-through window

@interface CMSBridgeWindow : UIWindow
@property(nonatomic, weak) UIView *panel;
@end

@implementation CMSBridgeWindow

- (UIView *)hitTest:(CGPoint)point
          withEvent:(UIEvent *)event {

    UIView *panel = self.panel;

    if (!panel || panel.hidden)
        return nil;

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

#pragma mark - Logger runtime access

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

    if (!object || !output)
        return NO;

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

    if (!cls)
        return nil;

    return CMSGetObject(cls, @"shared");
}

static BOOL CMSReadCount(
    NSDictionary *counts,
    NSString *key,
    long long *output) {

    if (!counts || !output)
        return NO;

    id value = counts[key];

    if (!value) {
        *output = 0;
        return YES;
    }

    if (![value isKindOfClass:NSNumber.class])
        return NO;

    *output = [value longLongValue];

    return YES;
}

#pragma mark - Symbol state

@interface CMSSymbolState : NSObject

@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *key;

@property(nonatomic, strong) UIColor *color;

@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) NSArray<UILabel *> *cells;

@property(nonatomic, assign) long long observedCount;
@property(nonatomic, assign) long long lastSpin;

@property(nonatomic, assign) BOOL hasBaseline;
@property(nonatomic, assign) BOOL hasOccurrence;

@property(nonatomic, strong)
NSMutableArray<NSNumber *> *history;

@end

@implementation CMSSymbolState
@end

static CMSSymbolState *CMSMakeSymbol(
    NSString *name,
    NSString *key,
    UIColor *color) {

    CMSSymbolState *symbol =
        [CMSSymbolState new];

    symbol.name = name;
    symbol.key = key;
    symbol.color = color;

    symbol.hasBaseline = NO;
    symbol.hasOccurrence = NO;

    symbol.history = [NSMutableArray array];

    return symbol;
}

#pragma mark - Panel

@interface CMSBridgePanel : UIView
<UIGestureRecognizerDelegate>

@property(nonatomic, strong) UILabel *spinLabel;
@property(nonatomic, strong) UILabel *statusLabel;

@property(nonatomic, strong)
NSArray<CMSSymbolState *> *symbols;

@property(nonatomic, assign) long long currentSpin;
@property(nonatomic, assign) BOOL hasSpin;

- (void)refresh;

@end

static CMSBridgeWindow *gBridgeWindow = nil;
static CMSBridgePanel *gBridgePanel = nil;

@implementation CMSBridgePanel

- (instancetype)initWithFrame:(CGRect)frame {

    self = [super initWithFrame:frame];

    if (!self)
        return nil;

    self.backgroundColor =
        [[UIColor blackColor]
            colorWithAlphaComponent:0.94];

    self.layer.cornerRadius = 12;
    self.layer.borderWidth = 1;

    self.layer.borderColor =
        UIColor.cyanColor.CGColor;

    self.clipsToBounds = YES;

    self.symbols = @[
        CMSMakeSymbol(
            @"ATTACK",
            @"ATTACK",
            UIColor.systemRedColor),

        CMSMakeSymbol(
            @"STEAL",
            @"STEAL",
            UIColor.systemOrangeColor),

        CMSMakeSymbol(
            @"POINT",
            @"POINT",
            UIColor.systemYellowColor),

        CMSMakeSymbol(
            @"FLASKA",
            @"GREEN_BOTTLE",
            UIColor.systemGreenColor)
    ];

    UILabel *title =
        [[UILabel alloc]
            initWithFrame:CGRectMake(10, 8, 300, 24)];

    title.text = @"CMS BRIDGE v17";

    title.textColor =
        UIColor.cyanColor;

    title.font =
        [UIFont boldSystemFontOfSize:14];

    [self addSubview:title];

    NSArray *headers =
        @[@"SYMBOL", @"NU", @"FÖRRA", @"-2", @"-3"];

    CGFloat x[] = {
        10, 119, 167, 224, 271
    };

    CGFloat widths[] = {
        103, 43, 51, 41, 39
    };

    for (NSUInteger j = 0; j < 5; j++) {

        UILabel *label =
            [[UILabel alloc]
                initWithFrame:CGRectMake(
                    x[j], 39, widths[j], 18)];

        label.text = headers[j];

        label.font =
            [UIFont systemFontOfSize:10];

        label.textColor =
            UIColor.lightGrayColor;

        label.textAlignment =
            j == 0
                ? NSTextAlignmentLeft
                : NSTextAlignmentRight;

        [self addSubview:label];
    }

    for (NSUInteger i = 0;
         i < self.symbols.count;
         i++) {

        CMSSymbolState *symbol =
            self.symbols[i];

        CGFloat y = 62 + i * 38;

        UILabel *name =
            [[UILabel alloc]
                initWithFrame:CGRectMake(
                    10, y, 103, 28)];

        name.text = symbol.name;
        name.textColor = symbol.color;

        name.font =
            [UIFont boldSystemFontOfSize:12];

        symbol.nameLabel = name;

        [self addSubview:name];

        NSMutableArray<UILabel *> *cells =
            [NSMutableArray array];

        for (NSUInteger j = 1; j < 5; j++) {

            UILabel *cell =
                [[UILabel alloc]
                    initWithFrame:CGRectMake(
                        x[j], y, widths[j], 28)];

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

        symbol.cells = [cells copy];
    }

    UIView *separator =
        [[UIView alloc]
            initWithFrame:CGRectMake(
                10, 218, 300, 1)];

    separator.backgroundColor =
        UIColor.darkGrayColor;

    [self addSubview:separator];

    self.spinLabel =
        [[UILabel alloc]
            initWithFrame:CGRectMake(
                10, 224, 300, 23)];

    self.spinLabel.text = @"Spins ~—";

    self.spinLabel.textColor =
        UIColor.cyanColor;

    self.spinLabel.font =
        [UIFont monospacedDigitSystemFontOfSize:13
                                        weight:UIFontWeightMedium];

    [self addSubview:self.spinLabel];

    self.statusLabel =
        [[UILabel alloc]
            initWithFrame:CGRectMake(
                10, 251, 300, 20)];

    self.statusLabel.text =
        @"Väntar på Logger";

    self.statusLabel.textColor =
        UIColor.lightGrayColor;

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

    if (!self.superview)
        return;

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
        MAX(0, MIN(
            maxX,
            frame.origin.x + delta.x));

    frame.origin.y =
        MAX(0, MIN(
            maxY,
            frame.origin.y + delta.y));

    self.frame = frame;

    [gesture setTranslation:CGPointZero
                    inView:self.superview];
}

- (BOOL)gestureRecognizerShouldBegin:
    (UIGestureRecognizer *)gesture {

    if ([gesture
            isKindOfClass:UIPanGestureRecognizer.class]) {

        CGPoint point =
            [gesture locationInView:self];

        return point.y <= 32;
    }

    return YES;
}

#pragma mark - Update counters

- (void)refresh {

    id logger = CMSLogger();

    if (!logger) {

        self.statusLabel.text =
            @"Logger saknas";

        return;
    }

    id countsObject =
        CMSGetObject(logger, @"counts");

    if (![countsObject
            isKindOfClass:NSDictionary.class]) {

        self.statusLabel.text =
            @"Väntar på symboldata";

        return;
    }

    NSDictionary *counts =
        [(NSDictionary *)countsObject copy];

    long long spins = 0;

    BOOL spinValid =
        CMSGetInteger(
            logger,
            @"estimatedSpins",
            &spins) && spins >= 0;

    if (spinValid) {

        if (self.hasSpin &&
            spins < self.currentSpin) {

            // Logger's spin estimate reset.
            // Clear intervals that can no longer
            // be compared to the new spin baseline.

            for (CMSSymbolState *symbol
                 in self.symbols) {

                symbol.hasOccurrence = NO;

                [symbol.history
                    removeAllObjects];
            }
        }

        self.currentSpin = spins;
        self.hasSpin = YES;

    } else {

        self.hasSpin = NO;
    }

    NSString *spinText =
        self.hasSpin
            ? [NSString stringWithFormat:
                @"Spins ~%lld",
                self.currentSpin]
            : @"Spins ~—";

    if (![self.spinLabel.text
            isEqualToString:spinText]) {

        self.spinLabel.text = spinText;
    }

    for (CMSSymbolState *symbol
         in self.symbols) {

        // GREEN_BOTTLE is a placeholder key.
        // Do not invent bottle events when the
        // Logger does not provide this counter.

        if ([symbol.key
                isEqualToString:@"GREEN_BOTTLE"] &&
            !counts[symbol.key]) {

            for (UILabel *cell in symbol.cells)
                cell.text = @"—";

            symbol.hasBaseline = NO;
            symbol.hasOccurrence = NO;

            [symbol.history removeAllObjects];

            continue;
        }

        long long count = 0;

        if (!CMSReadCount(
                counts,
                symbol.key,
                &count)) {

            continue;
        }

        if (!symbol.hasBaseline) {

            // Existing total counts cannot tell
            // us the last occurrence's spin.

            symbol.observedCount = count;
            symbol.hasBaseline = YES;

        } else if (count < symbol.observedCount) {

            // Logger counters restarted.

            symbol.observedCount = count;
            symbol.hasOccurrence = NO;

            [symbol.history removeAllObjects];

        } else if (count > symbol.observedCount) {

            // This symbol was detected again.
            // Only this symbol's timer resets.

            if (self.hasSpin) {

                if (symbol.hasOccurrence) {

                    long long interval =
                        self.currentSpin -
                        symbol.lastSpin;

                    if (interval >= 0) {

                        [symbol.history
                            insertObject:@(interval)
                            atIndex:0];

                        // Keep the last 3 intervals.

                        while (symbol.history.count > 3) {

                            [symbol.history
                                removeLastObject];
                        }
                    }
                }

                symbol.lastSpin =
                    self.currentSpin;

                symbol.hasOccurrence = YES;

            } else {

                symbol.hasOccurrence = NO;
            }

            symbol.observedCount = count;
        }

        // NU: spins since latest occurrence.

        NSString *currentText = @"—";

        if (self.hasSpin &&
            symbol.hasOccurrence) {

            long long elapsed =
                self.currentSpin -
                symbol.lastSpin;

            if (elapsed >= 0) {

                currentText =
                    [NSString stringWithFormat:
                        @"%lld", elapsed];
            }
        }

        UILabel *currentCell = symbol.cells[0];

        if (![currentCell.text
                isEqualToString:currentText]) {

            currentCell.text = currentText;
        }

        // FÖRRA, -2, -3:
        // Three independent historical intervals.

        for (NSUInteger i = 0; i < 3; i++) {

            NSString *value = @"—";

            if (i < symbol.history.count) {

                value =
                    [symbol.history[i]
                        stringValue];
            }

            UILabel *cell =
                symbol.cells[i + 1];

            if (![cell.text
                    isEqualToString:value]) {

                cell.text = value;
            }
        }
    }

    self.statusLabel.text =
        counts[@"GREEN_BOTTLE"]
            ? @"10 Hz · uppskattade spins"
            : @"10 Hz · flaska ej identifierad";
}

@end

#pragma mark - Window setup

static UIWindowScene *CMSForegroundScene(void) {

    for (UIScene *scene in
         UIApplication.sharedApplication.connectedScenes) {

        if ([scene
                isKindOfClass:UIWindowScene.class] &&
            scene.activationState ==
                UISceneActivationStateForegroundActive) {

            return (UIWindowScene *)scene;
        }
    }

    return nil;
}

static void CMSSetup(void) {

    if (gBridgePanel)
        return;

    UIWindowScene *scene =
        CMSForegroundScene();

    if (!scene)
        return;

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

    gBridgeWindow.rootViewController =
        controller;

    gBridgePanel =
        [[CMSBridgePanel alloc]
            initWithFrame:
                CGRectMake(12, 90, 320, 280)];

    [controller.view addSubview:gBridgePanel];

    gBridgeWindow.panel = gBridgePanel;

    gBridgeWindow.hidden = NO;

    [gBridgePanel refresh];

    // Refresh ten times per second.
    // Logger's detection frequency is unchanged.

    NSTimer *timer =
        [NSTimer
            timerWithTimeInterval:kCMSRefreshInterval
            repeats:YES
            block:^(NSTimer *t) {

                if (!gBridgePanel ||
                    gBridgePanel.hidden)
                    return;

                if (UIApplication.sharedApplication
                        .applicationState !=
                    UIApplicationStateActive)
                    return;

                [gBridgePanel refresh];
            }];

    [[NSRunLoop mainRunLoop]
        addTimer:timer
        forMode:NSRunLoopCommonModes];
}

#pragma mark - Startup

__attribute__((constructor))
static void CMSBridgeV17Start(void) {

    dispatch_async(
        dispatch_get_main_queue(), ^{

            const int delays[] = {
                3, 10, 25
            };

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

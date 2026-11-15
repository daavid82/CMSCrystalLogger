
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <string.h>

#pragma mark - CMSCrystalBridge v19

// 10 updates per second.
static const NSTimeInterval kCMSRefresh = 0.1;

// Black background with 35% opacity.
static const CGFloat kCMSBackgroundOpacity = 0.35;

// Only this top strip captures touches.
static const CGFloat kCMSDragHeight = 34.0;

#pragma mark - Text styling

static void CMSStyleLabel(UILabel *label,
                          CGFloat size,
                          BOOL bold,
                          UIColor *color) {

    label.textColor = color;

    label.font = bold
        ? [UIFont boldSystemFontOfSize:size]
        : [UIFont systemFontOfSize:size];

    // Dark shadow makes text readable over the wheel.
    label.layer.shadowColor =
        UIColor.blackColor.CGColor;

    label.layer.shadowOpacity = 1.0;
    label.layer.shadowRadius = 2.0;
    label.layer.shadowOffset =
        CGSizeMake(0, 1);

    label.layer.masksToBounds = NO;

    label.backgroundColor =
        UIColor.clearColor;
}

static void CMSSetText(UILabel *label,
                       NSString *text) {

    if (![label.text isEqualToString:text])
        label.text = text;
}

#pragma mark - Pass-through window

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

    // Outside the panel: pass through.
    if (local.x < 0 ||
        local.x > panel.bounds.size.width ||
        local.y < 0 ||
        local.y > panel.bounds.size.height)
        return nil;

    // Counter area: pass through to the game.
    if (local.y > kCMSDragHeight)
        return nil;

    // Header: allow dragging.
    return [super hitTest:point withEvent:event];
}

@end

#pragma mark - Logger access

static id CMSGetObject(id object,
                       NSString *name) {

    if (!object)
        return nil;

    SEL selector =
        NSSelectorFromString(name);

    NSMethodSignature *signature =
        [object methodSignatureForSelector:selector];

    if (!signature ||
        signature.numberOfArguments != 2 ||
        strcmp(signature.methodReturnType, "@") != 0)
        return nil;

    IMP imp =
        [object methodForSelector:selector];

    if (!imp)
        return nil;

    id (*getter)(id, SEL) =
        (id (*)(id, SEL))imp;

    return getter(object, selector);
}

static BOOL CMSGetInteger(id object,
                          NSString *name,
                          long long *output) {

    if (!object || !output)
        return NO;

    SEL selector =
        NSSelectorFromString(name);

    NSMethodSignature *signature =
        [object methodSignatureForSelector:selector];

    if (!signature ||
        signature.numberOfArguments != 2)
        return NO;

    const char *type =
        signature.methodReturnType;

    if (!type ||
        (strcmp(type, "q") != 0 &&
         strcmp(type, "Q") != 0))
        return NO;

    IMP imp =
        [object methodForSelector:selector];

    if (!imp)
        return NO;

    long long (*getter)(id, SEL) =
        (long long (*)(id, SEL))imp;

    *output = getter(object, selector);

    return YES;
}

static id CMSLogger(void) {

    Class cls =
        objc_getClass("CMSCrystalLogger");

    if (!cls)
        return nil;

    return CMSGetObject(cls, @"shared");
}

static BOOL CMSReadCount(NSDictionary *counts,
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

@property(nonatomic,copy) NSString *name;
@property(nonatomic,copy) NSString *key;

@property(nonatomic,strong) UIColor *color;
@property(nonatomic,strong) UILabel *nameLabel;

@property(nonatomic,strong)
NSArray<UILabel *> *cells;

@property(nonatomic,strong)
NSMutableArray<NSNumber *> *history;

@property(nonatomic,assign) long long observedCount;
@property(nonatomic,assign) long long lastSpin;

@property(nonatomic,assign) BOOL hasBaseline;
@property(nonatomic,assign) BOOL hasOccurrence;

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

    symbol.history =
        [NSMutableArray array];

    return symbol;
}

#pragma mark - Main panel

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

static CMSBridgeWindow *gBridgeWindow = nil;
static CMSBridgePanel *gBridgePanel = nil;

@implementation CMSBridgePanel

- (instancetype)initWithFrame:(CGRect)frame {

    self = [super initWithFrame:frame];

    if (!self)
        return nil;

    self.backgroundColor =
        [[UIColor blackColor]
            colorWithAlphaComponent:
                kCMSBackgroundOpacity];

    self.layer.cornerRadius = 12;
    self.layer.borderWidth = 1.2;

    self.layer.borderColor =
        [[UIColor cyanColor]
            colorWithAlphaComponent:0.9].CGColor;

    self.clipsToBounds = NO;

    self.symbols = @[
        CMSMakeSymbol(
            @"ATTACK",
            @"ATTACK",
            [UIColor colorWithRed:1.0
                           green:0.45
                            blue:0.45
                           alpha:1.0]),

        CMSMakeSymbol(
            @"STEAL",
            @"STEAL",
            [UIColor colorWithRed:1.0
                           green:0.70
                            blue:0.30
                           alpha:1.0]),

        CMSMakeSymbol(
            @"POINT",
            @"POINT",
            [UIColor colorWithRed:1.0
                           green:0.94
                            blue:0.30
                           alpha:1.0]),

        CMSMakeSymbol(
            @"FLASKA",
            @"GREEN_BOTTLE",
            [UIColor colorWithRed:0.40
                           green:1.0
                            blue:0.50
                           alpha:1.0])
    ];

    // Header.

    UILabel *title =
        [[UILabel alloc]
            initWithFrame:
                CGRectMake(12, 7, 280, 24)];

    title.text = @"CMS BRIDGE v19";

    CMSStyleLabel(
        title,
        15,
        YES,
        UIColor.cyanColor);

    [self addSubview:title];

    // Column headers.

    NSArray *headers =
        @[@"SYMBOL", @"NU", @"FÖRRA", @"-2", @"-3"];

    CGFloat x[] = {
        12, 119, 167, 224, 271
    };

    CGFloat widths[] = {
        102, 43, 51, 41, 39
    };

    for (NSUInteger j = 0; j < 5; j++) {

        UILabel *header =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(
                        x[j], 40,
                        widths[j], 20)];

        header.text = headers[j];

        CMSStyleLabel(
            header,
            11,
            YES,
            UIColor.whiteColor);

        header.textAlignment =
            j == 0
                ? NSTextAlignmentLeft
                : NSTextAlignmentRight;

        [self addSubview:header];
    }

    // Four independent symbol rows.

    for (NSUInteger i = 0;
         i < self.symbols.count;
         i++) {

        CMSSymbolState *symbol =
            self.symbols[i];

        CGFloat y = 67 + i * 40;

        UILabel *name =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(12, y, 102, 28)];

        name.text = symbol.name;

        CMSStyleLabel(
            name,
            13,
            YES,
            symbol.color);

        symbol.nameLabel = name;

        [self addSubview:name];

        NSMutableArray<UILabel *> *cells =
            [NSMutableArray array];

        for (NSUInteger j = 1; j < 5; j++) {

            UILabel *cell =
                [[UILabel alloc]
                    initWithFrame:
                        CGRectMake(
                            x[j],
                            y,
                            widths[j],
                            28)];

            cell.text = @"—";

            cell.textAlignment =
                NSTextAlignmentRight;

            UIColor *color =
                j == 1
                    ? UIColor.whiteColor
                    : [UIColor colorWithWhite:0.92
                                       alpha:1.0];

            CMSStyleLabel(
                cell,
                j == 1 ? 19 : 14,
                j == 1,
                color);

            cell.font =
                [UIFont monospacedDigitSystemFontOfSize:
                    j == 1 ? 19 : 14
                    weight:
                    j == 1
                        ? UIFontWeightBold
                        : UIFontWeightSemibold];

            [self addSubview:cell];
            [cells addObject:cell];
        }

        symbol.cells = [cells copy];
    }

    // Separator.

    UIView *separator =
        [[UIView alloc]
            initWithFrame:
                CGRectMake(12, 229, 298, 1)];

    separator.backgroundColor =
        [[UIColor whiteColor]
            colorWithAlphaComponent:0.65];

    [self addSubview:separator];

    // Spin count.

    self.spinLabel =
        [[UILabel alloc]
            initWithFrame:
                CGRectMake(12, 235, 298, 25)];

    self.spinLabel.text = @"Spins ~—";

    CMSStyleLabel(
        self.spinLabel,
        15,
        YES,
        UIColor.cyanColor);

    self.spinLabel.font =
        [UIFont monospacedDigitSystemFontOfSize:15
                                        weight:UIFontWeightBold];

    [self addSubview:self.spinLabel];

    // Status.

    self.statusLabel =
        [[UILabel alloc]
            initWithFrame:
                CGRectMake(12, 265, 298, 20)];

    self.statusLabel.text =
        @"Väntar på Logger";

    CMSStyleLabel(
        self.statusLabel,
        11,
        YES,
        UIColor.whiteColor);

    [self addSubview:self.statusLabel];

    // Dragging is limited to the header.

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

    CGFloat maxX =
        MAX(0,
            self.superview.bounds.size.width -
            frame.size.width);

    CGFloat maxY =
        MAX(0,
            self.superview.bounds.size.height -
            frame.size.height);

    frame.origin.x =
        MAX(0,
            MIN(maxX,
                frame.origin.x + delta.x));

    frame.origin.y =
        MAX(0,
            MIN(maxY,
                frame.origin.y + delta.y));

    self.frame = frame;

    [gesture setTranslation:
        CGPointZero
        inView:self.superview];
}

- (BOOL)gestureRecognizerShouldBegin:
    (UIGestureRecognizer *)gesture {

    if ([gesture
            isKindOfClass:UIPanGestureRecognizer.class]) {

        CGPoint point =
            [gesture locationInView:self];

        return point.y <= kCMSDragHeight;
    }

    return YES;
}

#pragma mark - Refresh counters

- (void)refresh {

    id logger = CMSLogger();

    if (!logger) {

        CMSSetText(
            self.statusLabel,
            @"Logger saknas");

        return;
    }

    id countsObject =
        CMSGetObject(logger, @"counts");

    if (![countsObject
            isKindOfClass:NSDictionary.class]) {

        CMSSetText(
            self.statusLabel,
            @"Väntar på symboldata");

        return;
    }

    NSDictionary *counts =
        [(NSDictionary *)countsObject copy];

    // Read the existing Logger spin estimate.

    long long spins = 0;

    BOOL spinValid =
        CMSGetInteger(
            logger,
            @"estimatedSpins",
            &spins) && spins >= 0;

    if (spinValid) {

        if (self.hasSpin &&
            spins < self.currentSpin) {

            // Spin estimate restarted.
            // Old spin positions cannot be compared.

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

    CMSSetText(self.spinLabel, spinText);

    // Update each symbol independently.

    for (CMSSymbolState *symbol
         in self.symbols) {

        // Bottle detection is not yet implemented
        // by the known Logger version.

        if ([symbol.key
                isEqualToString:@"GREEN_BOTTLE"] &&
            !counts[symbol.key]) {

            for (UILabel *cell in symbol.cells)
                CMSSetText(cell, @"—");

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

            // Establish current counter baseline.
            // Do not invent historical events.

            symbol.observedCount = count;
            symbol.hasBaseline = YES;

        } else if (count < symbol.observedCount) {

            // Logger reset.

            symbol.observedCount = count;
            symbol.hasOccurrence = NO;

            [symbol.history removeAllObjects];

        } else if (count > symbol.observedCount) {

            // New occurrence of THIS symbol only.

            if (self.hasSpin) {

                if (symbol.hasOccurrence) {

                    long long interval =
                        self.currentSpin -
                        symbol.lastSpin;

                    if (interval >= 0) {

                        [symbol.history
                            insertObject:@(interval)
                            atIndex:0];

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

        // NU: elapsed spins since last occurrence.

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

        CMSSetText(
            symbol.cells[0],
            currentText);

        // FÖRRA, -2, -3.

        for (NSUInteger i = 0; i < 3; i++) {

            NSString *value = @"—";

            if (i < symbol.history.count) {

                value =
                    [symbol.history[i]
                        stringValue];
            }

            CMSSetText(
                symbol.cells[i + 1],
                value);
        }
    }

    CMSSetText(
        self.statusLabel,
        counts[@"GREEN_BOTTLE"]
            ? @"10 Hz · touch-through · 35 %"
            : @"10 Hz · flaska ej identifierad");
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
                CGRectMake(12, 90, 322, 294)];

    [controller.view
        addSubview:gBridgePanel];

    gBridgeWindow.panel =
        gBridgePanel;

    gBridgeWindow.hidden = NO;

    [gBridgePanel refresh];

    // Ten UI refreshes per second.
    // This does not speed up Logger's detection.

    NSTimer *timer =
        [NSTimer timerWithTimeInterval:kCMSRefresh
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
static void CMSBridgeV19Start(void) {

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

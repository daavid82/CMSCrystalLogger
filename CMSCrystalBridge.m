
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <string.h>

#pragma mark - CMSCrystalBridge v16

@interface CMSBridgeWindow : UIWindow
@property(nonatomic,weak) UIView *panel;
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

#pragma mark - Logger access

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

    return cls
        ? CMSGetObject(cls, @"shared")
        : nil;
}

static BOOL CMSReadCount(
    NSDictionary *counts,
    NSString *key,
    long long *output) {

    if (!counts || !output) return NO;

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

#pragma mark - Independent symbol state

@interface CMSSymbolState : NSObject

@property(nonatomic,copy) NSString *name;
@property(nonatomic,copy) NSString *key;

@property(nonatomic,strong) UIColor *color;

@property(nonatomic,strong) UILabel *nameLabel;
@property(nonatomic,strong) UILabel *currentLabel;
@property(nonatomic,strong) UILabel *previousLabel;

@property(nonatomic,assign) long long observedCount;
@property(nonatomic,assign) long long lastSpin;
@property(nonatomic,assign) long long previousInterval;

@property(nonatomic,assign) BOOL hasBaseline;
@property(nonatomic,assign) BOOL hasOccurrence;
@property(nonatomic,assign) BOOL hasPreviousInterval;

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
    symbol.hasPreviousInterval = NO;

    return symbol;
}

#pragma mark - Panel

@interface CMSBridgePanel : UIView
<UIGestureRecognizerDelegate>

@property(nonatomic,strong) UILabel *heading;
@property(nonatomic,strong) UILabel *spinLabel;
@property(nonatomic,strong) UILabel *statusLabel;

@property(nonatomic,strong)
NSArray<CMSSymbolState *> *symbols;

@property(nonatomic,assign) long long currentSpin;
@property(nonatomic,assign) BOOL hasSpin;
@property(nonatomic,assign) BOOL loggerReady;

- (void)refresh;

@end

static CMSBridgeWindow *gBridgeWindow = nil;
static CMSBridgePanel *gBridgePanel = nil;

@implementation CMSBridgePanel

- (instancetype)initWithFrame:(CGRect)frame {

    self = [super initWithFrame:frame];

    if (!self) return nil;

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
            @"GRÖN FLASKA",
            @"GREEN_BOTTLE",
            UIColor.systemGreenColor)
    ];

    self.heading =
        [[UILabel alloc]
            initWithFrame:
                CGRectMake(10, 8, 220, 24)];

    self.heading.text = @"CMS BRIDGE v16";

    self.heading.textColor =
        UIColor.cyanColor;

    self.heading.font =
        [UIFont boldSystemFontOfSize:14];

    [self addSubview:self.heading];

    UILabel *nameHeader =
        [[UILabel alloc]
            initWithFrame:
                CGRectMake(10, 37, 112, 17)];

    nameHeader.text = @"SYMBOL";

    nameHeader.textColor =
        UIColor.lightGrayColor;

    nameHeader.font =
        [UIFont systemFontOfSize:10];

    [self addSubview:nameHeader];

    UILabel *currentHeader =
        [[UILabel alloc]
            initWithFrame:
                CGRectMake(122, 37, 45, 17)];

    currentHeader.text = @"NU";

    currentHeader.textAlignment =
        NSTextAlignmentRight;

    currentHeader.textColor =
        UIColor.lightGrayColor;

    currentHeader.font =
        [UIFont systemFontOfSize:10];

    [self addSubview:currentHeader];

    UILabel *previousHeader =
        [[UILabel alloc]
            initWithFrame:
                CGRectMake(174, 37, 56, 17)];

    previousHeader.text = @"FÖRRA";

    previousHeader.textAlignment =
        NSTextAlignmentRight;

    previousHeader.textColor =
        UIColor.lightGrayColor;

    previousHeader.font =
        [UIFont systemFontOfSize:10];

    [self addSubview:previousHeader];

    for (NSUInteger i = 0;
         i < self.symbols.count;
         i++) {

        CMSSymbolState *symbol =
            self.symbols[i];

        CGFloat y = 59 + i * 38;

        symbol.nameLabel =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(10, y, 112, 28)];

        symbol.nameLabel.text =
            symbol.name;

        symbol.nameLabel.textColor =
            symbol.color;

        symbol.nameLabel.font =
            [UIFont boldSystemFontOfSize:12];

        [self addSubview:symbol.nameLabel];

        symbol.currentLabel =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(122, y, 45, 28)];

        symbol.currentLabel.text = @"—";

        symbol.currentLabel.textAlignment =
            NSTextAlignmentRight;

        symbol.currentLabel.textColor =
            UIColor.whiteColor;

        symbol.currentLabel.font =
            [UIFont monospacedDigitSystemFontOfSize:17
                                            weight:UIFontWeightBold];

        [self addSubview:symbol.currentLabel];

        symbol.previousLabel =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(174, y, 56, 28)];

        symbol.previousLabel.text = @"—";

        symbol.previousLabel.textAlignment =
            NSTextAlignmentRight;

        symbol.previousLabel.textColor =
            UIColor.lightGrayColor;

        symbol.previousLabel.font =
            [UIFont monospacedDigitSystemFontOfSize:14
                                            weight:UIFontWeightRegular];

        [self addSubview:symbol.previousLabel];
    }

    UIView *line =
        [[UIView alloc]
            initWithFrame:
                CGRectMake(10, 213, 220, 1)];

    line.backgroundColor =
        [UIColor darkGrayColor];

    [self addSubview:line];

    self.spinLabel =
        [[UILabel alloc]
            initWithFrame:
                CGRectMake(10, 220, 220, 24)];

    self.spinLabel.text =
        @"Spins ~—";

    self.spinLabel.textColor =
        UIColor.cyanColor;

    self.spinLabel.font =
        [UIFont monospacedDigitSystemFontOfSize:13
                                        weight:UIFontWeightMedium];

    [self addSubview:self.spinLabel];

    self.statusLabel =
        [[UILabel alloc]
            initWithFrame:
                CGRectMake(10, 247, 220, 22)];

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

#pragma mark - Counter updates

- (void)refresh {

    id logger = CMSLogger();

    if (!logger) {

        self.loggerReady = NO;

        self.statusLabel.text =
            @"Logger saknas";

        return;
    }

    id countsObject =
        CMSGetObject(logger, @"counts");

    if (![countsObject
            isKindOfClass:NSDictionary.class]) {

        self.loggerReady = NO;

        self.statusLabel.text =
            @"Väntar på symboldata";

        return;
    }

    NSDictionary *counts =
        [(NSDictionary *)countsObject copy];

    long long spins = 0;

    BOOL validSpin =
        CMSGetInteger(
            logger,
            @"estimatedSpins",
            &spins);

    if (validSpin && spins >= 0) {

        if (self.hasSpin &&
            spins < self.currentSpin) {

            // Logger restarted its spin estimate.
            // Old spin positions are no longer valid.
            for (CMSSymbolState *symbol
                 in self.symbols) {

                symbol.hasOccurrence = NO;
                symbol.hasPreviousInterval = NO;
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

        // A missing bottle key is not evidence
        // that the bottle count is zero.
        if ([symbol.key
                isEqualToString:@"GREEN_BOTTLE"] &&
            !counts[symbol.key]) {

            symbol.currentLabel.text = @"—";
            symbol.previousLabel.text = @"—";
            symbol.hasBaseline = NO;
            symbol.hasOccurrence = NO;
            continue;
        }

        long long count = 0;

        if (!CMSReadCount(
                counts,
                symbol.key,
                &count)) {

            symbol.currentLabel.text = @"—";
            continue;
        }

        if (!symbol.hasBaseline) {

            // First observation: do not pretend
            // an old symbol occurred just now.
            symbol.observedCount = count;
            symbol.hasBaseline = YES;

        } else if (count < symbol.observedCount) {

            // Logger counters were reset.
            symbol.observedCount = count;
            symbol.hasOccurrence = NO;
            symbol.hasPreviousInterval = NO;

        } else if (count > symbol.observedCount) {

            // Only THIS symbol is reset.
            // All other symbols remain unchanged.

            if (self.hasSpin) {

                if (symbol.hasOccurrence) {

                    long long interval =
                        self.currentSpin -
                        symbol.lastSpin;

                    if (interval >= 0) {

                        symbol.previousInterval =
                            interval;

                        symbol.hasPreviousInterval =
                            YES;
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

        NSString *previousText =
            symbol.hasPreviousInterval
                ? [NSString stringWithFormat:
                    @"%lld",
                    symbol.previousInterval]
                : @"—";

        if (![symbol.currentLabel.text
                isEqualToString:currentText]) {

            symbol.currentLabel.text =
                currentText;
        }

        if (![symbol.previousLabel.text
                isEqualToString:previousText]) {

            symbol.previousLabel.text =
                previousText;
        }
    }

    self.loggerReady = YES;

    self.statusLabel.text =
        counts[@"GREEN_BOTTLE"]
            ? @"Räknare aktiva · uppskattade spins"
            : @"Grön flaska väntar på identifiering";
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

    if (gBridgePanel) return;

    UIWindowScene *scene =
        CMSForegroundScene();

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

    gBridgeWindow.rootViewController =
        controller;

    gBridgePanel =
        [[CMSBridgePanel alloc]
            initWithFrame:
                CGRectMake(12, 90, 240, 280)];

    [controller.view addSubview:gBridgePanel];

    gBridgeWindow.panel =
        gBridgePanel;

    gBridgeWindow.hidden = NO;

    [gBridgePanel refresh];

    // Five UI checks per second.
    // This does not change Logger's own
    // underlying spin detection rate.
    NSTimer *timer =
        [NSTimer timerWithTimeInterval:0.2
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
static void CMSBridgeV16Start(void) {

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

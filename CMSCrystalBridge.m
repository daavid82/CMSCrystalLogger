
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

#pragma mark - CMSCrystalBridge v12

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

#pragma mark - Globals

static CMSBridgeWindow *gWindow = nil;

@class CMSBridgePanel;
static CMSBridgePanel *gPanel = nil;

static void CMSRefresh(void);

#pragma mark - Panel

@interface CMSBridgePanel : UIView
<UIGestureRecognizerDelegate>

@property(nonatomic,strong) UIButton *toggleButton;
@property(nonatomic,strong) UIButton *refreshButton;
@property(nonatomic,strong) UIButton *dataButton;
@property(nonatomic,strong) UITextView *details;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,copy) NSString *fullReport;
@property(nonatomic,assign) BOOL expanded;

@end

@implementation CMSBridgePanel

- (instancetype)initWithFrame:(CGRect)frame {

    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor =
        [[UIColor blackColor]
            colorWithAlphaComponent:0.94];

    self.layer.cornerRadius = 10;
    self.layer.borderWidth = 1;
    self.layer.borderColor =
        UIColor.cyanColor.CGColor;

    self.clipsToBounds = YES;
    self.expanded = NO;
    self.fullReport = @"";

    self.toggleButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    self.toggleButton.frame =
        CGRectMake(0, 0, 190, 38);

    [self.toggleButton
        setTitle:@"CMS Bridge v12 +"
        forState:UIControlStateNormal];

    [self.toggleButton
        setTitleColor:UIColor.whiteColor
        forState:UIControlStateNormal];

    self.toggleButton.titleLabel.font =
        [UIFont boldSystemFontOfSize:13];

    [self.toggleButton
        addTarget:self
        action:@selector(togglePanel)
        forControlEvents:UIControlEventTouchUpInside];

    [self addSubview:self.toggleButton];

    self.details =
        [[UITextView alloc]
            initWithFrame:CGRectMake(8, 43, 308, 205)];

    self.details.backgroundColor =
        UIColor.clearColor;

    self.details.textColor =
        UIColor.whiteColor;

    self.details.font =
        [UIFont monospacedSystemFontOfSize:11
            weight:UIFontWeightRegular];

    self.details.editable = NO;
    self.details.selectable = YES;
    self.details.scrollEnabled = YES;
    self.details.hidden = YES;

    [self addSubview:self.details];

    self.refreshButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    self.refreshButton.frame =
        CGRectMake(12, 255, 300, 40);

    self.refreshButton.backgroundColor =
        [UIColor colorWithRed:0.10
                        green:0.35
                         blue:0.65
                        alpha:1.0];

    self.refreshButton.layer.cornerRadius = 8;

    [self.refreshButton
        setTitle:@"UPPDATERA RÄKNARE"
        forState:UIControlStateNormal];

    [self.refreshButton
        setTitleColor:UIColor.whiteColor
        forState:UIControlStateNormal];

    [self.refreshButton
        addTarget:self
        action:@selector(refreshData)
        forControlEvents:UIControlEventTouchUpInside];

    self.refreshButton.hidden = YES;

    [self addSubview:self.refreshButton];

    self.dataButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    self.dataButton.frame =
        CGRectMake(12, 302, 300, 40);

    self.dataButton.backgroundColor =
        [UIColor colorWithRed:0.10
                        green:0.55
                         blue:0.25
                        alpha:1.0];

    self.dataButton.layer.cornerRadius = 8;

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
            initWithFrame:CGRectMake(12, 347, 300, 20)];

    self.statusLabel.textColor =
        UIColor.whiteColor;

    self.statusLabel.font =
        [UIFont systemFontOfSize:11];

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

- (void)togglePanel {

    self.expanded = !self.expanded;

    CGRect frame = self.frame;

    frame.size = self.expanded
        ? CGSizeMake(324, 375)
        : CGSizeMake(190, 38);

    if (self.superview) {

        CGFloat maxX = MAX(
            0,
            self.superview.bounds.size.width -
            frame.size.width
        );

        CGFloat maxY = MAX(
            0,
            self.superview.bounds.size.height -
            frame.size.height
        );

        frame.origin.x =
            MAX(0, MIN(frame.origin.x, maxX));

        frame.origin.y =
            MAX(0, MIN(frame.origin.y, maxY));
    }

    self.frame = frame;

    self.details.hidden = !self.expanded;
    self.refreshButton.hidden = !self.expanded;
    self.dataButton.hidden = !self.expanded;
    self.statusLabel.hidden = !self.expanded;

    [self.toggleButton
        setTitle:self.expanded
            ? @"CMS Bridge v12 -"
            : @"CMS Bridge v12 +"
        forState:UIControlStateNormal];
}

- (void)refreshData {
    self.statusLabel.text = @"Läser Logger...";
    CMSRefresh();
}

- (void)exportData {

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

- (void)drag:(UIPanGestureRecognizer *)gesture {

    if (!self.superview) return;

    CGPoint delta =
        [gesture translationInView:self.superview];

    CGRect frame = self.frame;

    CGFloat maxX = MAX(
        0,
        self.superview.bounds.size.width -
        frame.size.width
    );

    CGFloat maxY = MAX(
        0,
        self.superview.bounds.size.height -
        frame.size.height
    );

    frame.origin.x = MAX(
        0,
        MIN(frame.origin.x + delta.x, maxX)
    );

    frame.origin.y = MAX(
        0,
        MIN(frame.origin.y + delta.y, maxY)
    );

    self.frame = frame;

    [gesture setTranslation:
        CGPointZero
        inView:self.superview];
}

- (BOOL)gestureRecognizerShouldBegin:
    (UIGestureRecognizer *)gestureRecognizer {

    if ([gestureRecognizer isKindOfClass:
            UIPanGestureRecognizer.class]) {

        CGPoint point =
            [gestureRecognizer locationInView:self];

        return point.y <= 38;
    }

    return YES;
}

@end

#pragma mark - Setup

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

static void CMSSetupPanel(void) {

    if (gPanel) return;

    UIWindowScene *scene = CMSForegroundScene();

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
            initWithFrame:CGRectMake(12, 90, 190, 38)];

    [controller.view addSubview:gPanel];

    gWindow.panel = gPanel;
    gWindow.hidden = NO;
}

#pragma mark - Logger access

static id CMSReadObject(id object, NSString *name) {

    if (!object) return nil;

    SEL selector = NSSelectorFromString(name);

    NSMethodSignature *signature =
        [object methodSignatureForSelector:selector];

    if (!signature ||
        signature.numberOfArguments != 2 ||
        signature.methodReturnType[0] != '@') {

        return nil;
    }

    IMP implementation =
        [object methodForSelector:selector];

    if (!implementation) return nil;

    id (*getter)(id, SEL) =
        (id (*)(id, SEL))implementation;

    return getter(object, selector);
}

static BOOL CMSReadInteger(
    id object,
    NSString *name,
    long long *value) {

    if (!object || !value) return NO;

    SEL selector = NSSelectorFromString(name);

    NSMethodSignature *signature =
        [object methodSignatureForSelector:selector];

    if (!signature ||
        signature.numberOfArguments != 2) {

        return NO;
    }

    const char *type = signature.methodReturnType;

    if (!type || (type[0] != 'q' &&
                  type[0] != 'Q')) {

        return NO;
    }

    IMP implementation =
        [object methodForSelector:selector];

    if (!implementation) return NO;

    long long (*getter)(id, SEL) =
        (long long (*)(id, SEL))implementation;

    *value = getter(object, selector);

    return YES;
}

static id CMSFindLogger(void) {

    Class loggerClass =
        objc_getClass("CMSCrystalLogger");

    if (!loggerClass) return nil;

    return CMSReadObject(
        loggerClass,
        @"shared"
    );
}

#pragma mark - Formatting

static NSString *CMSValue(id value) {

    if (!value) return @"nil";

    if ([value isKindOfClass:NSString.class]) {
        return value;
    }

    if ([value isKindOfClass:NSNumber.class]) {
        return [value stringValue];
    }

    return NSStringFromClass([value class]);
}

static NSString *CMSCount(
    NSDictionary *counts,
    NSString *symbol) {

    if (!counts) return @"N/A";

    id value = counts[symbol];

    if (!value) return @"0";

    return CMSValue(value);
}

static void CMSAppendLogs(
    NSMutableString *report,
    id logsObject) {

    [report appendString:
        @"\n=== LOGGER LOGS ===\n"];

    if (![logsObject isKindOfClass:NSArray.class]) {

        [report appendFormat:
            @"TYPE: %@\n",
            logsObject
                ? NSStringFromClass([logsObject class])
                : @"nil"];

        return;
    }

    NSArray *logs = [(NSArray *)logsObject copy];

    [report appendFormat:
        @"COUNT: %lu\n",
        (unsigned long)logs.count];

    NSUInteger limit = MIN(logs.count, 15);

    NSUInteger start = logs.count - limit;

    for (NSUInteger i = start;
         i < logs.count;
         i++) {

        NSString *line = CMSValue(logs[i]);

        if (line.length > 240) {
            line = [[line substringToIndex:240]
                stringByAppendingString:@"..."];
        }

        [report appendFormat:
            @"[%lu] %@\n",
            (unsigned long)i,
            line];
    }
}

#pragma mark - Main inspection

static void CMSRefresh(void) {

    CMSSetupPanel();

    NSMutableString *report =
        [NSMutableString stringWithString:
            @"CMSCrystalBridge v12\n"
             "LOGGER LIVE COUNTER\n\n"];

    Class loggerClass =
        objc_getClass("CMSCrystalLogger");

    [report appendFormat:
        @"LOGGER CLASS: %@\n",
        loggerClass ? @"FOUND" : @"NOT FOUND"];

    if (!loggerClass) {

        [report appendString:
            @"\nCMSCrystalLogger is not loaded.\n"
             "Install and load Logger dylib.\n"];

    } else {

        id logger = CMSFindLogger();

        [report appendFormat:
            @"LOGGER INSTANCE: %@\n",
            logger ? @"FOUND" : @"NOT FOUND"];

        if (logger) {

            id countsObject =
                CMSReadObject(logger, @"counts");

            id lastSymbol =
                CMSReadObject(logger, @"lastSymbol");

            id logs =
                CMSReadObject(logger, @"logs");

            NSDictionary *counts = nil;

            if ([countsObject
                    isKindOfClass:NSDictionary.class]) {

                counts =
                    [(NSDictionary *)countsObject copy];
            }

            [report appendString:
                @"\n=== SYMBOL COUNTER ===\n"];

            [report appendFormat:
                @"ATTACK: %@\n",
                CMSCount(counts, @"ATTACK")];

            [report appendFormat:
                @"STEAL: %@\n",
                CMSCount(counts, @"STEAL")];

            [report appendFormat:
                @"SHIELD: %@\n",
                CMSCount(counts, @"SHIELD")];

            [report appendFormat:
                @"POINT: %@\n",
                CMSCount(counts, @"POINT")];

            [report appendFormat:
                @"\nLAST SYMBOL: %@\n",
                CMSValue(lastSymbol)];

            if (counts) {

                [report appendString:
                    @"\n=== ALL COUNT KEYS ===\n"];

                NSArray *keys =
                    [[counts allKeys]
                        sortedArrayUsingComparator:
                        ^NSComparisonResult(
                            id a, id b) {

                            return [[a description]
                                compare:[b description]];
                        }];

                for (id key in keys) {

                    [report appendFormat:
                        @"%@: %@\n",
                        CMSValue(key),
                        CMSValue(counts[key])];
                }

            } else {

                [report appendString:
                    @"COUNTS: NOT DICTIONARY\n"];
            }

            long long estimatedSpins = 0;
            long long spinCandidates = 0;

            BOOL hasEstimated =
                CMSReadInteger(
                    logger,
                    @"estimatedSpins",
                    &estimatedSpins
                );

            BOOL hasCandidates =
                CMSReadInteger(
                    logger,
                    @"spinCandidates",
                    &spinCandidates
                );

            [report appendString:
                @"\n=== SPIN DATA ===\n"];

            if (hasEstimated) {

                [report appendFormat:
                    @"ESTIMATED SPINS: %lld\n",
                    estimatedSpins];

            } else {

                [report appendString:
                    @"ESTIMATED SPINS: N/A\n"];
            }

            if (hasCandidates) {

                [report appendFormat:
                    @"SPIN CANDIDATES: %lld\n",
                    spinCandidates];

            } else {

                [report appendString:
                    @"SPIN CANDIDATES: N/A\n"];
            }

            CMSAppendLogs(report, logs);
        }
    }

    [report appendString:
        @"\n=== STATUS ===\n"
         "Logger read-only snapshot\n"
         "No Logger counters modified\n"
         "No RS functions called\n"
         "Raid stack not yet verified\n"
         "AutoSpeed unchanged\n"];

    NSLog(@"[CMSBridgeV12] %@", report);

    if (gPanel) {

        gPanel.fullReport = [report copy];

        gPanel.details.text = report;

        [gPanel.details
            setContentOffset:CGPointZero
            animated:NO];

        [gPanel.dataButton
            setTitle:@"KOPIERA ALL DATA"
            forState:UIControlStateNormal];

        gPanel.statusLabel.text =
            @"Logger snapshot klar";
    }
}

#pragma mark - Startup

__attribute__((constructor))
static void CMSBridgeV12Start(void) {

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

                    CMSRefresh();
                });
        }
    });
}

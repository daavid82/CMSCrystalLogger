
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>

#pragma mark - Window

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

#pragma mark - Panel

@interface CMSBridgePanel : UIView
<UIGestureRecognizerDelegate>

@property(nonatomic, strong) UIButton *toggleButton;
@property(nonatomic, strong) UIButton *refreshButton;
@property(nonatomic, strong) UIButton *dataButton;
@property(nonatomic, strong) UITextView *details;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, copy) NSString *fullReport;
@property(nonatomic, assign) BOOL expanded;

@end

static CMSBridgeWindow *gWindow = nil;
static CMSBridgePanel *gPanel = nil;

static void CMSInspect(void);

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

    self.fullReport = @"";
    self.expanded = NO;

    self.toggleButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    self.toggleButton.frame =
        CGRectMake(0, 0, 190, 38);

    [self.toggleButton
        setTitle:@"CMS Bridge v11 +"
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
        CGRectMake(12, 255, 300, 40);

    self.refreshButton.backgroundColor =
        [UIColor colorWithRed:0.10
                        green:0.35
                         blue:0.65
                        alpha:1.0];

    self.refreshButton.layer.cornerRadius = 8;

    [self.refreshButton
        setTitle:@"UPPDATERA DATA"
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
            ? @"CMS Bridge v11 -"
            : @"CMS Bridge v11 +"
        forState:UIControlStateNormal];
}

- (void)refreshData {
    self.statusLabel.text = @"Läser data...";
    CMSInspect();
}

- (void)exportData {

    if (self.fullReport.length == 0) {
        self.statusLabel.text = @"Ingen data ännu";
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

#pragma mark - Safe data helpers

static NSString *CMSTypeName(id object) {

    if (!object) return @"nil";

    return NSStringFromClass([object class]);
}

static NSString *CMSPreview(id object) {

    if (!object) return @"nil";

    if ([object isKindOfClass:NSString.class]) {

        NSString *value = (NSString *)object;

        if (value.length > 160) {
            return [[value substringToIndex:160]
                stringByAppendingString:@"..."];
        }

        return value;
    }

    if ([object isKindOfClass:NSNumber.class]) {
        return [(NSNumber *)object stringValue];
    }

    if ([object isKindOfClass:NSNull.class]) {
        return @"NSNull";
    }

    if ([object isKindOfClass:NSArray.class]) {

        return [NSString stringWithFormat:
            @"Array count=%lu",
            (unsigned long)[(NSArray *)object count]];
    }

    if ([object isKindOfClass:NSDictionary.class]) {

        return [NSString stringWithFormat:
            @"Dictionary count=%lu",
            (unsigned long)[(NSDictionary *)object count]];
    }

    return @"(object preview skipped)";
}

static void CMSDescribeArray(
    NSString *name,
    id object,
    NSMutableString *report) {

    [report appendFormat:
        @"\n=== %@ ===\nCLASS: %@\n",
        name,
        CMSTypeName(object)];

    if (![object isKindOfClass:NSArray.class]) {
        [report appendString:@"NOT ARRAY\n"];
        return;
    }

    NSArray *array = (NSArray *)object;

    [report appendFormat:
        @"COUNT: %lu\n",
        (unsigned long)array.count];

    NSUInteger limit = MIN(array.count, 12);

    for (NSUInteger i = 0; i < limit; i++) {

        id item = array[i];

        [report appendFormat:
            @"[%lu] %@ | %@\n",
            (unsigned long)i,
            CMSTypeName(item),
            CMSPreview(item)];

        if ([item isKindOfClass:NSArray.class]) {

            NSArray *nested = (NSArray *)item;

            NSUInteger nestedLimit =
                MIN(nested.count, 8);

            for (NSUInteger j = 0;
                 j < nestedLimit;
                 j++) {

                id value = nested[j];

                [report appendFormat:
                    @"    [%lu] %@ | %@\n",
                    (unsigned long)j,
                    CMSTypeName(value),
                    CMSPreview(value)];
            }
        }
    }

    if (array.count > limit) {
        [report appendFormat:
            @"... %lu fler poster\n",
            (unsigned long)(array.count - limit)];
    }
}

#pragma mark - Widget discovery

static void CMSFindWidgets(
    UIView *view,
    Class targetClass,
    NSMutableArray *results,
    NSUInteger depth) {

    if (!view || depth > 30 ||
        results.count >= 10) {
        return;
    }

    if ([view isKindOfClass:targetClass]) {
        [results addObject:view];
    }

    for (UIView *child in view.subviews) {

        CMSFindWidgets(
            child,
            targetClass,
            results,
            depth + 1
        );

        if (results.count >= 10) {
            break;
        }
    }
}

static id CMSReadProperty(
    id object,
    NSString *propertyName) {

    if (!object) return nil;

    SEL selector =
        NSSelectorFromString(propertyName);

    if (![object respondsToSelector:selector]) {
        return nil;
    }

    // Only object-returning, zero-argument getters
    // confirmed in the v10 runtime report.
    IMP implementation =
        [object methodForSelector:selector];

    if (!implementation) return nil;

    id (*getter)(id, SEL) =
        (id (*)(id, SEL))implementation;

    return getter(object, selector);
}

#pragma mark - Inspection

static void CMSInspect(void) {

    CMSSetupPanel();

    NSMutableString *report =
        [NSMutableString stringWithString:
            @"CMSCrystalBridge v11\n"
             "READ-ONLY LIVE SNAPSHOT\n\n"];

    [report appendFormat:
        @"LADDADE BILDER: %u\n",
        _dyld_image_count()];

    const char *symbols[] = {
        "RS_GetTripleHistoryForSymbol",
        "RS_ResetTripleHistoryForSymbol",
        "RS_ResetTripleHistory",
        "RS_GetTargetSpinSymbol",
        "RS_SetTargetSpinSymbol"
    };

    NSUInteger foundSymbols = 0;

    for (NSUInteger i = 0; i < 5; i++) {

        if (dlsym(RTLD_DEFAULT, symbols[i])) {
            foundSymbols++;
        }
    }

    [report appendFormat:
        @"RS SYMBOLS: %lu/5\n",
        (unsigned long)foundSymbols];

    Class targetClass =
        objc_getClass("VIPCronologiaWidget");

    if (!targetClass) {

        [report appendString:
            @"VIPCronologiaWidget: NOT FOUND\n"];

    } else {

        [report appendString:
            @"VIPCronologiaWidget: FOUND\n"];

        NSMutableArray *widgets =
            [NSMutableArray array];

        UIWindowScene *scene =
            CMSForegroundScene();

        if (scene) {

            for (UIWindow *window in scene.windows) {

                if (window == gWindow) {
                    continue;
                }

                CMSFindWidgets(
                    window,
                    targetClass,
                    widgets,
                    0
                );
            }
        }

        [report appendFormat:
            @"ACTIVE WIDGETS: %lu\n",
            (unsigned long)widgets.count];

        NSUInteger index = 0;

        for (id widget in widgets) {

            [report appendFormat:
                @"\n========== WIDGET %lu ==========\n",
                (unsigned long)index];

            id columnData =
                CMSReadProperty(widget, @"columnData");

            id columnCountLabels =
                CMSReadProperty(
                    widget,
                    @"columnCountLabels"
                );

            id columnCards =
                CMSReadProperty(widget, @"columnCards");

            CMSDescribeArray(
                @"columnData",
                columnData,
                report
            );

            CMSDescribeArray(
                @"columnCountLabels",
                columnCountLabels,
                report
            );

            CMSDescribeArray(
                @"columnCards",
                columnCards,
                report
            );

            if ([columnCountLabels
                    isKindOfClass:NSArray.class]) {

                NSArray *labels =
                    (NSArray *)columnCountLabels;

                [report appendString:
                    @"\n=== LABEL TEXT ===\n"];

                NSUInteger limit =
                    MIN(labels.count, 20);

                for (NSUInteger i = 0;
                     i < limit;
                     i++) {

                    id item = labels[i];

                    if ([item
                            isKindOfClass:UILabel.class]) {

                        UILabel *label =
                            (UILabel *)item;

                        [report appendFormat:
                            @"[%lu] %@\n",
                            (unsigned long)i,
                            label.text ?: @"(empty)"];
                    } else {

                        [report appendFormat:
                            @"[%lu] NOT UILabel: %@\n",
                            (unsigned long)i,
                            CMSTypeName(item)];
                    }
                }
            }

            index++;
        }
    }

    [report appendString:
        @"\n=== STATUS ===\n"
         "Snapshot only\n"
         "No game state modifications\n"
         "No RS functions called\n"
         "AutoSpeed unchanged\n"];

    NSLog(@"[CMSBridgeV11] %@", report);

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
            @"Snapshot klar";
    }
}

#pragma mark - Startup

__attribute__((constructor))
static void CMSBridgeV11Start(void) {

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

                    CMSInspect();
                });
        }
    });
}

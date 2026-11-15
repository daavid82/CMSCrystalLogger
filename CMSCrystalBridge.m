
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import <stdlib.h>

// CMSCrystalBridge v9
// Read-only diagnostics with copy-all button.

static const char *const kSymbols[] = {
    "RS_GetTripleHistoryForSymbol",
    "RS_ResetTripleHistoryForSymbol",
    "RS_ResetTripleHistory",
    "RS_GetTargetSpinSymbol",
    "RS_SetTargetSpinSymbol"
};

#pragma mark - Pass-through window

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

#pragma mark - Diagnostic panel

@interface CMSBridgePanel : UIView
    <UIGestureRecognizerDelegate>

@property(nonatomic, strong) UITextView *details;
@property(nonatomic, strong) UIButton *toggle;
@property(nonatomic, strong) UIButton *copyDataButton;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, copy) NSString *fullReport;
@property(nonatomic, assign) BOOL expanded;

@end

@implementation CMSBridgePanel

- (instancetype)initWithFrame:(CGRect)frame {

    if ((self = [super initWithFrame:frame])) {

        self.backgroundColor =
            [[UIColor blackColor]
                colorWithAlphaComponent:0.92];

        self.layer.cornerRadius = 10;
        self.layer.borderWidth = 1;
        self.layer.borderColor =
            UIColor.cyanColor.CGColor;

        self.clipsToBounds = YES;
        self.expanded = NO;
        self.fullReport = @"";

        self.toggle =
            [UIButton buttonWithType:
                UIButtonTypeSystem];

        self.toggle.frame =
            CGRectMake(0, 0, 190, 38);

        [self.toggle
            setTitle:@"CMS Bridge v9 +"
            forState:UIControlStateNormal];

        [self.toggle
            setTitleColor:UIColor.whiteColor
            forState:UIControlStateNormal];

        self.toggle.titleLabel.font =
            [UIFont boldSystemFontOfSize:13];

        [self.toggle
            addTarget:self
            action:@selector(togglePanel)
            forControlEvents:
                UIControlEventTouchUpInside];

        [self addSubview:self.toggle];

        self.details =
            [[UITextView alloc]
                initWithFrame:
                    CGRectMake(8, 42, 308, 225)];

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

        self.copyDataButton =
            [UIButton buttonWithType:
                UIButtonTypeSystem];

        self.copyDataButton.frame =
            CGRectMake(12, 275, 300, 42);

        self.copyDataButton.backgroundColor =
            [UIColor colorWithRed:0.10
                            green:0.55
                             blue:0.25
                            alpha:1.0];

        self.copyDataButton.layer.cornerRadius = 8;

        [self.copyDataButton
            setTitle:@"KOPIERA ALL DATA"
            forState:UIControlStateNormal];

        [self.copyDataButton
            setTitleColor:UIColor.whiteColor
            forState:UIControlStateNormal];

        self.copyDataButton.titleLabel.font =
            [UIFont boldSystemFontOfSize:14];

        [self.copyDataButton
            addTarget:self
            action:@selector(copyAllData)
            forControlEvents:
                UIControlEventTouchUpInside];

        self.copyDataButton.hidden = YES;

        [self addSubview:self.copyDataButton];

        self.statusLabel =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(12, 320, 300, 18)];

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
    }

    return self;
}

- (void)togglePanel {

    self.expanded = !self.expanded;

    CGRect frame = self.frame;

    frame.size =
        self.expanded
            ? CGSizeMake(324, 345)
            : CGSizeMake(190, 38);

    if (self.superview) {

        CGFloat maxX =
            MAX(0,
                self.superview.bounds.size.width -
                frame.size.width);

        CGFloat maxY =
            MAX(0,
                self.superview.bounds.size.height -
                frame.size.height);

        frame.origin.x =
            MAX(0, MIN(frame.origin.x, maxX));

        frame.origin.y =
            MAX(0, MIN(frame.origin.y, maxY));
    }

    self.frame = frame;

    self.details.hidden = !self.expanded;
    self.copyDataButton.hidden = !self.expanded;
    self.statusLabel.hidden = !self.expanded;

    [self.toggle
        setTitle:
            self.expanded
                ? @"CMS Bridge v9 -"
                : @"CMS Bridge v9 +"
        forState:UIControlStateNormal];
}

- (void)copyAllData {

    NSString *report = self.fullReport;

    if (report.length == 0) {
        self.statusLabel.text = @"Ingen data ännu";
        return;
    }

    [UIPasteboard generalPasteboard].string = report;

    self.statusLabel.text =
        [NSString stringWithFormat:
            @"Kopierat! %lu tecken",
            (unsigned long)report.length];

    [self.copyDataButton
        setTitle:@"KOPIERAT!"
        forState:UIControlStateNormal];
}

- (void)drag:(UIPanGestureRecognizer *)gesture {

    if (!self.superview) return;

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
            MIN(frame.origin.x + delta.x, maxX));

    frame.origin.y =
        MAX(0,
            MIN(frame.origin.y + delta.y, maxY));

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

static CMSBridgeWindow *gWindow = nil;
static CMSBridgePanel *gPanel = nil;

static UIWindowScene *CMSForegroundScene(void) {

    for (UIScene *scene in
         UIApplication.sharedApplication.connectedScenes) {

        if ([scene isKindOfClass:
                UIWindowScene.class] &&
            scene.activationState ==
                UISceneActivationStateForegroundActive) {

            return (UIWindowScene *)scene;
        }
    }

    return nil;
}

static void CMSSetupPanel(void) {

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
                CGRectMake(12, 90, 190, 38)];

    [controller.view addSubview:gPanel];

    gWindow.panel = gPanel;
    gWindow.hidden = NO;
}

#pragma mark - Helpers

static NSString *CMSString(const char *value) {

    if (!value) return @"?";

    NSString *result =
        [NSString stringWithUTF8String:value];

    return result ?: @"?";
}

static BOOL CMSInterestingName(NSString *name) {

    NSString *lower = name.lowercaseString;

    NSArray<NSString *> *terms = @[
        @"history",
        @"symbol",
        @"column",
        @"count",
        @"refresh",
        @"raid",
        @"spin",
        @"triple",
        @"load",
        @"update"
    ];

    for (NSString *term in terms) {

        if ([lower containsString:term])
            return YES;
    }

    return NO;
}

#pragma mark - Properties

static void CMSInspectProperties(
    Class cls,
    NSMutableString *report) {

    unsigned int count = 0;

    objc_property_t *properties =
        class_copyPropertyList(cls, &count);

    [report appendFormat:
        @"\n=== EGENSKAPER: %u ===\n",
        count];

    for (unsigned int i = 0; i < count; i++) {

        [report appendFormat:
            @"%@\n  %@\n",
            CMSString(property_getName(properties[i])),
            CMSString(property_getAttributes(properties[i]))];
    }

    free(properties);
}

#pragma mark - Ivars

static void CMSInspectIvars(
    Class cls,
    NSMutableString *report) {

    unsigned int count = 0;

    Ivar *ivars =
        class_copyIvarList(cls, &count);

    [report appendFormat:
        @"\n=== INSTANSVARIABLER: %u ===\n",
        count];

    for (unsigned int i = 0; i < count; i++) {

        [report appendFormat:
            @"%@ : %@\n",
            CMSString(ivar_getName(ivars[i])),
            CMSString(ivar_getTypeEncoding(ivars[i]))];
    }

    free(ivars);
}

#pragma mark - Methods

static void CMSInspectMethods(
    Class cls,
    NSMutableString *report) {

    unsigned int count = 0;

    Method *methods =
        class_copyMethodList(cls, &count);

    [report appendFormat:
        @"\n=== METODER TOTALT: %u ===\n",
        count];

    NSUInteger matches = 0;

    for (unsigned int i = 0; i < count; i++) {

        Method method = methods[i];

        NSString *name =
            NSStringFromSelector(
                method_getName(method));

        if (!CMSInterestingName(name))
            continue;

        matches++;

        [report appendFormat:
            @"\nMETOD: %@\n"
             "ENCODING: %@\n",
            name,
            CMSString(method_getTypeEncoding(method))];

        unsigned int arguments =
            method_getNumberOfArguments(method);

        [report appendFormat:
            @"ARGUMENT: %u\n",
            arguments];

        for (unsigned int a = 0;
             a < arguments;
             a++) {

            char *type =
                method_copyArgumentType(method, a);

            [report appendFormat:
                @"  arg%u = %@\n",
                a,
                CMSString(type)];

            free(type);
        }

        char *returnType =
            method_copyReturnType(method);

        [report appendFormat:
            @"RETURN = %@\n",
            CMSString(returnType)];

        free(returnType);
    }

    [report appendFormat:
        @"\nMATCHANDE METODER: %lu\n",
        (unsigned long)matches];

    free(methods);
}

#pragma mark - Class hierarchy

static void CMSInspectHierarchy(
    Class cls,
    NSMutableString *report) {

    [report appendString:
        @"\n=== KLASSHIERARKI ===\n"];

    Class current = cls;

    for (NSUInteger depth = 0;
         current && depth < 12;
         depth++) {

        [report appendFormat:
            @"%lu: %@\n",
            (unsigned long)depth,
            CMSString(class_getName(current))];

        current = class_getSuperclass(current);
    }
}

#pragma mark - Symbols

static void CMSInspectSymbols(
    NSMutableString *report) {

    NSUInteger found = 0;

    NSMutableSet<NSString *> *owners =
        [NSMutableSet set];

    [report appendString:
        @"=== EXPORTERADE FUNKTIONER ===\n"];

    for (NSUInteger i = 0; i < 5; i++) {

        void *address =
            dlsym(RTLD_DEFAULT, kSymbols[i]);

        NSString *owner = @"unknown";

        if (address) {

            found++;

            Dl_info info = {0};

            if (dladdr(address, &info) &&
                info.dli_fname) {

                owner =
                    CMSString(info.dli_fname)
                        .lastPathComponent;

                [owners addObject:owner];
            }
        }

        [report appendFormat:
            @"%lu. %@ %@\n",
            (unsigned long)(i + 1),
            address ? @"FOUND" : @"MISSING",
            address ? owner : @""];
    }

    [report appendFormat:
        @"\nSYMBOLER: %lu/5\n"
         "SAMMA BIBLIOTEK: %@\n",
        (unsigned long)found,
        (found == 5 && owners.count == 1)
            ? @"JA" : @"NEJ"];
}

#pragma mark - Diagnostics

static void CMSInspect(void) {

    CMSSetupPanel();

    NSMutableString *report =
        [NSMutableString stringWithString:
            @"CMSCrystalBridge v9\n"
             "READ-ONLY DIAGNOSTICS\n\n"];

    [report appendFormat:
        @"LADDADE BILDER: %u\n\n",
        _dyld_image_count()];

    CMSInspectSymbols(report);

    Class cls =
        objc_getClass("VIPCronologiaWidget");

    if (!cls) {

        [report appendString:
            @"\nVIPCronologiaWidget: NOT FOUND\n"];

    } else {

        [report appendString:
            @"\nVIPCronologiaWidget: FOUND\n"];

        CMSInspectHierarchy(cls, report);
        CMSInspectProperties(cls, report);
        CMSInspectIvars(cls, report);
        CMSInspectMethods(cls, report);
    }

    [report appendString:
        @"\n=== STATUS ===\n"
         "Endast runtime-metadata\n"
         "Inga okända metoder anropas\n"
         "Inga historikvärden läses\n"
         "Raid stack: ej ansluten\n"
         "AutoSpeed: oförändrad\n"];

    NSLog(@"[CMSBridgeV9] %@", report);

    if (gPanel) {

        gPanel.fullReport = [report copy];
        gPanel.details.text = report;

        [gPanel.details
            setContentOffset:CGPointZero
            animated:NO];

        [gPanel.copyDataButton
            setTitle:@"KOPIERA ALL DATA"
            forState:UIControlStateNormal];

        gPanel.statusLabel.text =
            @"Rapport klar";
    }
}

#pragma mark - Startup

__attribute__((constructor))
static void CMSBridgeV9Start(void) {

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

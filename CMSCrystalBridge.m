
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import <stdlib.h>

//
// CMSCrystalBridge v8
// Read-only Objective-C runtime diagnostics.
//
// No calls to unknown game functions.
// No modifications to game memory or history.
//

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

    if (!panel || panel.hidden) {
        return nil;
    }

    CGPoint local =
        [panel convertPoint:point fromView:self];

    if (![panel pointInside:local withEvent:event]) {
        return nil;
    }

    UIView *hit =
        [super hitTest:point withEvent:event];

    if (hit == self ||
        hit == self.rootViewController.view) {
        return nil;
    }

    return hit;
}

@end

#pragma mark - Diagnostic panel

@interface CMSBridgePanel : UIView

@property(nonatomic, strong) UITextView *details;
@property(nonatomic, strong) UIButton *toggle;
@property(nonatomic, assign) BOOL expanded;

@end

@implementation CMSBridgePanel

- (instancetype)initWithFrame:(CGRect)frame {

    if ((self = [super initWithFrame:frame])) {

        self.backgroundColor =
            [[UIColor blackColor]
                colorWithAlphaComponent:0.90];

        self.layer.cornerRadius = 10;
        self.layer.borderWidth = 1;
        self.layer.borderColor =
            UIColor.cyanColor.CGColor;

        self.clipsToBounds = YES;
        self.expanded = NO;

        self.toggle =
            [UIButton buttonWithType:
                UIButtonTypeSystem];

        self.toggle.frame =
            CGRectMake(0, 0, 190, 38);

        [self.toggle
            setTitle:@"CMS Bridge v8 +"
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
                    CGRectMake(8, 40, 304, 290)];

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

        UIPanGestureRecognizer *pan =
            [[UIPanGestureRecognizer alloc]
                initWithTarget:self
                action:@selector(drag:)];

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
            ? CGSizeMake(324, 340)
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

    [self.toggle
        setTitle:
            self.expanded
                ? @"CMS Bridge v8 -"
                : @"CMS Bridge v8 +"
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

        // Only drag using the title bar.
        // Allow normal scrolling in the text view.
        return point.y <= 38;
    }

    return YES;
}

@end

#pragma mark - Window setup

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

    gWindow.rootViewController =
        controller;

    gPanel =
        [[CMSBridgePanel alloc]
            initWithFrame:
                CGRectMake(12, 90, 190, 38)];

    [controller.view addSubview:gPanel];

    gWindow.panel = gPanel;

    // Do not replace the game's key window.
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

        if ([lower containsString:term]) {
            return YES;
        }
    }

    return NO;
}

#pragma mark - Property metadata

static void CMSInspectProperties(
    Class cls,
    NSMutableString *report) {

    unsigned int count = 0;

    objc_property_t *properties =
        class_copyPropertyList(cls, &count);

    [report appendFormat:
        @"\nEgenskaper: %u\n", count];

    for (unsigned int i = 0; i < count; i++) {

        NSString *name =
            CMSString(property_getName(properties[i]));

        NSString *attributes =
            CMSString(property_getAttributes(properties[i]));

        [report appendFormat:
            @"%@\n  %@\n",
            name,
            attributes];
    }

    free(properties);
}

#pragma mark - Instance variable metadata

static void CMSInspectIvars(
    Class cls,
    NSMutableString *report) {

    unsigned int count = 0;

    Ivar *ivars =
        class_copyIvarList(cls, &count);

    [report appendFormat:
        @"\nInstansvariabler: %u\n", count];

    for (unsigned int i = 0; i < count; i++) {

        NSString *name =
            CMSString(ivar_getName(ivars[i]));

        NSString *type =
            CMSString(ivar_getTypeEncoding(ivars[i]));

        [report appendFormat:
            @"%@ : %@\n", name, type];
    }

    free(ivars);
}

#pragma mark - Method metadata

static void CMSInspectMethods(
    Class cls,
    NSMutableString *report) {

    unsigned int count = 0;

    Method *methods =
        class_copyMethodList(cls, &count);

    [report appendFormat:
        @"\nMetoder totalt: %u\n", count];

    NSUInteger matches = 0;

    [report appendString:
        @"\nRelevanta metoder:\n"];

    for (unsigned int i = 0; i < count; i++) {

        Method method = methods[i];

        SEL selector =
            method_getName(method);

        NSString *name =
            NSStringFromSelector(selector);

        if (!CMSInterestingName(name)) {
            continue;
        }

        matches++;

        NSString *encoding =
            CMSString(method_getTypeEncoding(method));

        unsigned int arguments =
            method_getNumberOfArguments(method);

        [report appendFormat:
            @"\n%@\n"
             "Typ: %@\n"
             "Argument inkl self/_cmd: %u\n",
            name,
            encoding,
            arguments];

        // Inspect method signature only.
        // Do not invoke the method.

        for (unsigned int a = 0;
             a < arguments;
             a++) {

            char *argumentType =
                method_copyArgumentType(method, a);

            [report appendFormat:
                @"  arg%u: %@\n",
                a,
                CMSString(argumentType)];

            free(argumentType);
        }

        char *returnType =
            method_copyReturnType(method);

        [report appendFormat:
            @"  return: %@\n",
            CMSString(returnType)];

        free(returnType);
    }

    [report appendFormat:
        @"\nMatchande metoder: %lu\n",
        (unsigned long)matches];

    free(methods);
}

#pragma mark - Class hierarchy

static void CMSInspectHierarchy(
    Class cls,
    NSMutableString *report) {

    [report appendString:
        @"\nKlasshierarki:\n"];

    Class current = cls;

    NSUInteger depth = 0;

    while (current && depth < 12) {

        [report appendFormat:
            @"%lu: %@\n",
            (unsigned long)depth,
            CMSString(class_getName(current))];

        current = class_getSuperclass(current);

        depth++;
    }
}

#pragma mark - Symbol ownership

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

                NSString *path =
                    CMSString(info.dli_fname);

                owner = path.lastPathComponent;

                [owners addObject:owner];
            }
        }

        [report appendFormat:
            @"%lu: %@ %@\n",
            (unsigned long)(i + 1),
            address ? @"FOUND" : @"MISSING",
            address ? owner : @""];
    }

    [report appendFormat:
        @"\nSymboler: %lu/5\n"
         "Samma bibliotek: %@\n",
        (unsigned long)found,
        (found == 5 && owners.count == 1)
            ? @"JA" : @"NEJ"];
}

#pragma mark - Main diagnostics

static void CMSInspect(void) {

    CMSSetupPanel();

    NSMutableString *report =
        [NSMutableString stringWithString:
            @"CMS Bridge v8\n"
             "SKRIVSKYDDAD ANALYS\n\n"];

    [report appendFormat:
        @"Laddade bilder: %u\n\n",
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

    NSLog(@"[CMSBridgeV8] %@", report);

    if (gPanel) {

        gPanel.details.text = report;

        [gPanel.details
            setContentOffset:CGPointZero
            animated:NO];
    }
}

#pragma mark - Startup

__attribute__((constructor))
static void CMSBridgeV8Start(void) {

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

                    CMSInspect();
                });
        }
    });
}

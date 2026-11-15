
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import <stdlib.h>

// CMSCrystalBridge v7
// Read-only runtime diagnostics.
// Does not call unknown CMSCrystal functions.

static const char *const kSymbols[] = {
    "RS_GetTripleHistoryForSymbol",
    "RS_ResetTripleHistoryForSymbol",
    "RS_ResetTripleHistory",
    "RS_GetTargetSpinSymbol",
    "RS_SetTargetSpinSymbol"
};

#pragma mark - Touch pass-through window

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
            setTitle:@"CMS Bridge v7 +"
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
        self.details.hidden = YES;

        [self addSubview:self.details];

        UIPanGestureRecognizer *pan =
            [[UIPanGestureRecognizer alloc]
                initWithTarget:self
                action:@selector(drag:)];

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
                ? @"CMS Bridge v7 −"
                : @"CMS Bridge v7 +"
        forState:UIControlStateNormal];
}

- (void)drag:(UIPanGestureRecognizer *)gesture {

    UIView *parent = self.superview;

    if (!parent) return;

    CGPoint delta =
        [gesture translationInView:parent];

    CGRect frame = self.frame;

    CGFloat maxX =
        MAX(0,
            parent.bounds.size.width -
            frame.size.width);

    CGFloat maxY =
        MAX(0,
            parent.bounds.size.height -
            frame.size.height);

    frame.origin.x =
        MAX(0,
            MIN(frame.origin.x + delta.x, maxX));

    frame.origin.y =
        MAX(0,
            MIN(frame.origin.y + delta.y, maxY));

    self.frame = frame;

    [gesture setTranslation:CGPointZero
                    inView:parent];
}

@end

#pragma mark - Window setup

static CMSBridgeWindow *gWindow = nil;
static CMSBridgePanel *gPanel = nil;

static UIWindowScene *CMSForegroundScene(void) {

    if (@available(iOS 13.0, *)) {

        for (UIScene *scene in
            UIApplication.sharedApplication.connectedScenes) {

            if ([scene isKindOfClass:
                    UIWindowScene.class] &&
                scene.activationState ==
                    UISceneActivationStateForegroundActive) {

                return (UIWindowScene *)scene;
            }
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

#pragma mark - Runtime metadata inspection

static void CMSInspectHistoryStorage(
    NSMutableString *report) {

    Class cls =
        objc_getClass("VIPCronologiaWidget");

    if (!cls) {

        [report appendString:
            @"\nVIPCronologiaWidget: NOT FOUND\n"];

        return;
    }

    [report appendString:
        @"\n=== V7 HISTORIKANALYS ===\n"];

    unsigned int propertyCount = 0;

    objc_property_t *properties =
        class_copyPropertyList(
            cls,
            &propertyCount);

    [report appendFormat:
        @"\nEgenskaper: %u\n",
        propertyCount];

    for (unsigned int i = 0;
         i < propertyCount;
         i++) {

        const char *name =
            property_getName(properties[i]);

        const char *attributes =
            property_getAttributes(properties[i]);

        [report appendFormat:
            @"%s\n  %s\n",
            name ? name : "?",
            attributes ? attributes : "?"];
    }

    free(properties);

    unsigned int ivarCount = 0;

    Ivar *ivars =
        class_copyIvarList(
            cls,
            &ivarCount);

    [report appendFormat:
        @"\nInstansvariabler: %u\n",
        ivarCount];

    for (unsigned int i = 0;
         i < ivarCount;
         i++) {

        const char *name =
            ivar_getName(ivars[i]);

        const char *type =
            ivar_getTypeEncoding(ivars[i]);

        [report appendFormat:
            @"%s : %s\n",
            name ? name : "?",
            type ? type : "?"];
    }

    free(ivars);

    [report appendString:
        @"\nEndast metadata\n"
         "Inga historikfunktioner anropas\n"
         "Raid stack: ej ansluten\n"];
}

#pragma mark - Diagnostics

static void CMSInspect(void) {

    CMSSetupPanel();

    NSMutableString *report =
        [NSMutableString stringWithString:
            @"CMS Bridge v7\n"
             "Skrivskyddad analys\n\n"];

    NSUInteger found = 0;

    NSMutableSet<NSString *> *owners =
        [NSMutableSet set];

    for (NSUInteger i = 0; i < 5; i++) {

        void *address =
            dlsym(RTLD_DEFAULT, kSymbols[i]);

        if (!address) continue;

        found++;

        Dl_info info = {0};

        if (dladdr(address, &info) &&
            info.dli_fname) {

            NSString *path =
                [NSString stringWithUTF8String:
                    info.dli_fname];

            if (path) {
                [owners addObject:
                    path.lastPathComponent];
            }
        }
    }

    [report appendFormat:
        @"C-funktioner: %lu/5\n"
         "Laddade bilder: %u\n"
         "Ägare: %@\n",
        (unsigned long)found,
        _dyld_image_count(),
        [[owners.allObjects
            sortedArrayUsingSelector:
                @selector(compare:)]
            componentsJoinedByString:@", "]];

    CMSInspectHistoryStorage(report);

    NSLog(@"[CMSBridgeV7] %@", report);

    if (gPanel) {
        gPanel.details.text = report;
    }
}

#pragma mark - Startup

__attribute__((constructor))
static void CMSBridgeV7Start(void) {

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

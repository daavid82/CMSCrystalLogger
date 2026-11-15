
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import <string.h>

#pragma mark - Symbols

static const char *kSymbols[] = {
    "RS_GetTripleHistoryForSymbol",
    "RS_ResetTripleHistoryForSymbol",
    "RS_ResetTripleHistory",
    "RS_GetTargetSpinSymbol",
    "RS_SetTargetSpinSymbol"
};

static const NSUInteger kSymbolCount = 5;

#pragma mark - Pass-through window

@interface CMSPassWindow : UIWindow
@property(nonatomic, weak) UIView *touchPanel;
@end

@implementation CMSPassWindow

- (UIView *)hitTest:(CGPoint)point
          withEvent:(UIEvent *)event {

    UIView *panel = self.touchPanel;

    if (!panel || panel.hidden) {
        return nil;
    }

    CGPoint localPoint =
        [panel convertPoint:point fromView:self];

    if (![panel pointInside:localPoint withEvent:event]) {
        return nil;
    }

    return [super hitTest:point withEvent:event];
}

@end

#pragma mark - Diagnostic panel

@interface CMSBridgePanel : UIView

@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIButton *toggleButton;
@property(nonatomic, assign) BOOL expanded;

- (void)updateReport:(NSString *)report;

@end

@implementation CMSBridgePanel

- (instancetype)initWithFrame:(CGRect)frame {

    self = [super initWithFrame:frame];

    if (self) {

        self.expanded = NO;

        self.backgroundColor =
            [[UIColor blackColor]
                colorWithAlphaComponent:0.88];

        self.layer.cornerRadius = 10;
        self.layer.borderWidth = 1;

        self.layer.borderColor =
            [UIColor cyanColor].CGColor;

        self.clipsToBounds = YES;

        self.toggleButton =
            [UIButton buttonWithType:
                UIButtonTypeSystem];

        self.toggleButton.frame =
            CGRectMake(0, 0, 180, 38);

        [self.toggleButton
            setTitle:@"CMS Bridge v4  +"
            forState:UIControlStateNormal];

        [self.toggleButton
            setTitleColor:UIColor.whiteColor
            forState:UIControlStateNormal];

        self.toggleButton.titleLabel.font =
            [UIFont boldSystemFontOfSize:13];

        [self.toggleButton
            addTarget:self
            action:@selector(togglePanel)
            forControlEvents:
                UIControlEventTouchUpInside];

        [self addSubview:self.toggleButton];

        self.statusLabel =
            [[UILabel alloc]
                initWithFrame:
                    CGRectMake(10, 43, 300, 225)];

        self.statusLabel.textColor =
            UIColor.whiteColor;

        self.statusLabel.font =
            [UIFont monospacedSystemFontOfSize:10
                weight:UIFontWeightRegular];

        self.statusLabel.numberOfLines = 0;
        self.statusLabel.lineBreakMode =
            NSLineBreakByTruncatingTail;

        self.statusLabel.text =
            @"Väntar på diagnostik...";

        self.statusLabel.hidden = YES;

        [self addSubview:self.statusLabel];

        UIPanGestureRecognizer *pan =
            [[UIPanGestureRecognizer alloc]
                initWithTarget:self
                action:@selector(dragPanel:)];

        [self addGestureRecognizer:pan];
    }

    return self;
}

- (void)togglePanel {

    self.expanded = !self.expanded;

    CGRect frame = self.frame;

    frame.size.width =
        self.expanded ? 324 : 180;

    frame.size.height =
        self.expanded ? 280 : 38;

    self.frame = frame;

    self.statusLabel.hidden =
        !self.expanded;

    [self.toggleButton
        setTitle:
            self.expanded
                ? @"CMS Bridge v4  −"
                : @"CMS Bridge v4  +"
        forState:UIControlStateNormal];
}

- (void)dragPanel:
    (UIPanGestureRecognizer *)gesture {

    UIView *parent = self.superview;

    if (!parent) return;

    CGPoint delta =
        [gesture translationInView:parent];

    CGRect frame = self.frame;

    frame.origin.x += delta.x;
    frame.origin.y += delta.y;

    frame.origin.x =
        MAX(0,
            MIN(frame.origin.x,
                parent.bounds.size.width -
                frame.size.width));

    frame.origin.y =
        MAX(0,
            MIN(frame.origin.y,
                parent.bounds.size.height -
                frame.size.height));

    self.frame = frame;

    [gesture setTranslation:CGPointZero
                    inView:parent];
}

- (void)updateReport:(NSString *)report {

    self.statusLabel.text = report;
}

@end

#pragma mark - Globals

static CMSPassWindow *gWindow = nil;
static CMSBridgePanel *gPanel = nil;

#pragma mark - Window setup

static UIWindowScene *CMSActiveScene(void) {

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

static void CMSCreatePanel(void) {

    if (gPanel) return;

    UIWindowScene *scene =
        CMSActiveScene();

    if (!scene) return;

    gWindow =
        [[CMSPassWindow alloc]
            initWithWindowScene:scene];

    gWindow.frame =
        scene.coordinateSpace.bounds;

    gWindow.windowLevel =
        UIWindowLevelAlert + 10;

    UIViewController *controller =
        [UIViewController new];

    controller.view.backgroundColor =
        UIColor.clearColor;

    controller.view.userInteractionEnabled =
        YES;

    gWindow.rootViewController =
        controller;

    gPanel =
        [[CMSBridgePanel alloc]
            initWithFrame:
                CGRectMake(12, 90, 180, 38)];

    [controller.view addSubview:gPanel];

    gWindow.touchPanel = gPanel;

    // Do not call makeKeyAndVisible.
    // Keep the game's existing key window.
    gWindow.hidden = NO;
}

#pragma mark - Diagnostics

static NSString *CMSShortName(const char *path) {

    if (!path) return @"Unknown";

    NSString *name =
        [NSString stringWithUTF8String:path];

    return name.lastPathComponent ?: @"Unknown";
}

static void CMSProbe(unsigned attempt) {

    NSMutableArray<NSString *> *libraries =
        [NSMutableArray array];

    NSMutableArray<NSString *> *candidates =
        [NSMutableArray array];

    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {

        const char *path =
            _dyld_get_image_name(i);

        if (!path) continue;

        NSString *name =
            CMSShortName(path);

        [libraries addObject:name];

        NSString *lower =
            name.lowercaseString;

        if ([lower containsString:@"crystal"] ||
            [lower containsString:@"god"] ||
            [lower containsString:@"inject"]) {

            [candidates addObject:name];
        }
    }

    NSMutableString *report =
        [NSMutableString stringWithFormat:
            @"Kontroll: %u\n"
             "Laddade bilder: %u\n\n",
            attempt,
            count];

    [report appendString:
        @"Möjliga bibliotek:\n"];

    NSUInteger shown =
        MIN(candidates.count, (NSUInteger)6);

    for (NSUInteger i = 0; i < shown; i++) {

        [report appendFormat:
            @"%@\n", candidates[i]];
    }

    if (candidates.count == 0) {

        [report appendString:
            @"Inga namnmatchningar\n"];
    }

    NSUInteger found = 0;

    [report appendString:
        @"\nHistorikfunktioner:\n"];

    for (NSUInteger i = 0;
         i < kSymbolCount;
         i++) {

        void *address =
            dlsym(RTLD_DEFAULT, kSymbols[i]);

        Dl_info info = {0};

        NSString *owner = @"";

        if (address &&
            dladdr(address, &info) &&
            info.dli_fname) {

            owner =
                CMSShortName(info.dli_fname);
        }

        if (address) {
            found++;
        }

        [report appendFormat:
            @"%lu: %@ %@\n",
            (unsigned long)(i + 1),
            address ? @"FOUND" : @"NOT FOUND",
            address ? owner : @""];
    }

    [report appendFormat:
        @"\nSymboler: %lu/5\n"
         "Inga spelanrop",
        (unsigned long)found];

    NSLog(@"[CMSBridgeV4] %@", report);

    CMSCreatePanel();

    if (gPanel) {
        [gPanel updateReport:report];
    }

    // Detailed image names are printed to
    // the system log for later diagnostics.
    NSLog(@"[CMSBridgeV4] Loaded images: %@",
          [libraries componentsJoinedByString:@", "]);
}

#pragma mark - Startup

__attribute__((constructor))
static void CMSBridgeV4Start(void) {

    dispatch_async(
        dispatch_get_main_queue(), ^{

        const int delays[] = {
            3, 8, 20, 40
        };

        for (unsigned i = 0; i < 4; i++) {

            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)delays[i] *
                        NSEC_PER_SEC),
                dispatch_get_main_queue(), ^{

                    CMSProbe(i + 1);
                });
        }
    });
}

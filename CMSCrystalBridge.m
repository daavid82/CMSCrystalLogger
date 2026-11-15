
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import <string.h>

static const char * const kSymbols[] = {
    "RS_GetTripleHistoryForSymbol",
    "RS_ResetTripleHistoryForSymbol",
    "RS_ResetTripleHistory",
    "RS_GetTargetSpinSymbol",
    "RS_SetTargetSpinSymbol"
};

@interface CMSBridgePanel : UIView
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UIButton *toggleButton;
@property(nonatomic,assign) BOOL expanded;
@end

@implementation CMSBridgePanel

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor =
            [[UIColor blackColor] colorWithAlphaComponent:0.85];
        self.layer.cornerRadius = 12;
        self.layer.borderColor =
            [UIColor colorWithRed:0.30
                            green:0.75
                             blue:0.95
                            alpha:1].CGColor;
        self.layer.borderWidth = 1;
        self.clipsToBounds = YES;
        self.expanded = YES;

        UILabel *title =
            [[UILabel alloc] initWithFrame:CGRectMake(12, 8, 270, 24)];
        title.text = @"CMSCrystal Bridge v3 · Diagnostik";
        title.textColor = UIColor.whiteColor;
        title.font = [UIFont boldSystemFontOfSize:14];
        [self addSubview:title];

        self.statusLabel =
            [[UILabel alloc] initWithFrame:CGRectMake(12, 37, 280, 180)];
        self.statusLabel.textColor = UIColor.whiteColor;
        self.statusLabel.font =
            [UIFont monospacedSystemFontOfSize:11
                                       weight:UIFontWeightRegular];
        self.statusLabel.numberOfLines = 0;
        self.statusLabel.text = @"Väntar på första kontrollen…";
        [self addSubview:self.statusLabel];

        self.toggleButton =
            [UIButton buttonWithType:UIButtonTypeSystem];
        self.toggleButton.frame = CGRectMake(280, 4, 32, 32);
        [self.toggleButton setTitle:@"−"
                          forState:UIControlStateNormal];
        [self.toggleButton setTitleColor:UIColor.whiteColor
                               forState:UIControlStateNormal];
        [self.toggleButton addTarget:self
                              action:@selector(toggle)
                    forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.toggleButton];

        UIPanGestureRecognizer *pan =
            [[UIPanGestureRecognizer alloc]
                initWithTarget:self
                        action:@selector(drag:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)toggle {
    self.expanded = !self.expanded;
    CGRect f = self.frame;
    f.size.height = self.expanded ? 226 : 38;
    self.frame = f;
    self.statusLabel.hidden = !self.expanded;
    [self.toggleButton
        setTitle:self.expanded ? @"−" : @"+"
        forState:UIControlStateNormal];
}

- (void)drag:(UIPanGestureRecognizer *)gesture {
    CGPoint p = [gesture translationInView:self.superview];
    self.center = CGPointMake(
        self.center.x + p.x,
        self.center.y + p.y
    );
    [gesture setTranslation:CGPointZero
                    inView:self.superview];
}
@end

static CMSBridgePanel *gPanel;
static UIWindow *gOverlayWindow;

static UIWindowScene *ActiveScene(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in
             UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] &&
                scene.activationState ==
                    UISceneActivationStateForegroundActive)
                return (UIWindowScene *)scene;
        }

        for (UIScene *scene in
             UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class])
                return (UIWindowScene *)scene;
        }
    }
    return nil;
}

static void ShowPanel(void) {
    if (gPanel) return;

    UIWindowScene *scene = ActiveScene();
    if (!scene) return;

    if (@available(iOS 13.0, *)) {
        gOverlayWindow =
            [[UIWindow alloc] initWithWindowScene:scene];
    } else {
        gOverlayWindow =
            [[UIWindow alloc]
                initWithFrame:UIScreen.mainScreen.bounds];
    }

    gOverlayWindow.frame = scene.coordinateSpace.bounds;
    gOverlayWindow.windowLevel = UIWindowLevelAlert + 10;

    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    gOverlayWindow.rootViewController = root;
    gOverlayWindow.hidden = NO;

    // Separat fönster kan fånga pekningar utanför panelen.
    gPanel =
        [[CMSBridgePanel alloc]
            initWithFrame:CGRectMake(12, 90, 324, 226)];
    [root.view addSubview:gPanel];
}

static void Probe(unsigned attempt) {
    NSMutableArray<NSString *> *originals =
        [NSMutableArray array];

    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        const char *path = _dyld_get_image_name(i);

        if (path &&
            strstr(path, "CMSCrystal") &&
            !strstr(path, "CMSCrystalBridge") &&
            !strstr(path, "CMSCrystalLogger")) {
            [originals addObject:
                [[NSString stringWithUTF8String:path]
                    lastPathComponent]];
        }
    }

    NSUInteger found = 0;

    NSMutableString *report =
        [NSMutableString stringWithFormat:
            @"Kontroll %u\nOriginal: %@\n",
            attempt,
            originals.count
                ? [originals componentsJoinedByString:@", "]
                : @"NOT LOADED"];

    for (size_t i = 0;
         i < sizeof(kSymbols) / sizeof(kSymbols[0]);
         ++i) {

        void *addr = dlsym(RTLD_DEFAULT, kSymbols[i]);
        Dl_info info = {0};

        const char *owner =
            (addr && dladdr(addr, &info) && info.dli_fname)
                ? info.dli_fname
                : NULL;

        BOOL correctOwner =
            owner &&
            strstr(owner, "CMSCrystal") &&
            !strstr(owner, "CMSCrystalBridge");

        if (addr && correctOwner) found++;

        [report appendFormat:
            @"%zu. %@ %@\n",
            i + 1,
            addr && correctOwner ? @"FOUND" : @"NOT FOUND",
            @(kSymbols[i])];
    }

    [report appendFormat:
        @"\nFunktioner: %lu/5\nEndast läsning – inga anrop",
        (unsigned long)found];

    NSLog(@"[CMSBridgeV3] %@", report);

    ShowPanel();

    if (gPanel) {
        gPanel.statusLabel.text = report;
    }
}

__attribute__((constructor))
static void InitCMSBridgeV3(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        const int delays[] = {3, 8, 20, 40};

        for (unsigned i = 0; i < 4; ++i) {
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)delays[i] * NSEC_PER_SEC
                ),
                dispatch_get_main_queue(),
                ^{
                    Probe(i + 1);
                }
            );
        }
    });
}

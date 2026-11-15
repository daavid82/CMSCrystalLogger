
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import <string.h>

// CMSCrystalBridge v5: safe symbol ownership diagnostics.
// Does not invoke unknown functions or modify the game.
static const char *const kSymbols[] = {
    "RS_GetTripleHistoryForSymbol",
    "RS_ResetTripleHistoryForSymbol",
    "RS_ResetTripleHistory",
    "RS_GetTargetSpinSymbol",
    "RS_SetTargetSpinSymbol"
};

@interface CMSBridgePassWindow : UIWindow
@property(nonatomic,weak) UIView *interactivePanel;
@end
@implementation CMSBridgePassWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *panel = self.interactivePanel;
    if (!panel || panel.hidden || panel.alpha < 0.01) return nil;
    CGPoint local = [panel convertPoint:point fromView:self];
    if (![panel pointInside:local withEvent:event]) return nil;
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self || hit == self.rootViewController.view) ? nil : hit;
}
@end

@interface CMSBridgeV5Panel : UIView
@property(nonatomic,strong) UILabel *reportLabel;
@property(nonatomic,strong) UIButton *toggleButton;
@property(nonatomic,assign) BOOL expanded;
- (void)setReport:(NSString *)report;
@end
@implementation CMSBridgeV5Panel
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.88];
        self.layer.cornerRadius = 10;
        self.layer.borderWidth = 1;
        self.layer.borderColor = UIColor.cyanColor.CGColor;
        self.clipsToBounds = YES;
        self.expanded = NO;
        self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.toggleButton.frame = CGRectMake(0, 0, 188, 38);
        [self.toggleButton setTitle:@"CMS Bridge v5  +" forState:UIControlStateNormal];
        [self.toggleButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        self.toggleButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [self.toggleButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.toggleButton];
        self.reportLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 42, 302, 255)];
        self.reportLabel.textColor = UIColor.whiteColor;
        self.reportLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        self.reportLabel.numberOfLines = 0;
        self.reportLabel.adjustsFontSizeToFitWidth = NO;
        self.reportLabel.text = @"Väntar på kontroll...";
        self.reportLabel.hidden = YES;
        [self addSubview:self.reportLabel];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}
- (void)togglePanel {
    self.expanded = !self.expanded;
    CGRect f = self.frame;
    f.size = self.expanded ? CGSizeMake(324, 310) : CGSizeMake(188, 38);
    if (self.superview) {
        f.origin.x = MAX(0, MIN(f.origin.x, self.superview.bounds.size.width - f.size.width));
        f.origin.y = MAX(0, MIN(f.origin.y, self.superview.bounds.size.height - f.size.height));
    }
    self.frame = f;
    self.reportLabel.hidden = !self.expanded;
    [self.toggleButton setTitle:(self.expanded ? @"CMS Bridge v5  −" : @"CMS Bridge v5  +") forState:UIControlStateNormal];
}
- (void)drag:(UIPanGestureRecognizer *)gesture {
    UIView *parent = self.superview;
    if (!parent) return;
    CGPoint delta = [gesture translationInView:parent];
    CGRect f = self.frame;
    f.origin.x = MAX(0, MIN(f.origin.x + delta.x, MAX(0, parent.bounds.size.width - f.size.width)));
    f.origin.y = MAX(0, MIN(f.origin.y + delta.y, MAX(0, parent.bounds.size.height - f.size.height)));
    self.frame = f;
    [gesture setTranslation:CGPointZero inView:parent];
}
- (void)setReport:(NSString *)report { self.reportLabel.text = report; }
@end

static CMSBridgePassWindow *gWindow;
static CMSBridgeV5Panel *gPanel;

static UIWindowScene *ForegroundScene(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive)
                return (UIWindowScene *)s;
        }
    }
    return nil;
}
static void EnsurePanel(void) {
    if (gPanel) return;
    UIWindowScene *scene = ForegroundScene();
    if (!scene) return;
    gWindow = [[CMSBridgePassWindow alloc] initWithWindowScene:scene];
    gWindow.frame = scene.coordinateSpace.bounds;
    gWindow.windowLevel = UIWindowLevelAlert + 10;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    gWindow.rootViewController = vc;
    gPanel = [[CMSBridgeV5Panel alloc] initWithFrame:CGRectMake(12, 90, 188, 38)];
    [vc.view addSubview:gPanel];
    gWindow.interactivePanel = gPanel;
    // Keep the game's key window unchanged.
    gWindow.hidden = NO;
}

static NSString *ShortName(const char *path) {
    if (!path) return @"unknown";
    NSString *s = [NSString stringWithUTF8String:path];
    return s.lastPathComponent ?: @"unknown";
}

static void Probe(unsigned attempt) {
    // All UI and dyld inspection occur on the main thread.
    EnsurePanel();
    NSUInteger found = 0;
    NSMutableSet<NSString *> *owners = [NSMutableSet set];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSUInteger i = 0; i < 5; i++) {
        void *address = dlsym(RTLD_DEFAULT, kSymbols[i]);
        Dl_info info = {0};
        NSString *owner = @"unknown";
        if (address && dladdr(address, &info) && info.dli_fname) {
            owner = ShortName(info.dli_fname);
            [owners addObject:owner];
        }
        if (address) found++;
        [lines addObject:[NSString stringWithFormat:@"%lu %@ %@", (unsigned long)(i + 1), address ? @"FOUND" : @"MISSING", owner]];
    }
    NSString *ownerText = owners.count ? [[owners.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "] : @"ingen";
    BOOL consistent = found == 5 && owners.count == 1;
    NSString *report = [NSString stringWithFormat:
        @"Kontroll %u | Bilder: %u\n"
         "Symboler: %lu/5\n"
         "Ägare: %@\n"
         "Samma bibliotek: %@\n\n"
         "%@\n\n"
         "LÄGE: ENDAST DIAGNOSTIK\n"
         "Inga funktionsanrop\n"
         "Raid stack: ej ansluten",
         attempt, _dyld_image_count(), (unsigned long)found,
         ownerText, consistent ? @"JA" : @"NEJ",
         [lines componentsJoinedByString:@"\n"]];
    NSLog(@"[CMSBridgeV5] %@", report);
    if (gPanel) [gPanel setReport:report];
}

__attribute__((constructor))
static void StartCMSBridgeV5(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        const int delays[] = {3, 8, 20, 40};
        for (unsigned i = 0; i < 4; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)delays[i] * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                Probe(i + 1);
            });
        }
    });
}

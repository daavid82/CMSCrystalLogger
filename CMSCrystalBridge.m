
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

static const char *const symbols[] = {"RS_GetTripleHistoryForSymbol","RS_ResetTripleHistoryForSymbol","RS_ResetTripleHistory","RS_GetTargetSpinSymbol","RS_SetTargetSpinSymbol"};

@interface BridgeWindow : UIWindow
@property(nonatomic,weak) UIView *panel;
@end
@implementation BridgeWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v=self.panel;
    if (!v || v.hidden) return nil;
    CGPoint q=[v convertPoint:p fromView:self];
    if (![v pointInside:q withEvent:e]) return nil;
    UIView *hit=[super hitTest:p withEvent:e];
    return (hit==self || hit==self.rootViewController.view) ? nil : hit;
}
@end

@interface BridgePanel : UIView
@property(nonatomic,strong) UITextView *details;
@property(nonatomic,strong) UIButton *toggle;
@property(nonatomic,assign) BOOL expanded;
@end
@implementation BridgePanel
- (instancetype)initWithFrame:(CGRect)f {
    if ((self=[super initWithFrame:f])) {
        self.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0.9];
        self.layer.cornerRadius=10;
        self.layer.borderWidth=1;
        self.layer.borderColor=UIColor.cyanColor.CGColor;
        self.clipsToBounds=YES;
        self.toggle=[UIButton buttonWithType:UIButtonTypeSystem];
        self.toggle.frame=CGRectMake(0,0,190,38);
        [self.toggle setTitle:@"CMS Bridge v6 +" forState:UIControlStateNormal];
        [self.toggle setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [self.toggle addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.toggle];
        self.details=[[UITextView alloc] initWithFrame:CGRectMake(8,40,304,290)];
        self.details.backgroundColor=UIColor.clearColor;
        self.details.textColor=UIColor.whiteColor;
        self.details.font=[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
        self.details.editable=NO;
        self.details.hidden=YES;
        [self addSubview:self.details];
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}
- (void)togglePanel {
    self.expanded=!self.expanded;
    CGRect f=self.frame;
    f.size=self.expanded ? CGSizeMake(324,340) : CGSizeMake(190,38);
    if (self.superview) {
        f.origin.x=MAX(0,MIN(f.origin.x,MAX(0,self.superview.bounds.size.width-f.size.width)));
        f.origin.y=MAX(0,MIN(f.origin.y,MAX(0,self.superview.bounds.size.height-f.size.height)));
    }
    self.frame=f;
    self.details.hidden=!self.expanded;
    [self.toggle setTitle:self.expanded ? @"CMS Bridge v6 −" : @"CMS Bridge v6 +" forState:UIControlStateNormal];
}
- (void)drag:(UIPanGestureRecognizer *)g {
    if (!self.superview) return;
    CGPoint d=[g translationInView:self.superview];
    CGRect f=self.frame;
    f.origin.x=MAX(0,MIN(f.origin.x+d.x,MAX(0,self.superview.bounds.size.width-f.size.width)));
    f.origin.y=MAX(0,MIN(f.origin.y+d.y,MAX(0,self.superview.bounds.size.height-f.size.height)));
    self.frame=f;
    [g setTranslation:CGPointZero inView:self.superview];
}
@end

static BridgeWindow *window;
static BridgePanel *panel;
static void setup(void) {
    if (panel) return;
    UIWindowScene *active=nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] && s.activationState==UISceneActivationStateForegroundActive) {active=(UIWindowScene *)s;break;}
    }
    if (!active) return;
    window=[[BridgeWindow alloc] initWithWindowScene:active];
    window.frame=active.coordinateSpace.bounds;
    window.windowLevel=UIWindowLevelAlert+10;
    UIViewController *vc=[UIViewController new];
    vc.view.backgroundColor=UIColor.clearColor;
    window.rootViewController=vc;
    panel=[[BridgePanel alloc] initWithFrame:CGRectMake(12,90,190,38)];
    [vc.view addSubview:panel];
    window.panel=panel;
    window.hidden=NO;
}
static void inspect(void) {
    setup();
    NSMutableString *r=[NSMutableString stringWithString:@"V6 · skrivskyddad analys\n\n"];
    NSUInteger found=0;
    NSMutableSet *owners=[NSMutableSet set];
    for (int i=0;i<5;i++) {
        void *ptr=dlsym(RTLD_DEFAULT,symbols[i]);
        if (ptr) {
            found++;
            Dl_info di={0};
            if (dladdr(ptr,&di) && di.dli_fname) {
                [owners addObject:[[NSString stringWithUTF8String:di.dli_fname] lastPathComponent]];
            }
        }
    }
    [r appendFormat:@"C-funktioner: %lu/5\nÄgare: %@\n\n",(unsigned long)found,[[owners allObjects] componentsJoinedByString:@", "]];
    Class cls=objc_getClass("VIPCronologiaWidget");
    if (!cls) {
        [r appendString:@"VIPCronologiaWidget: saknas\n"];
    } else {
        [r appendString:@"VIPCronologiaWidget: FOUND\n\nMetoder (typkod):\n"];
        unsigned int n=0;
        Method *methods=class_copyMethodList(cls,&n);
        NSUInteger matches=0;
        for (unsigned int i=0;i<n;i++) {
            SEL s=method_getName(methods[i]);
            NSString *name=NSStringFromSelector(s);
            NSString *low=name.lowercaseString;
            if ([low containsString:@"history"] || [low containsString:@"symbol"] || [low containsString:@"count"] || [low containsString:@"refresh"]) {
                const char *encoding=method_getTypeEncoding(methods[i]);
                [r appendFormat:@"%@\n  %s\n",name,encoding?:"?"];
                matches++;
            }
        }
        if (methods) free(methods);
        [r appendFormat:@"\nMatchande metoder: %lu\n",(unsigned long)matches];
    }
    [r appendString:@"\nInga historikanrop\nRaid stack: ej ansluten"];
    NSLog(@"[CMSBridgeV6] %@",r);
    if (panel) panel.details.text=r;
}
__attribute__((constructor)) static void start(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSNumber *delay in @[@3,@10,@25]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay.intValue*NSEC_PER_SEC)),dispatch_get_main_queue(),^{inspect();});
        }
    });
}


#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <stdint.h>

@interface CMSLogger : NSObject
@property(nonatomic,strong) UIWindow *panel;
@property(nonatomic,strong) UITextView *logView;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UILabel *balanceLabel;
@property(nonatomic,strong) UILabel *betLabel;
@property(nonatomic,strong) UILabel *resultLabel;
@property(nonatomic,strong) UILabel *regionLabel;
@property(nonatomic,strong) NSMutableArray<NSString *> *events;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,assign) BOOL running;
@property(nonatomic,assign) BOOL busy;
@property(nonatomic,assign) NSInteger attempts;
@property(nonatomic,assign) NSInteger scans;
@property(nonatomic,assign) NSInteger balanceYPercent;
@property(nonatomic,assign) NSInteger resultYPercent;
@property(nonatomic,assign) long long balance;
@property(nonatomic,assign) BOOL hasBalance;
@property(nonatomic,assign) long long pendingBalance;
@property(nonatomic,assign) NSInteger balanceStreak;
@property(nonatomic,assign) NSInteger bet;
@property(nonatomic,assign) NSInteger pendingBet;
@property(nonatomic,assign) NSInteger betStreak;
@property(nonatomic,copy) NSString *result;
@property(nonatomic,copy) NSString *pendingResult;
@property(nonatomic,assign) NSInteger resultStreak;
@property(nonatomic,assign) NSInteger possibleSpins;
@property(nonatomic,assign) NSInteger possibleResults;
@property(nonatomic,assign) NSInteger uncertainChanges;
+ (instancetype)shared;
- (void)start;
@end

@implementation CMSLogger

+ (instancetype)shared {
    static CMSLogger *x;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        x = [CMSLogger new];
        x.events = [NSMutableArray new];
        x.balanceYPercent = 82;
        x.resultYPercent = 20;
        x.result = @"";
        x.pendingResult = @"";
    });
    return x;
}

- (void)log:(NSString *)s {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self log:s];
        });
        return;
    }

    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"HH:mm:ss";

    NSString *line = [NSString stringWithFormat:
        @"%@ %@", [f stringFromDate:[NSDate date]], s];

    [self.events addObject:line];

    if (self.events.count > 350)
        [self.events removeObjectAtIndex:0];

    NSString *all =
        [self.events componentsJoinedByString:@"\n"];

    self.logView.text = all;

    if (all.length)
        [self.logView scrollRangeToVisible:
            NSMakeRange(all.length - 1, 1)];

    [all writeToFile:
        [NSTemporaryDirectory()
            stringByAppendingPathComponent:@"CMSCrystalV12.log"]
        atomically:YES
        encoding:NSUTF8StringEncoding
        error:nil];

    NSLog(@"[CMSCrystal] %@", line);
}

- (void)refresh {
    self.statusLabel.text = [NSString stringWithFormat:
        @"AUTO %@ | SCANS %ld | POSSIBLE SPINS %ld",
        self.running ? @"ON" : @"OFF",
        (long)self.scans,
        (long)self.possibleSpins];

    self.statusLabel.textColor =
        self.running ? UIColor.systemGreenColor :
                       UIColor.systemOrangeColor;

    self.balanceLabel.text = self.hasBalance ?
        [NSString stringWithFormat:@"BALANCE: %lld",self.balance] :
        @"BALANCE: WAITING";

    self.betLabel.text = self.bet > 0 ?
        [NSString stringWithFormat:@"MAX BET: x%ld",(long)self.bet] :
        @"MAX BET: WAITING";

    self.resultLabel.text = [NSString stringWithFormat:
        @"TOP: %@ | CANDIDATES %ld",
        self.result.length ? self.result : @"UNKNOWN",
        (long)self.possibleResults];

    self.regionLabel.text = [NSString stringWithFormat:
        @"TOP Y %ld%% | BAL Y %ld%%",
        (long)self.resultYPercent,
        (long)self.balanceYPercent];
}

- (UIWindow *)gameWindow {
    UIWindow *best = nil;

    for (UIScene *s in
         UIApplication.sharedApplication.connectedScenes) {

        if (![s isKindOfClass:[UIWindowScene class]])
            continue;

        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            if (w == self.panel || w.hidden ||
                w.bounds.size.width < 100 ||
                w.bounds.size.height < 100)
                continue;

            if (!best || w.windowLevel < best.windowLevel)
                best = w;
        }
    }
    return best;
}

- (UIImage *)capture {
    UIWindow *w = [self gameWindow];
    if (!w) return nil;

    UIGraphicsImageRendererFormat *fmt =
        [UIGraphicsImageRendererFormat defaultFormat];

    fmt.scale = 1;
    fmt.opaque = YES;

    UIGraphicsImageRenderer *r =
        [[UIGraphicsImageRenderer alloc]
            initWithSize:w.bounds.size format:fmt];

    return [r imageWithActions:
        ^(UIGraphicsImageRendererContext *c) {
            [w drawViewHierarchyInRect:
                CGRectMake(0, 0,
                           w.bounds.size.width,
                           w.bounds.size.height)
                afterScreenUpdates:NO];
        }];
}

- (CGImageRef)crop:(CGImageRef)image
                x:(CGFloat)x
                y:(CGFloat)y
            width:(CGFloat)width
           height:(CGFloat)height {

    CGFloat iw = (CGFloat)CGImageGetWidth(image);
    CGFloat ih = (CGFloat)CGImageGetHeight(image);

    CGRect r = CGRectMake(
        iw*x, ih*y, iw*width, ih*height);

    r = CGRectIntersection(
        r, CGRectMake(0, 0, iw, ih));

    if (CGRectIsEmpty(r)) return NULL;

    return CGImageCreateWithImageInRect(
        image, CGRectIntegral(r));
}

- (NSArray<NSDictionary *> *)recognize:(CGImageRef)image {
    if (!image) return @[];

    VNRecognizeTextRequest *req =
        [VNRecognizeTextRequest new];

    req.recognitionLevel =
        VNRequestTextRecognitionLevelAccurate;
    req.usesLanguageCorrection = NO;
    req.recognitionLanguages = @[@"en-US"];

    NSError *err = nil;

    VNImageRequestHandler *handler =
        [[VNImageRequestHandler alloc]
            initWithCGImage:image options:@{}];

    if (![handler performRequests:@[req] error:&err])
        return @[];

    NSMutableArray *a = [NSMutableArray new];

    for (VNRecognizedTextObservation *obs in req.results) {
        VNRecognizedText *t =
            [[obs topCandidates:1] firstObject];

        if (t) {
            [a addObject:@{
                @"text":t.string,
                @"confidence":@(t.confidence),
                @"y":@(obs.boundingBox.origin.y)
            }];
        }
    }
    return a;
}

- (long long)numberFromText:(NSString *)s {
    NSMutableString *digits = [NSMutableString new];

    for (NSUInteger i=0; i<s.length; i++) {
        unichar c = [s characterAtIndex:i];

        if (c >= '0' && c <= '9')
            [digits appendFormat:@"%C",c];
    }

    if (!digits.length || digits.length > 15)
        return -1;

    return digits.longLongValue;
}

- (long long)balanceFrom:(NSArray<NSDictionary *> *)items {
    long long best = -1;
    float bestConfidence = 0;

    for (NSDictionary *d in items) {
        NSString *s = d[@"text"];

        NSString *trim =
            [s stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet];

        // Spin balance appears as +791636.
        // Ignore other numbers without a leading +.
        if (![trim hasPrefix:@"+"])
            continue;

        long long n = [self numberFromText:trim];
        if (n < 0) continue;

        float c = [d[@"confidence"] floatValue];

        if (c > bestConfidence) {
            best = n;
            bestConfidence = c;
        }
    }
    return best;
}

- (NSInteger)betFrom:(NSArray<NSDictionary *> *)items {
    for (NSDictionary *d in items) {
        NSString *s = [d[@"text"] uppercaseString];

        NSRange r = [s rangeOfString:@"BET"];
        if (r.location == NSNotFound)
            continue;

        NSRange x =
            [s rangeOfString:@"X"
                     options:NSBackwardsSearch];

        if (x.location == NSNotFound)
            continue;

        long long n = [self numberFromText:
            [s substringFromIndex:x.location+1]];

        if (n >= 1 && n <= 100000)
            return (NSInteger)n;
    }
    return 0;
}

- (NSString *)resultFrom:(NSArray<NSDictionary *> *)items {
    NSArray *names =
        @[@"ATTACK",@"POINT",@"STEAL",@"SHIELD",@"SPINS"];

    NSString *best = @"";
    float score = 0;

    for (NSDictionary *d in items) {
        NSString *s = [d[@"text"] uppercaseString];
        float confidence =
            [d[@"confidence"] floatValue];

        for (NSString *name in names) {
            if ([s containsString:name] &&
                confidence > score) {
                best = name;
                score = confidence;
            }
        }
    }

    return score >= 0.7 ? best : @"";
}

- (void)processBalance:(long long)n {
    if (n < 0) return;

    if (n == self.pendingBalance)
        self.balanceStreak++;
    else {
        self.pendingBalance = n;
        self.balanceStreak = 1;
    }

    if (self.balanceStreak < 2)
        return;

    if (!self.hasBalance) {
        self.hasBalance = YES;
        self.balance = n;

        [self log:[NSString stringWithFormat:
            @"BALANCE BASELINE: %lld",n]];
        return;
    }

    if (n == self.balance)
        return;

    long long old = self.balance;
    long long delta = n - old;
    self.balance = n;

    [self log:[NSString stringWithFormat:
        @"BALANCE CHANGE: %lld -> %lld (%+lld)",
        old,n,delta]];

    if (delta < 0 &&
        self.bet > 0 &&
        -delta == self.bet) {

        self.possibleSpins++;

        [self log:[NSString stringWithFormat:
            @"POSSIBLE SPIN #%ld | BET x%ld",
            (long)self.possibleSpins,
            (long)self.bet]];
    } else {
        self.uncertainChanges++;

        [self log:
            @"UNCLASSIFIED BALANCE CHANGE (WIN/REFUND/BET/READING?)"];
    }
}

- (void)processBet:(NSInteger)n {
    if (n <= 0) return;

    if (n == self.pendingBet)
        self.betStreak++;
    else {
        self.pendingBet = n;
        self.betStreak = 1;
    }

    if (self.betStreak >= 2 && n != self.bet) {
        self.bet = n;

        [self log:[NSString stringWithFormat:
            @"BET DETECTED: x%ld",(long)n]];
    }
}

- (void)processResult:(NSString *)s {
    if (!s.length) {
        self.resultStreak = 0;
        self.pendingResult = @"";
        return;
    }

    if ([s isEqualToString:self.pendingResult])
        self.resultStreak++;
    else {
        self.pendingResult = s;
        self.resultStreak = 1;
    }

    if (self.resultStreak == 2 &&
        ![s isEqualToString:self.result]) {

        self.result = s;
        self.possibleResults++;

        [self log:[NSString stringWithFormat:
            @"POSSIBLE TOP RESULT: %@",s]];
    }
}

- (void)scan {
    if (self.busy) return;
    self.busy = YES;

    UIImage *image = [self capture];

    if (!image.CGImage) {
        self.busy = NO;
        [self log:@"CAPTURE FAILED"];
        return;
    }

    self.scans++;

    CGImageRef original = image.CGImage;

    CGImageRef top = [self crop:original
        x:0.12
        y:self.resultYPercent/100.0
        width:0.76
        height:0.16];

    CGImageRef bottom = [self crop:original
        x:0.29
        y:self.balanceYPercent/100.0
        width:0.43
        height:0.08];

    CGImageRef bet = [self crop:original
        x:0.28
        y:0.665
        width:0.45
        height:0.045];

    if (!top || !bottom || !bet) {
        if (top) CGImageRelease(top);
        if (bottom) CGImageRelease(bottom);
        if (bet) CGImageRelease(bet);

        self.busy = NO;
        [self log:@"CROP FAILED"];
        return;
    }

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED,0), ^{
        @autoreleasepool {
            NSArray *topTexts =
                [self recognize:top];

            NSArray *balanceTexts =
                [self recognize:bottom];

            NSArray *betTexts =
                [self recognize:bet];

            CGImageRelease(top);
            CGImageRelease(bottom);
            CGImageRelease(bet);

            NSString *result =
                [self resultFrom:topTexts];

            long long balance =
                [self balanceFrom:balanceTexts];

            NSInteger betValue =
                [self betFrom:betTexts];

            dispatch_async(dispatch_get_main_queue(), ^{
                self.busy = NO;

                if (!self.running) return;

                [self processBet:betValue];
                [self processBalance:balance];
                [self processResult:result];

                if (self.scans % 15 == 0) {
                    NSMutableArray *raw =
                        [NSMutableArray new];

                    for (NSDictionary *d in balanceTexts)
                        [raw addObject:d[@"text"]];

                    [self log:[NSString stringWithFormat:
                        @"BALANCE OCR RAW: %@",
                        [raw componentsJoinedByString:@" | "]]];

                    [raw removeAllObjects];

                    for (NSDictionary *d in betTexts)
                        [raw addObject:d[@"text"]];

                    [self log:[NSString stringWithFormat:
                        @"BET OCR RAW: %@",
                        [raw componentsJoinedByString:@" | "]]];
                }

                [self refresh];
            });
        }
    });
}

- (void)tick:(NSTimer *)timer {
    if (self.running) [self scan];
}

- (void)toggle {
    if (self.running) {
        self.running = NO;
        [self.timer invalidate];
        self.timer = nil;
        [self log:@"AUTO STOPPED"];
    } else {
        self.running = YES;
        self.hasBalance = NO;
        self.balanceStreak = 0;
        self.betStreak = 0;
        self.resultStreak = 0;
        self.pendingResult = @"";
        self.result = @"";

        self.timer =
            [NSTimer scheduledTimerWithTimeInterval:0.6
                                             target:self
                                           selector:@selector(tick:)
                                           userInfo:nil
                                            repeats:YES];

        [self log:@"AUTO STARTED - CALIBRATION MODE"];
        [self scan];
    }

    [self refresh];
}

- (void)balanceUp {
    self.balanceYPercent =
        MAX(65,self.balanceYPercent-2);
    [self refresh];
    [self log:@"BALANCE AREA UP"];
}

- (void)balanceDown {
    self.balanceYPercent =
        MIN(91,self.balanceYPercent+2);
    [self refresh];
    [self log:@"BALANCE AREA DOWN"];
}

- (void)topUp {
    self.resultYPercent =
        MAX(2,self.resultYPercent-2);
    [self refresh];
    [self log:@"TOP AREA UP"];
}

- (void)topDown {
    self.resultYPercent =
        MIN(75,self.resultYPercent+2);
    [self refresh];
    [self log:@"TOP AREA DOWN"];
}

- (void)copyLog {
    [self log:@"LOG COPIED"];

    UIPasteboard.generalPasteboard.string =
        [self.events componentsJoinedByString:@"\n"];
}

- (UIButton *)button:(NSString *)name
                frame:(CGRect)r
               action:(SEL)a
               parent:(UIView *)v {

    UIButton *b =
        [UIButton buttonWithType:UIButtonTypeSystem];

    b.frame = r;

    [b setTitle:name forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor
           forState:UIControlStateNormal];

    b.backgroundColor =
        [UIColor colorWithWhite:0.22 alpha:1];

    b.titleLabel.font =
        [UIFont boldSystemFontOfSize:11];

    b.layer.cornerRadius = 8;

    [b addTarget:self action:a
     forControlEvents:UIControlEventTouchUpInside];

    [v addSubview:b];
    return b;
}

- (void)move:(UIPanGestureRecognizer *)g {
    CGPoint p =
        [g translationInView:self.panel];

    CGRect r = self.panel.frame;
    r.origin.x += p.x;
    r.origin.y += p.y;
    self.panel.frame = r;

    [g setTranslation:CGPointZero
              inView:self.panel];
}

- (void)showPanel {
    if (self.panel) return;

    UIWindowScene *scene = nil;

    for (UIScene *s in
         UIApplication.sharedApplication.connectedScenes) {

        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState ==
                UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }

    if (!scene) {
        if (++self.attempts < 60)
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                    NSEC_PER_SEC),
                dispatch_get_main_queue(), ^{
                    [self showPanel];
                });
        return;
    }

    CGFloat width =
        MIN(350,scene.coordinateSpace.bounds.size.width-24);

    self.panel =
        [[UIWindow alloc] initWithWindowScene:scene];

    self.panel.frame =
        CGRectMake(12,70,width,400);

    self.panel.windowLevel =
        UIWindowLevelAlert+1;

    UIViewController *vc =
        [UIViewController new];

    vc.view.backgroundColor =
        [UIColor colorWithRed:0.06
                        green:0.08
                         blue:0.12
                        alpha:0.96];

    vc.view.layer.cornerRadius = 12;
    vc.view.clipsToBounds = YES;

    self.panel.rootViewController = vc;

    UILabel *title =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12,8,width-24,28)];

    title.text =
        @"CMSCrystalLogger v12 BALANCE";

    title.textColor = UIColor.whiteColor;
    title.font =
        [UIFont boldSystemFontOfSize:15];

    title.userInteractionEnabled = YES;

    [title addGestureRecognizer:
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(move:)]];

    [vc.view addSubview:title];

    self.statusLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12,40,width-24,21)];

    self.statusLabel.font =
        [UIFont systemFontOfSize:11];

    [vc.view addSubview:self.statusLabel];

    self.balanceLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12,63,width-24,22)];

    self.balanceLabel.textColor =
        UIColor.systemGreenColor;

    [vc.view addSubview:self.balanceLabel];

    self.betLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12,86,width-24,22)];

    self.betLabel.textColor =
        UIColor.whiteColor;

    [vc.view addSubview:self.betLabel];

    self.resultLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12,109,width-24,22)];

    self.resultLabel.textColor =
        UIColor.systemYellowColor;

    [vc.view addSubview:self.resultLabel];

    self.regionLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12,132,width-24,20)];

    self.regionLabel.textColor =
        UIColor.lightGrayColor;

    self.regionLabel.font =
        [UIFont systemFontOfSize:11];

    [vc.view addSubview:self.regionLabel];

    self.logView =
        [[UITextView alloc] initWithFrame:
            CGRectMake(10,158,width-20,132)];

    self.logView.backgroundColor =
        UIColor.clearColor;

    self.logView.textColor =
        UIColor.systemGreenColor;

    self.logView.font =
        [UIFont monospacedSystemFontOfSize:10
                                   weight:UIFontWeightRegular];

    self.logView.editable = NO;

    [vc.view addSubview:self.logView];

    CGFloat gap = 6;
    CGFloat bw = (width-36-2*gap)/3;

    [self button:@"AUTO ON/OFF"
          frame:CGRectMake(12,298,bw,34)
         action:@selector(toggle)
         parent:vc.view];

    [self button:@"COPY LOG"
          frame:CGRectMake(18+bw,298,bw,34)
         action:@selector(copyLog)
         parent:vc.view];

    [self button:@"TOP UP"
          frame:CGRectMake(24+2*bw,298,bw,34)
         action:@selector(topUp)
         parent:vc.view];

    [self button:@"TOP DOWN"
          frame:CGRectMake(12,340,bw,34)
         action:@selector(topDown)
         parent:vc.view];

    [self button:@"BAL UP"
          frame:CGRectMake(18+bw,340,bw,34)
         action:@selector(balanceUp)
         parent:vc.view];

    [self button:@"BAL DOWN"
          frame:CGRectMake(24+2*bw,340,bw,34)
         action:@selector(balanceDown)
         parent:vc.view];

    self.panel.hidden = NO;
    [self.panel makeKeyAndVisible];

    [self refresh];

    [self log:@"V12 READY - BALANCE/BET/TOP OCR"];
    [self log:@"POSSIBLE SPINS ONLY - NOT CONFIRMED"];
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showPanel];
    });
}

@end

__attribute__((constructor))
static void CMSCrystalInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[CMSLogger shared] start];
    });
}

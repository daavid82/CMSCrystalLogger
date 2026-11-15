
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <stdlib.h>

@interface CMSLogger : NSObject
@property(nonatomic,strong) UIWindow *panel;
@property(nonatomic,strong) UITextView *logView;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UILabel *balanceLabel;
@property(nonatomic,strong) UILabel *betLabel;
@property(nonatomic,strong) UILabel *topLabel;
@property(nonatomic,strong) UILabel *areaLabel;
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,strong) NSTimer *timer;

@property(nonatomic,assign) BOOL running;
@property(nonatomic,assign) BOOL busy;
@property(nonatomic,assign) NSInteger attempts;
@property(nonatomic,assign) NSInteger scans;
@property(nonatomic,assign) NSInteger possibleSpins;
@property(nonatomic,assign) NSInteger uncertain;

@property(nonatomic,assign) CGFloat balanceY;
@property(nonatomic,assign) CGFloat balanceX;
@property(nonatomic,assign) CGFloat balanceW;
@property(nonatomic,assign) CGFloat betY;
@property(nonatomic,assign) CGFloat topY;

@property(nonatomic,assign) BOOL trimFive;
@property(nonatomic,assign) BOOL hasBalance;
@property(nonatomic,assign) long long balance;
@property(nonatomic,assign) long long rawBalance;
@property(nonatomic,assign) long long pendingBalance;
@property(nonatomic,assign) NSInteger balanceStreak;

@property(nonatomic,assign) NSInteger bet;
@property(nonatomic,assign) NSInteger pendingBet;
@property(nonatomic,assign) NSInteger betStreak;

@property(nonatomic,copy) NSString *topResult;
@property(nonatomic,copy) NSString *pendingTop;
@property(nonatomic,assign) NSInteger topStreak;

+ (instancetype)shared;
- (void)start;
@end

@implementation CMSLogger

+ (instancetype)shared {
    static CMSLogger *instance;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        instance = [CMSLogger new];
        instance.events = [NSMutableArray new];

        instance.balanceX = 0.39;
        instance.balanceY = 0.828;
        instance.balanceW = 0.23;
        instance.betY = 0.711;
        instance.topY = 0.20;

        instance.trimFive = YES;
        instance.topResult = @"";
        instance.pendingTop = @"";
    });

    return instance;
}

- (void)log:(NSString *)message {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self log:message];
        });
        return;
    }

    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"HH:mm:ss";

    NSString *line = [NSString stringWithFormat:
        @"%@ %@",
        [fmt stringFromDate:[NSDate date]],
        message];

    [self.events addObject:line];

    if (self.events.count > 400)
        [self.events removeObjectAtIndex:0];

    NSString *all =
        [self.events componentsJoinedByString:@"\n"];

    self.logView.text = all;

    if (all.length)
        [self.logView scrollRangeToVisible:
            NSMakeRange(all.length - 1, 1)];

    [all writeToFile:
        [NSTemporaryDirectory()
            stringByAppendingPathComponent:@"CMSCrystalV14.log"]
        atomically:YES
        encoding:NSUTF8StringEncoding
        error:nil];

    NSLog(@"[CMSCrystalV14] %@", line);
}

- (void)refresh {
    self.status.text = [NSString stringWithFormat:
        @"AUTO %@ | SCANS %ld | SPINS? %ld",
        self.running ? @"ON" : @"OFF",
        (long)self.scans,
        (long)self.possibleSpins];

    self.status.textColor =
        self.running ? UIColor.systemGreenColor :
                       UIColor.systemOrangeColor;

    if (self.hasBalance) {
        self.balanceLabel.text =
            [NSString stringWithFormat:
                @"BAL %lld | RAW %lld",
                self.balance,
                self.rawBalance];
    } else {
        self.balanceLabel.text =
            @"BALANCE: WAITING";
    }

    self.betLabel.text = self.bet > 0 ?
        [NSString stringWithFormat:
            @"CURRENT BET: x%ld",
            (long)self.bet] :
        @"CURRENT BET: WAITING";

    self.topLabel.text = [NSString stringWithFormat:
        @"TOP: %@",
        self.topResult.length ?
            self.topResult : @"UNKNOWN"];

    self.areaLabel.text = [NSString stringWithFormat:
        @"TRIM5 %@ | BAL Y %.1f%%",
        self.trimFive ? @"ON" : @"OFF",
        self.balanceY * 100];
}

- (UIWindow *)gameWindow {
    UIWindow *best = nil;

    for (UIScene *scene in
         UIApplication.sharedApplication.connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        for (UIWindow *w in
             ((UIWindowScene *)scene).windows) {

            if (w == self.panel || w.hidden)
                continue;

            if (w.bounds.size.width < 100 ||
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

    UIGraphicsImageRendererFormat *format =
        [UIGraphicsImageRendererFormat defaultFormat];

    format.scale = 1;
    format.opaque = YES;

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc]
            initWithSize:w.bounds.size
                  format:format];

    return [renderer imageWithActions:
        ^(UIGraphicsImageRendererContext *ctx) {
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
                w:(CGFloat)width
                h:(CGFloat)height {

    CGFloat iw = CGImageGetWidth(image);
    CGFloat ih = CGImageGetHeight(image);

    CGRect rect = CGRectMake(
        iw*x, ih*y, iw*width, ih*height);

    rect = CGRectIntersection(
        rect, CGRectMake(0, 0, iw, ih));

    if (CGRectIsEmpty(rect))
        return NULL;

    return CGImageCreateWithImageInRect(
        image, CGRectIntegral(rect));
}

- (NSArray *)ocr:(CGImageRef)image {
    if (!image) return @[];

    VNRecognizeTextRequest *request =
        [VNRecognizeTextRequest new];

    request.recognitionLevel =
        VNRequestTextRecognitionLevelAccurate;

    request.usesLanguageCorrection = NO;
    request.recognitionLanguages = @[@"en-US"];

    VNImageRequestHandler *handler =
        [[VNImageRequestHandler alloc]
            initWithCGImage:image options:@{}];

    NSError *error = nil;

    if (![handler performRequests:@[request]
                            error:&error])
        return @[];

    NSMutableArray *result = [NSMutableArray new];

    for (VNRecognizedTextObservation *obs
         in request.results) {

        VNRecognizedText *text =
            [[obs topCandidates:1] firstObject];

        if (!text) continue;

        [result addObject:@{
            @"text":text.string,
            @"confidence":@(text.confidence)
        }];
    }

    return result;
}

- (NSString *)raw:(NSArray *)items {
    NSMutableArray *parts = [NSMutableArray new];

    for (NSDictionary *d in items)
        [parts addObject:d[@"text"]];

    return [parts componentsJoinedByString:@" | "];
}

- (NSString *)onlyDigits:(NSString *)s {
    NSMutableString *result = [NSMutableString new];

    for (NSUInteger i=0; i<s.length; i++) {
        unichar c = [s characterAtIndex:i];

        if (c >= '0' && c <= '9')
            [result appendFormat:@"%C",c];
    }

    return result;
}

- (long long)readBalance:(NSArray *)items {
    long long best = -1;
    float bestConfidence = -1;

    for (NSDictionary *d in items) {
        NSString *s =
            [d[@"text"] stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet];

        if (![s hasPrefix:@"+"])
            continue;

        NSString *digits =
            [self onlyDigits:
                [s substringFromIndex:1]];

        if (!digits.length || digits.length > 12)
            continue;

        // Reject letters and unrelated UI text.
        NSString *withoutSeparators =
            [[[[s substringFromIndex:1]
                stringByReplacingOccurrencesOfString:@" "
                withString:@""]
                stringByReplacingOccurrencesOfString:@","
                withString:@""]
                stringByReplacingOccurrencesOfString:@"."
                withString:@""];

        if (![withoutSeparators isEqualToString:digits])
            continue;

        float confidence =
            [d[@"confidence"] floatValue];

        if (confidence > bestConfidence) {
            bestConfidence = confidence;
            best = digits.longLongValue;
        }
    }

    return best;
}

- (NSInteger)readBet:(NSArray *)items {
    NSInteger best = 0;
    float bestConfidence = -1;

    for (NSDictionary *d in items) {
        NSString *s =
            [d[@"text"] uppercaseString];

        s = [s stringByReplacingOccurrencesOfString:@" "
                                         withString:@""];

        // Vision may read the green x10 button as *10.
        if (![s hasPrefix:@"X"] &&
            ![s hasPrefix:@"×"] &&
            ![s hasPrefix:@"*"])
            continue;

        NSString *digits =
            [s substringFromIndex:1];

        if (!digits.length || digits.length > 5)
            continue;

        if (![[self onlyDigits:digits]
                isEqualToString:digits])
            continue;

        NSInteger value = digits.integerValue;

        if (value <= 0 || value > 10000)
            continue;

        float confidence =
            [d[@"confidence"] floatValue];

        if (confidence > bestConfidence) {
            bestConfidence = confidence;
            best = value;
        }
    }

    return best;
}

- (NSString *)readTop:(NSArray *)items {
    NSArray *names =
        @[@"ATTACK",@"POINT",@"STEAL",
          @"SHIELD",@"SPINS"];

    NSString *best = @"";
    float bestConfidence = 0;

    for (NSDictionary *d in items) {
        NSString *s =
            [d[@"text"] uppercaseString];

        float confidence =
            [d[@"confidence"] floatValue];

        for (NSString *name in names) {
            if ([s containsString:name] &&
                confidence > bestConfidence) {
                best = name;
                bestConfidence = confidence;
            }
        }
    }

    return bestConfidence >= 0.70 ? best : @"";
}

- (void)processBet:(NSInteger)value {
    if (value <= 0) {
        self.betStreak = 0;
        return;
    }

    if (value == self.pendingBet)
        self.betStreak++;
    else {
        self.pendingBet = value;
        self.betStreak = 1;
    }

    if (self.betStreak >= 2 &&
        value != self.bet) {

        self.bet = value;

        [self log:[NSString stringWithFormat:
            @"CURRENT BET DETECTED: x%ld",
            (long)value]];
    }
}

- (void)processBalance:(long long)raw {
    if (raw < 0) {
        self.balanceStreak = 0;
        return;
    }

    long long value = raw;
    BOOL corrected = NO;

    // Optional, explicit test correction for the
    // observed extra trailing 5.
    // Never apply to arbitrary balances.
    if (self.trimFive &&
        raw >= 1000000 &&
        raw % 10 == 5) {

        value = raw / 10;
        corrected = YES;
    }

    if (value == self.pendingBalance)
        self.balanceStreak++;
    else {
        self.pendingBalance = value;
        self.balanceStreak = 1;
    }

    if (self.balanceStreak < 3)
        return;

    if (!self.hasBalance) {
        self.hasBalance = YES;
        self.balance = value;
        self.rawBalance = raw;

        [self log:[NSString stringWithFormat:
            @"BALANCE BASELINE: %lld | RAW %lld%@",
            value, raw,
            corrected ? @" | TRIM5" : @""]];
        return;
    }

    self.rawBalance = raw;

    if (value == self.balance)
        return;

    long long old = self.balance;
    long long delta = value - old;

    long long limit =
        MAX(100000LL,
            (long long)self.bet * 100LL);

    if (llabs(delta) > limit) {
        // Do not overwrite baseline on a large
        // jump; this may be a missing digit.
        if (self.scans % 10 == 0) {
            [self log:[NSString stringWithFormat:
                @"BALANCE SUSPICIOUS: %lld -> %lld | RAW %lld",
                old, value, raw]];
        }
        return;
    }

    self.balance = value;

    [self log:[NSString stringWithFormat:
        @"BALANCE CHANGE: %lld -> %lld (%+lld) | RAW %lld",
        old, value, delta, raw]];

    if (self.bet > 0 &&
        delta == -(long long)self.bet) {

        self.possibleSpins++;

        [self log:[NSString stringWithFormat:
            @"POSSIBLE SPIN #%ld | BET x%ld",
            (long)self.possibleSpins,
            (long)self.bet]];
    } else {
        self.uncertain++;

        [self log:
            @"UNCLASSIFIED BALANCE CHANGE - WIN/REFUND/OCR?"];
    }
}

- (void)processTop:(NSString *)value {
    if (!value.length) {
        self.pendingTop = @"";
        self.topStreak = 0;
        return;
    }

    if ([value isEqualToString:self.pendingTop])
        self.topStreak++;
    else {
        self.pendingTop = value;
        self.topStreak = 1;
    }

    if (self.topStreak >= 3 &&
        ![value isEqualToString:self.topResult]) {

        self.topResult = value;

        [self log:[NSString stringWithFormat:
            @"POSSIBLE TOP RESULT: %@",value]];
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

    CGImageRef source = image.CGImage;

    CGImageRef balImage =
        [self crop:source
                x:self.balanceX
                y:self.balanceY
                w:self.balanceW
                h:0.036];

    CGImageRef betImage =
        [self crop:source
                x:0.615
                y:self.betY
                w:0.14
                h:0.055];

    CGImageRef topImage =
        [self crop:source
                x:0.20
                y:self.topY
                w:0.60
                h:0.12];

    if (!balImage || !betImage || !topImage) {
        if (balImage) CGImageRelease(balImage);
        if (betImage) CGImageRelease(betImage);
        if (topImage) CGImageRelease(topImage);

        self.busy = NO;
        [self log:@"CROP FAILED"];
        return;
    }

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED,0), ^{
        @autoreleasepool {

            NSArray *balTexts = [self ocr:balImage];
            NSArray *betTexts = [self ocr:betImage];
            NSArray *topTexts = [self ocr:topImage];

            CGImageRelease(balImage);
            CGImageRelease(betImage);
            CGImageRelease(topImage);

            long long rawBalance =
                [self readBalance:balTexts];

            NSInteger bet =
                [self readBet:betTexts];

            NSString *top =
                [self readTop:topTexts];

            dispatch_async(dispatch_get_main_queue(), ^{
                self.busy = NO;

                if (!self.running)
                    return;

                [self processBet:bet];
                [self processBalance:rawBalance];
                [self processTop:top];

                if (self.scans % 10 == 0) {
                    [self log:[NSString stringWithFormat:
                        @"BAL OCR RAW: %@",
                        [self raw:balTexts]]];

                    [self log:[NSString stringWithFormat:
                        @"BET OCR RAW: %@",
                        [self raw:betTexts]]];

                    [self log:[NSString stringWithFormat:
                        @"TOP OCR RAW: %@",
                        [self raw:topTexts]]];
                }

                [self refresh];
            });
        }
    });
}

- (void)tick:(NSTimer *)timer {
    if (self.running)
        [self scan];
}

- (void)resetBaseline {
    self.hasBalance = NO;
    self.balanceStreak = 0;
    self.pendingBalance = 0;
    self.rawBalance = 0;
    [self refresh];
    [self log:@"BALANCE BASELINE RESET"];
}

- (void)toggleTrim {
    self.trimFive = !self.trimFive;
    [self resetBaseline];

    [self log:[NSString stringWithFormat:
        @"TRIM5 %@",
        self.trimFive ? @"ON" : @"OFF"]];

    [self refresh];
}

- (void)toggle {
    if (self.running) {
        self.running = NO;
        [self.timer invalidate];
        self.timer = nil;
        [self log:@"AUTO STOPPED"];
    } else {
        self.running = YES;
        self.scans = 0;
        self.possibleSpins = 0;
        self.uncertain = 0;
        self.bet = 0;
        self.betStreak = 0;
        self.topStreak = 0;
        self.topResult = @"";
        self.pendingTop = @"";
        [self resetBaseline];

        self.timer =
            [NSTimer scheduledTimerWithTimeInterval:0.6
                                             target:self
                                           selector:@selector(tick:)
                                           userInfo:nil
                                            repeats:YES];

        [self log:@"AUTO STARTED - V14"];
        [self scan];
    }

    [self refresh];
}

- (void)balanceUp {
    self.balanceY =
        MAX(0.70,self.balanceY-0.01);
    [self resetBaseline];
    [self log:@"BALANCE AREA UP"];
}

- (void)balanceDown {
    self.balanceY =
        MIN(0.90,self.balanceY+0.01);
    [self resetBaseline];
    [self log:@"BALANCE AREA DOWN"];
}

- (void)balanceNarrow {
    self.balanceW =
        MAX(0.15,self.balanceW-0.01);
    [self resetBaseline];
    [self log:@"BALANCE AREA NARROWER"];
}

- (void)balanceWide {
    self.balanceW =
        MIN(0.35,self.balanceW+0.01);
    [self resetBaseline];
    [self log:@"BALANCE AREA WIDER"];
}

- (void)copyLog {
    [self log:@"LOG COPIED"];

    UIPasteboard.generalPasteboard.string =
        [self.events componentsJoinedByString:@"\n"];
}

- (UIButton *)button:(NSString *)title
                frame:(CGRect)frame
               action:(SEL)action
               parent:(UIView *)parent {

    UIButton *button =
        [UIButton buttonWithType:UIButtonTypeSystem];

    button.frame = frame;
    [button setTitle:title
           forState:UIControlStateNormal];

    [button setTitleColor:UIColor.whiteColor
                forState:UIControlStateNormal];

    button.backgroundColor =
        [UIColor colorWithWhite:0.22 alpha:1];

    button.titleLabel.font =
        [UIFont boldSystemFontOfSize:11];

    button.layer.cornerRadius = 8;

    [button addTarget:self
               action:action
     forControlEvents:UIControlEventTouchUpInside];

    [parent addSubview:button];
    return button;
}

- (void)move:(UIPanGestureRecognizer *)gesture {
    CGPoint p =
        [gesture translationInView:self.panel];

    CGRect r = self.panel.frame;
    r.origin.x += p.x;
    r.origin.y += p.y;

    self.panel.frame = r;

    [gesture setTranslation:CGPointZero
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
        MIN(350,
            scene.coordinateSpace.bounds.size.width-24);

    self.panel =
        [[UIWindow alloc] initWithWindowScene:scene];

    self.panel.frame =
        CGRectMake(12,70,width,435);

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
        @"CMSCrystalLogger v14 SPIN FIX";

    title.textColor = UIColor.whiteColor;
    title.font =
        [UIFont boldSystemFontOfSize:15];

    title.userInteractionEnabled = YES;

    [title addGestureRecognizer:
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(move:)]];

    [vc.view addSubview:title];

    self.status =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12,42,width-24,22)];

    self.status.font =
        [UIFont systemFontOfSize:11];

    [vc.view addSubview:self.status];

    self.balanceLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12,68,width-24,26)];

    self.balanceLabel.textColor =
        UIColor.systemGreenColor;

    self.balanceLabel.font =
        [UIFont boldSystemFontOfSize:15];

    [vc.view addSubview:self.balanceLabel];

    self.betLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12,98,width-24,24)];

    self.betLabel.textColor = UIColor.whiteColor;
    [vc.view addSubview:self.betLabel];

    self.topLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12,126,width-24,24)];

    self.topLabel.textColor =
        UIColor.systemYellowColor;

    [vc.view addSubview:self.topLabel];

    self.areaLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12,152,width-24,22)];

    self.areaLabel.textColor =
        UIColor.lightGrayColor;

    self.areaLabel.font =
        [UIFont systemFontOfSize:11];

    [vc.view addSubview:self.areaLabel];

    self.logView =
        [[UITextView alloc] initWithFrame:
            CGRectMake(10,180,width-20,132)];

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
          frame:CGRectMake(12,320,bw,32)
         action:@selector(toggle)
         parent:vc.view];

    [self button:@"COPY LOG"
          frame:CGRectMake(18+bw,320,bw,32)
         action:@selector(copyLog)
         parent:vc.view];

    [self button:@"TRIM5 ON/OFF"
          frame:CGRectMake(24+2*bw,320,bw,32)
         action:@selector(toggleTrim)
         parent:vc.view];

    [self button:@"BAL UP"
          frame:CGRectMake(12,360,bw,32)
         action:@selector(balanceUp)
         parent:vc.view];

    [self button:@"BAL DOWN"
          frame:CGRectMake(18+bw,360,bw,32)
         action:@selector(balanceDown)
         parent:vc.view];

    [self button:@"RESET BAL"
          frame:CGRectMake(24+2*bw,360,bw,32)
         action:@selector(resetBaseline)
         parent:vc.view];

    CGFloat half = (width-30)/2;

    [self button:@"BAL NARROW"
          frame:CGRectMake(12,400,half,28)
         action:@selector(balanceNarrow)
         parent:vc.view];

    [self button:@"BAL WIDE"
          frame:CGRectMake(18+half,400,half,28)
         action:@selector(balanceWide)
         parent:vc.view];

    self.panel.hidden = NO;
    [self.panel makeKeyAndVisible];

    [self refresh];

    [self log:@"V14 READY"];
    [self log:@"BET OCR ACCEPTS X / MULTIPLY / STAR"];
    [self log:@"TRIM5 TEST MODE ENABLED"];
    [self log:@"NO CONFIRMED RESULT COUNTS"];
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

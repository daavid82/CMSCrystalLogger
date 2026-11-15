
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <math.h>

@interface CMSLogger : NSObject

@property(nonatomic,strong) UIWindow *panel;
@property(nonatomic,strong) UITextView *logView;
@property(nonatomic,strong) UILabel *statusLabel;
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

@property(nonatomic,assign) CGFloat balanceY;
@property(nonatomic,assign) CGFloat betY;
@property(nonatomic,assign) CGFloat topY;

@property(nonatomic,assign) long long balance;
@property(nonatomic,assign) long long pendingBalance;
@property(nonatomic,assign) NSInteger balanceStreak;
@property(nonatomic,assign) BOOL hasBalance;

@property(nonatomic,assign) NSInteger currentBet;
@property(nonatomic,assign) NSInteger pendingBet;
@property(nonatomic,assign) NSInteger betStreak;

@property(nonatomic,copy) NSString *topResult;
@property(nonatomic,copy) NSString *pendingTop;
@property(nonatomic,assign) NSInteger topStreak;

@property(nonatomic,assign) NSInteger possibleSpins;
@property(nonatomic,assign) NSInteger uncertainChanges;

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

        // Positions based on the supplied iPhone screenshot.
        instance.balanceY = 0.828;
        instance.betY = 0.711;
        instance.topY = 0.20;

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

    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"HH:mm:ss";

    NSString *line = [NSString stringWithFormat:
        @"%@ %@", [f stringFromDate:[NSDate date]], message];

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
            stringByAppendingPathComponent:@"CMSCrystalV13.log"]
        atomically:YES
        encoding:NSUTF8StringEncoding
        error:nil];

    NSLog(@"[CMSCrystalV13] %@", line);
}

- (void)refresh {
    self.statusLabel.text = [NSString stringWithFormat:
        @"AUTO %@ | SCANS %ld | SPINS? %ld",
        self.running ? @"ON" : @"OFF",
        (long)self.scans,
        (long)self.possibleSpins];

    self.statusLabel.textColor =
        self.running ? UIColor.systemGreenColor :
                       UIColor.systemOrangeColor;

    self.balanceLabel.text = self.hasBalance ?
        [NSString stringWithFormat:
            @"BALANCE: %lld", self.balance] :
        @"BALANCE: WAITING";

    self.betLabel.text = self.currentBet > 0 ?
        [NSString stringWithFormat:
            @"CURRENT BET: x%ld", (long)self.currentBet] :
        @"CURRENT BET: WAITING";

    self.topLabel.text = [NSString stringWithFormat:
        @"TOP: %@",
        self.topResult.length ? self.topResult : @"UNKNOWN"];

    self.areaLabel.text = [NSString stringWithFormat:
        @"BAL %.1f%% | BET %.1f%% | TOP %.0f%%",
        self.balanceY * 100,
        self.betY * 100,
        self.topY * 100];
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

    format.scale = 1.0;
    format.opaque = YES;

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc]
            initWithSize:w.bounds.size
                  format:format];

    return [renderer imageWithActions:
        ^(UIGraphicsImageRendererContext *context) {
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
        iw * x,
        ih * y,
        iw * width,
        ih * height);

    rect = CGRectIntersection(
        rect,
        CGRectMake(0, 0, iw, ih));

    if (CGRectIsEmpty(rect))
        return NULL;

    return CGImageCreateWithImageInRect(
        image, CGRectIntegral(rect));
}

- (NSArray<NSDictionary *> *)ocr:(CGImageRef)image {
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

    BOOL ok = [handler performRequests:@[request]
                                 error:&error];

    if (!ok) return @[];

    NSMutableArray *items = [NSMutableArray new];

    for (VNRecognizedTextObservation *obs
         in request.results) {

        VNRecognizedText *text =
            [[obs topCandidates:1] firstObject];

        if (!text) continue;

        [items addObject:@{
            @"text": text.string,
            @"confidence": @(text.confidence)
        }];
    }

    return items;
}

- (NSString *)raw:(NSArray<NSDictionary *> *)items {
    NSMutableArray *parts = [NSMutableArray new];

    for (NSDictionary *item in items) {
        [parts addObject:item[@"text"]];
    }

    return [parts componentsJoinedByString:@" | "];
}

- (long long)digits:(NSString *)text {
    NSMutableString *s = [NSMutableString new];

    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];

        if (c >= '0' && c <= '9')
            [s appendFormat:@"%C", c];
    }

    if (!s.length || s.length > 12)
        return -1;

    return s.longLongValue;
}

- (long long)readBalance:
    (NSArray<NSDictionary *> *)items {

    long long best = -1;
    float confidence = -1;

    for (NSDictionary *item in items) {
        NSString *text = item[@"text"];

        NSString *trim =
            [text stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet];

        if (![trim hasPrefix:@"+"])
            continue;

        // Do not accept arbitrary extra text.
        NSString *numberText =
            [trim substringFromIndex:1];

        NSMutableString *clean =
            [NSMutableString new];

        BOOL valid = YES;

        for (NSUInteger i = 0;
             i < numberText.length; i++) {

            unichar c =
                [numberText characterAtIndex:i];

            if (c >= '0' && c <= '9') {
                [clean appendFormat:@"%C", c];
            } else if (c == ' ' || c == ',' ||
                       c == '.') {
                // Allow common number separators.
            } else {
                valid = NO;
                break;
            }
        }

        if (!valid || !clean.length ||
            clean.length > 12)
            continue;

        long long value = clean.longLongValue;
        float c = [item[@"confidence"] floatValue];

        if (c > confidence) {
            confidence = c;
            best = value;
        }
    }

    return best;
}

- (NSInteger)readCurrentBet:
    (NSArray<NSDictionary *> *)items {

    NSInteger best = 0;
    float confidence = -1;

    for (NSDictionary *item in items) {
        NSString *s =
            [item[@"text"] uppercaseString];

        s = [s stringByReplacingOccurrencesOfString:@" "
                                         withString:@""];

        // This crop contains the small green x1/x10
        // button, not the MAX BET banner.
        if (![s hasPrefix:@"X"] &&
            ![s hasPrefix:@"×"])
            continue;

        long long value =
            [self digits:[s substringFromIndex:1]];

        if (value <= 0 || value > 100000)
            continue;

        float c = [item[@"confidence"] floatValue];

        if (c > confidence) {
            confidence = c;
            best = (NSInteger)value;
        }
    }

    return best;
}

- (NSString *)readTop:
    (NSArray<NSDictionary *> *)items {

    NSArray *names =
        @[@"ATTACK", @"POINT", @"STEAL",
          @"SHIELD", @"SPINS"];

    NSString *best = @"";
    float bestConfidence = 0;

    for (NSDictionary *item in items) {
        NSString *text =
            [item[@"text"] uppercaseString];

        float confidence =
            [item[@"confidence"] floatValue];

        for (NSString *name in names) {
            if ([text containsString:name] &&
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

    if (self.betStreak >= 3 &&
        self.currentBet != value) {

        self.currentBet = value;

        [self log:[NSString stringWithFormat:
            @"CURRENT BET DETECTED: x%ld",
            (long)value]];
    }
}

- (void)processBalance:(long long)value {
    if (value < 0) {
        self.balanceStreak = 0;
        return;
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

        [self log:[NSString stringWithFormat:
            @"BALANCE BASELINE: %lld", value]];
        return;
    }

    if (value == self.balance)
        return;

    long long old = self.balance;
    long long delta = value - old;

    // Reject very large jumps as OCR errors.
    // Do not silently overwrite the baseline.
    long long limit = MAX(
        100000LL,
        (long long)self.currentBet * 100LL);

    if (llabs(delta) > limit) {
        [self log:[NSString stringWithFormat:
            @"BALANCE SUSPICIOUS: %lld -> %lld",
            old, value]];
        return;
    }

    self.balance = value;

    [self log:[NSString stringWithFormat:
        @"BALANCE CHANGE: %lld -> %lld (%+lld)",
        old, value, delta]];

    if (self.currentBet > 0 &&
        delta == -(long long)self.currentBet) {

        self.possibleSpins++;

        [self log:[NSString stringWithFormat:
            @"POSSIBLE SPIN #%ld | BET x%ld",
            (long)self.possibleSpins,
            (long)self.currentBet]];

    } else {
        self.uncertainChanges++;

        [self log:
            @"BALANCE CHANGE UNCLASSIFIED - WIN/REFUND/OCR?"];
    }
}

- (void)processTop:(NSString *)value {
    if (!value.length) {
        self.topStreak = 0;
        self.pendingTop = @"";
        return;
    }

    if ([value isEqualToString:self.pendingTop])
        self.topStreak++;
    else {
        self.pendingTop = value;
        self.topStreak = 1;
    }

    if (self.topStreak == 3 &&
        ![value isEqualToString:self.topResult]) {

        self.topResult = value;

        [self log:[NSString stringWithFormat:
            @"POSSIBLE TOP RESULT: %@", value]];
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

    CGImageRef balanceImage =
        [self crop:source
                x:0.39
                y:self.balanceY
                w:0.23
                h:0.036];

    CGImageRef betImage =
        [self crop:source
                x:0.615
                y:self.betY
                w:0.14
                h:0.055];

    CGImageRef topImage =
        [self crop:source
                x:0.12
                y:self.topY
                w:0.76
                h:0.16];

    if (!balanceImage || !betImage || !topImage) {
        if (balanceImage) CGImageRelease(balanceImage);
        if (betImage) CGImageRelease(betImage);
        if (topImage) CGImageRelease(topImage);

        self.busy = NO;
        [self log:@"CROP FAILED"];
        return;
    }

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {

            NSArray *balanceTexts =
                [self ocr:balanceImage];

            NSArray *betTexts =
                [self ocr:betImage];

            NSArray *topTexts =
                [self ocr:topImage];

            CGImageRelease(balanceImage);
            CGImageRelease(betImage);
            CGImageRelease(topImage);

            long long balance =
                [self readBalance:balanceTexts];

            NSInteger bet =
                [self readCurrentBet:betTexts];

            NSString *top =
                [self readTop:topTexts];

            dispatch_async(dispatch_get_main_queue(), ^{
                self.busy = NO;

                if (!self.running)
                    return;

                [self processBet:bet];
                [self processBalance:balance];
                [self processTop:top];

                if (self.scans % 10 == 0) {
                    [self log:[NSString stringWithFormat:
                        @"BAL OCR RAW: %@",
                        [self raw:balanceTexts]]];

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
        self.topStreak = 0;
        self.pendingTop = @"";
        self.topResult = @"";

        self.timer =
            [NSTimer scheduledTimerWithTimeInterval:0.6
                                             target:self
                                           selector:@selector(tick:)
                                           userInfo:nil
                                            repeats:YES];

        [self log:@"AUTO STARTED - V13"];
        [self scan];
    }

    [self refresh];
}

- (void)balanceUp {
    self.balanceY = MAX(0.70, self.balanceY - 0.01);
    [self refresh];
    [self log:@"BALANCE AREA UP"];
}

- (void)balanceDown {
    self.balanceY = MIN(0.90, self.balanceY + 0.01);
    [self refresh];
    [self log:@"BALANCE AREA DOWN"];
}

- (void)betUp {
    self.betY = MAX(0.60, self.betY - 0.01);
    [self refresh];
    [self log:@"BET AREA UP"];
}

- (void)betDown {
    self.betY = MIN(0.85, self.betY + 0.01);
    [self refresh];
    [self log:@"BET AREA DOWN"];
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

    UIButton *b =
        [UIButton buttonWithType:UIButtonTypeSystem];

    b.frame = frame;
    [b setTitle:title forState:UIControlStateNormal];

    [b setTitleColor:UIColor.whiteColor
           forState:UIControlStateNormal];

    b.backgroundColor =
        [UIColor colorWithWhite:0.22 alpha:1];

    b.titleLabel.font =
        [UIFont boldSystemFontOfSize:11];

    b.layer.cornerRadius = 8;

    [b addTarget:self
          action:action
forControlEvents:UIControlEventTouchUpInside];

    [parent addSubview:b];
    return b;
}

- (void)movePanel:(UIPanGestureRecognizer *)gesture {
    CGPoint p = [gesture translationInView:self.panel];

    CGRect frame = self.panel.frame;
    frame.origin.x += p.x;
    frame.origin.y += p.y;

    self.panel.frame = frame;

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
            scene.coordinateSpace.bounds.size.width - 24);

    self.panel =
        [[UIWindow alloc] initWithWindowScene:scene];

    self.panel.frame =
        CGRectMake(12, 70, width, 405);

    self.panel.windowLevel =
        UIWindowLevelAlert + 1;

    UIViewController *vc = [UIViewController new];

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
            CGRectMake(12, 8, width - 24, 28)];

    title.text = @"CMSCrystalLogger v13";
    title.textColor = UIColor.whiteColor;
    title.font =
        [UIFont boldSystemFontOfSize:16];

    title.userInteractionEnabled = YES;

    [title addGestureRecognizer:
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(movePanel:)]];

    [vc.view addSubview:title];

    self.statusLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 42, width - 24, 22)];

    self.statusLabel.font =
        [UIFont systemFontOfSize:12];

    [vc.view addSubview:self.statusLabel];

    self.balanceLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 68, width - 24, 26)];

    self.balanceLabel.textColor =
        UIColor.systemGreenColor;

    self.balanceLabel.font =
        [UIFont boldSystemFontOfSize:17];

    [vc.view addSubview:self.balanceLabel];

    self.betLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 98, width - 24, 24)];

    self.betLabel.textColor = UIColor.whiteColor;
    self.betLabel.font =
        [UIFont boldSystemFontOfSize:15];

    [vc.view addSubview:self.betLabel];

    self.topLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 126, width - 24, 24)];

    self.topLabel.textColor =
        UIColor.systemYellowColor;

    [vc.view addSubview:self.topLabel];

    self.areaLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 153, width - 24, 20)];

    self.areaLabel.textColor =
        UIColor.lightGrayColor;

    self.areaLabel.font =
        [UIFont systemFontOfSize:11];

    [vc.view addSubview:self.areaLabel];

    self.logView =
        [[UITextView alloc] initWithFrame:
            CGRectMake(10, 178, width - 20, 128)];

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
    CGFloat bw = (width - 36 - gap * 2) / 3;

    [self button:@"AUTO ON/OFF"
          frame:CGRectMake(12, 313, bw, 34)
         action:@selector(toggle)
         parent:vc.view];

    [self button:@"COPY LOG"
          frame:CGRectMake(18 + bw, 313, bw, 34)
         action:@selector(copyLog)
         parent:vc.view];

    [self button:@"BAL UP"
          frame:CGRectMake(24 + 2*bw, 313, bw, 34)
         action:@selector(balanceUp)
         parent:vc.view];

    [self button:@"BAL DOWN"
          frame:CGRectMake(12, 355, bw, 34)
         action:@selector(balanceDown)
         parent:vc.view];

    [self button:@"BET UP"
          frame:CGRectMake(18 + bw, 355, bw, 34)
         action:@selector(betUp)
         parent:vc.view];

    [self button:@"BET DOWN"
          frame:CGRectMake(24 + 2*bw, 355, bw, 34)
         action:@selector(betDown)
         parent:vc.view];

    self.panel.hidden = NO;
    [self.panel makeKeyAndVisible];

    [self refresh];

    [self log:@"V13 READY"];
    [self log:@"CURRENT BET FROM GREEN BUTTON"];
    [self log:@"BALANCE FROM UNDER SPIN BUTTON"];
    [self log:@"CANDIDATES ONLY - NOT CONFIRMED"];
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

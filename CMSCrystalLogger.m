
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <stdlib.h>
#import <math.h>

@interface CMSLogger : NSObject

@property(nonatomic,strong) UIWindow *panel;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UILabel *balanceLabel;
@property(nonatomic,strong) UILabel *betLabel;
@property(nonatomic,strong) UILabel *spinLabel;
@property(nonatomic,strong) UILabel *topLabel;
@property(nonatomic,strong) UILabel *screenLabel;
@property(nonatomic,strong) UITextView *logView;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) NSMutableArray *events;

@property(nonatomic,assign) BOOL running;
@property(nonatomic,assign) BOOL busy;
@property(nonatomic,assign) BOOL hasBalance;
@property(nonatomic,assign) BOOL gameVisible;
@property(nonatomic,assign) BOOL trimFive;
@property(nonatomic,assign) BOOL trimLocked;

@property(nonatomic,assign) NSInteger attempts;
@property(nonatomic,assign) NSInteger scans;
@property(nonatomic,assign) NSInteger missedFrames;
@property(nonatomic,assign) NSInteger visibleFrames;

@property(nonatomic,assign) NSInteger bet;
@property(nonatomic,assign) NSInteger pendingBet;
@property(nonatomic,assign) NSInteger betStreak;

@property(nonatomic,assign) long long balance;
@property(nonatomic,assign) long long rawBalance;
@property(nonatomic,assign) long long pendingBalance;
@property(nonatomic,assign) NSInteger balanceStreak;

@property(nonatomic,assign) NSInteger estimatedSpins;
@property(nonatomic,assign) NSInteger confirmedSpins;
@property(nonatomic,assign) NSInteger uncertainEvents;
@property(nonatomic,assign) NSInteger positiveEvents;

@property(nonatomic,assign) CGFloat balanceY;
@property(nonatomic,assign) CGFloat balanceX;
@property(nonatomic,assign) CGFloat balanceW;
@property(nonatomic,assign) CGFloat betY;
@property(nonatomic,assign) CGFloat topY;

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

        // Initial test preference, not a permanent
        // assumption about every balance.
        instance.trimFive = YES;
        instance.trimLocked = NO;

        instance.topResult = @"";
        instance.pendingTop = @"";
    });

    return instance;
}

#pragma mark - Logging

- (void)log:(NSString *)message {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self log:message];
        });
        return;
    }

    NSDateFormatter *formatter =
        [NSDateFormatter new];

    formatter.dateFormat = @"HH:mm:ss";

    NSString *line = [NSString stringWithFormat:
        @"%@ %@",
        [formatter stringFromDate:[NSDate date]],
        message];

    [self.events addObject:line];

    if (self.events.count > 600)
        [self.events removeObjectAtIndex:0];

    NSString *all =
        [self.events componentsJoinedByString:@"\n"];

    if (self.logView) {
        self.logView.text = all;

        if (all.length > 0)
            [self.logView scrollRangeToVisible:
                NSMakeRange(all.length - 1, 1)];
    }

    NSString *path =
        [NSTemporaryDirectory()
            stringByAppendingPathComponent:
                @"CMSCrystalV15.log"];

    [all writeToFile:path
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:nil];

    NSLog(@"[CMSCrystalV15] %@", line);
}

- (void)refresh {
    self.statusLabel.text =
        [NSString stringWithFormat:
            @"AUTO %@  |  SCANS %ld",
            self.running ? @"ON" : @"OFF",
            (long)self.scans];

    self.statusLabel.textColor =
        self.running ?
            UIColor.systemGreenColor :
            UIColor.systemOrangeColor;

    self.balanceLabel.text =
        self.hasBalance ?
            [NSString stringWithFormat:
                @"BAL %lld   RAW %lld",
                self.balance,
                self.rawBalance] :
            @"BALANCE: WAITING";

    self.betLabel.text =
        self.bet > 0 ?
            [NSString stringWithFormat:
                @"CURRENT BET: x%ld",
                (long)self.bet] :
            @"CURRENT BET: WAITING";

    self.spinLabel.text =
        [NSString stringWithFormat:
            @"EST %ld  |  CONF %ld  |  ? %ld",
            (long)self.estimatedSpins,
            (long)self.confirmedSpins,
            (long)self.uncertainEvents];

    self.topLabel.text =
        [NSString stringWithFormat:
            @"TOP CANDIDATE: %@",
            self.topResult.length ?
                self.topResult : @"UNKNOWN"];

    self.screenLabel.text =
        [NSString stringWithFormat:
            @"SCREEN: %@  |  TRIM5: %@",
            self.gameVisible ?
                @"GAME" : @"OTHER / UNKNOWN",
            self.trimFive ? @"ON" : @"OFF"];
}

#pragma mark - Capture

- (UIWindow *)gameWindow {
    UIWindow *best = nil;

    for (UIScene *scene in
         UIApplication.sharedApplication.connectedScenes) {

        if (![scene isKindOfClass:
                [UIWindowScene class]])
            continue;

        for (UIWindow *window in
             ((UIWindowScene *)scene).windows) {

            if (window == self.panel ||
                window.hidden)
                continue;

            if (window.bounds.size.width < 100 ||
                window.bounds.size.height < 100)
                continue;

            if (!best ||
                window.windowLevel < best.windowLevel)
                best = window;
        }
    }

    return best;
}

- (UIImage *)capture {
    UIWindow *window = [self gameWindow];

    if (!window)
        return nil;

    UIGraphicsImageRendererFormat *format =
        [UIGraphicsImageRendererFormat
            defaultFormat];

    format.scale = 1;
    format.opaque = YES;

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc]
            initWithSize:window.bounds.size
                  format:format];

    return [renderer imageWithActions:
        ^(UIGraphicsImageRendererContext *ctx) {

            [window drawViewHierarchyInRect:
                CGRectMake(0, 0,
                    window.bounds.size.width,
                    window.bounds.size.height)
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

    CGRect rect =
        CGRectMake(iw*x,
                   ih*y,
                   iw*width,
                   ih*height);

    rect = CGRectIntersection(
        rect,
        CGRectMake(0,0,iw,ih));

    if (CGRectIsEmpty(rect))
        return NULL;

    return CGImageCreateWithImageInRect(
        image,
        CGRectIntegral(rect));
}

#pragma mark - OCR

- (NSArray *)ocr:(CGImageRef)image {
    if (!image)
        return @[];

    VNRecognizeTextRequest *request =
        [VNRecognizeTextRequest new];

    request.recognitionLevel =
        VNRequestTextRecognitionLevelAccurate;

    request.usesLanguageCorrection = NO;
    request.recognitionLanguages =
        @[@"en-US"];

    VNImageRequestHandler *handler =
        [[VNImageRequestHandler alloc]
            initWithCGImage:image
                    options:@{}];

    NSError *error = nil;

    if (![handler performRequests:@[request]
                            error:&error])
        return @[];

    NSMutableArray *result =
        [NSMutableArray new];

    for (VNRecognizedTextObservation *obs
         in request.results) {

        VNRecognizedText *text =
            [[obs topCandidates:1] firstObject];

        if (!text)
            continue;

        [result addObject:@{
            @"text":text.string,
            @"confidence":@(text.confidence)
        }];
    }

    return result;
}

- (NSString *)raw:(NSArray *)items {
    NSMutableArray *parts =
        [NSMutableArray new];

    for (NSDictionary *item in items)
        [parts addObject:item[@"text"]];

    return [parts componentsJoinedByString:@" | "];
}

- (NSString *)digits:(NSString *)text {
    NSMutableString *result =
        [NSMutableString new];

    for (NSUInteger i=0; i<text.length; i++) {
        unichar c = [text characterAtIndex:i];

        if (c >= '0' && c <= '9')
            [result appendFormat:@"%C",c];
    }

    return result;
}

- (long long)readRawBalance:(NSArray *)items {
    float bestConfidence = -1;
    long long best = -1;

    for (NSDictionary *item in items) {
        NSString *text =
            [item[@"text"]
                stringByTrimmingCharactersInSet:
                    NSCharacterSet
                        .whitespaceAndNewlineCharacterSet];

        if (![text hasPrefix:@"+"])
            continue;

        NSString *rest =
            [text substringFromIndex:1];

        NSString *number =
            [self digits:rest];

        if (number.length < 4 ||
            number.length > 12)
            continue;

        NSString *clean =
            [[[rest
                stringByReplacingOccurrencesOfString:@" "
                withString:@""]
                stringByReplacingOccurrencesOfString:@","
                withString:@""]
                stringByReplacingOccurrencesOfString:@"."
                withString:@""];

        if (![clean isEqualToString:number])
            continue;

        float confidence =
            [item[@"confidence"] floatValue];

        if (confidence > bestConfidence) {
            bestConfidence = confidence;
            best = number.longLongValue;
        }
    }

    return best;
}

- (NSInteger)readBet:(NSArray *)items {
    float bestConfidence = -1;
    NSInteger best = 0;

    for (NSDictionary *item in items) {
        NSString *text =
            [item[@"text"] uppercaseString];

        text =
            [text stringByReplacingOccurrencesOfString:@" "
                                            withString:@""];

        if (![text hasPrefix:@"X"] &&
            ![text hasPrefix:@"×"] &&
            ![text hasPrefix:@"*"])
            continue;

        NSString *number =
            [text substringFromIndex:1];

        if (number.length < 1 ||
            number.length > 5 ||
            ![[self digits:number]
                isEqualToString:number])
            continue;

        NSInteger value = number.integerValue;

        if (value <= 0 || value > 10000)
            continue;

        float confidence =
            [item[@"confidence"] floatValue];

        if (confidence > bestConfidence) {
            bestConfidence = confidence;
            best = value;
        }
    }

    return best;
}

- (NSString *)readTop:(NSArray *)items {
    NSArray *names =
        @[@"ATTACK", @"POINT", @"STEAL",
          @"SHIELD", @"SPINS"];

    NSString *best = @"";
    float confidence = 0;

    for (NSDictionary *item in items) {
        NSString *text =
            [item[@"text"] uppercaseString];

        float score =
            [item[@"confidence"] floatValue];

        for (NSString *name in names) {
            if ([text containsString:name] &&
                score > confidence) {

                confidence = score;
                best = name;
            }
        }
    }

    return confidence >= 0.75 ? best : @"";
}

#pragma mark - Bet tracking

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
        self.bet != value) {

        self.bet = value;

        [self log:[NSString stringWithFormat:
            @"BET VERIFIED: x%ld",
            (long)value]];
    }
}

#pragma mark - Smart balance

- (long long)normalizedBalance:(long long)raw {
    if (raw < 0)
        return -1;

    if (!self.trimFive)
        return raw;

    // An extra trailing 5 has been observed.
    // Apply only when the candidate has seven
    // digits and ends in 5.
    if (raw >= 1000000 &&
        raw <= 9999999 &&
        raw % 10 == 5)
        return raw / 10;

    return raw;
}

- (void)processBalance:(long long)raw {
    if (raw < 0) {
        self.balanceStreak = 0;
        return;
    }

    long long value =
        [self normalizedBalance:raw];

    if (value == self.pendingBalance)
        self.balanceStreak++;
    else {
        self.pendingBalance = value;
        self.balanceStreak = 1;
    }

    if (self.balanceStreak < 3)
        return;

    if (!self.hasBalance) {
        self.balance = value;
        self.rawBalance = raw;
        self.hasBalance = YES;

        [self log:[NSString stringWithFormat:
            @"BALANCE BASELINE: %lld | RAW %lld",
            value,raw]];
        return;
    }

    self.rawBalance = raw;

    if (value == self.balance)
        return;

    long long old = self.balance;
    long long delta = value - old;

    // Reject missing-digit OCR values.
    if (llabs(delta) > 100000) {
        if (self.scans % 10 == 0)
            [self log:[NSString stringWithFormat:
                @"OCR REJECTED: %lld -> %lld",
                old,value]];
        return;
    }

    // The game may be showing a bonus, refund,
    // or a different state. Never claim that
    // a balance change proves a spin.
    self.balance = value;

    [self log:[NSString stringWithFormat:
        @"BALANCE: %lld -> %lld (%+lld)",
        old,value,delta]];

    if (delta > 0) {
        self.positiveEvents++;

        [self log:[NSString stringWithFormat:
            @"BALANCE INCREASE +%lld | BONUS/REFUND/OTHER",
            delta]];
        return;
    }

    if (self.bet <= 0) {
        self.uncertainEvents++;
        [self log:@"NEGATIVE DELTA: BET UNKNOWN"];
        return;
    }

    long long spent = -delta;

    if (spent % self.bet == 0) {
        long long count = spent / self.bet;

        // Cap one observation to avoid
        // interpreting large jumps as many spins.
        if (count >= 1 && count <= 100) {
            self.estimatedSpins += (NSInteger)count;

            [self log:[NSString stringWithFormat:
                @"ESTIMATED SPINS +%lld | TOTAL %ld | BET x%ld",
                count,
                (long)self.estimatedSpins,
                (long)self.bet]];

            if (count > 1)
                [self log:
                    @"MULTIPLE POSSIBLE SPINS - NOT VERIFIED"];

            return;
        }
    }

    self.uncertainEvents++;

    [self log:[NSString stringWithFormat:
        @"UNCLASSIFIED DELTA %lld | BET x%ld",
        delta,(long)self.bet]];
}

#pragma mark - Screen and results

- (void)processVisibility:(BOOL)visible {
    if (visible) {
        self.visibleFrames++;
        self.missedFrames = 0;

        if (!self.gameVisible &&
            self.visibleFrames >= 2) {

            self.gameVisible = YES;
            [self log:@"GAME SCREEN DETECTED"];
        }
    } else {
        self.missedFrames++;
        self.visibleFrames = 0;

        if (self.gameVisible &&
            self.missedFrames >= 3) {

            self.gameVisible = NO;
            self.topStreak = 0;
            self.pendingTop = @"";

            [self log:
                @"GAME SCREEN NOT DETECTED - TRACKING PAUSED"];
        }
    }
}

- (void)processTop:(NSString *)value {
    if (!self.gameVisible || !value.length) {
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

    if (self.topStreak >= 3 &&
        ![value isEqualToString:self.topResult]) {

        self.topResult = value;

        [self log:[NSString stringWithFormat:
            @"TOP CANDIDATE: %@ | NOT CONFIRMED",
            value]];
    }
}

#pragma mark - Scanner

- (void)scan {
    if (self.busy || !self.running)
        return;

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

    if (!balanceImage ||
        !betImage ||
        !topImage) {

        if (balanceImage)
            CGImageRelease(balanceImage);
        if (betImage)
            CGImageRelease(betImage);
        if (topImage)
            CGImageRelease(topImage);

        self.busy = NO;
        [self log:@"CROP FAILED"];
        return;
    }

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED,0), ^{
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

            long long rawBalance =
                [self readRawBalance:balanceTexts];

            NSInteger currentBet =
                [self readBet:betTexts];

            NSString *top =
                [self readTop:topTexts];

            NSString *rawBal =
                [self raw:balanceTexts];

            NSString *rawBet =
                [self raw:betTexts];

            NSString *rawTop =
                [self raw:topTexts];

            dispatch_async(
                dispatch_get_main_queue(), ^{

                self.busy = NO;

                if (!self.running)
                    return;

                BOOL visible =
                    rawBalance >= 0 ||
                    currentBet > 0;

                [self processVisibility:visible];

                if (self.gameVisible) {
                    [self processBet:currentBet];
                    [self processBalance:rawBalance];
                    [self processTop:top];
                }

                if (self.scans % 10 == 0) {
                    [self log:[NSString stringWithFormat:
                        @"BAL OCR RAW: %@",rawBal]];

                    [self log:[NSString stringWithFormat:
                        @"BET OCR RAW: %@",rawBet]];

                    [self log:[NSString stringWithFormat:
                        @"TOP OCR RAW: %@",rawTop]];
                }

                [self refresh];
            });
        }
    });
}

- (void)tick:(NSTimer *)timer {
    [self scan];
}

#pragma mark - Controls

- (void)resetBaseline {
    self.hasBalance = NO;
    self.balanceStreak = 0;
    self.pendingBalance = 0;
    self.rawBalance = 0;

    [self log:@"BALANCE BASELINE RESET"];
    [self refresh];
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
        self.estimatedSpins = 0;
        self.confirmedSpins = 0;
        self.uncertainEvents = 0;
        self.positiveEvents = 0;

        self.bet = 0;
        self.betStreak = 0;

        self.gameVisible = NO;
        self.missedFrames = 0;
        self.visibleFrames = 0;

        self.topResult = @"";
        self.pendingTop = @"";
        self.topStreak = 0;

        [self resetBaseline];

        self.timer =
            [NSTimer scheduledTimerWithTimeInterval:0.6
                                             target:self
                                           selector:@selector(tick:)
                                           userInfo:nil
                                            repeats:YES];

        [self log:@"AUTO STARTED - V15"];
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
    [self log:@"BALANCE AREA NARROW"];
}

- (void)balanceWide {
    self.balanceW =
        MIN(0.35,self.balanceW+0.01);

    [self resetBaseline];
    [self log:@"BALANCE AREA WIDE"];
}

- (void)copyLog {
    [self log:@"LOG COPIED"];

    UIPasteboard.generalPasteboard.string =
        [self.events componentsJoinedByString:@"\n"];
}

#pragma mark - Overlay

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

- (UILabel *)label:(CGRect)frame
             font:(CGFloat)font
            color:(UIColor *)color
           parent:(UIView *)parent {

    UILabel *label =
        [[UILabel alloc] initWithFrame:frame];

    label.textColor = color;
    label.font =
        [UIFont boldSystemFontOfSize:font];

    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.7;

    [parent addSubview:label];

    return label;
}

- (void)movePanel:
    (UIPanGestureRecognizer *)gesture {

    CGPoint p =
        [gesture translationInView:self.panel];

    CGRect frame = self.panel.frame;

    frame.origin.x += p.x;
    frame.origin.y += p.y;

    self.panel.frame = frame;

    [gesture setTranslation:CGPointZero
                    inView:self.panel];
}

- (void)showPanel {
    if (self.panel)
        return;

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
        CGRectMake(12,65,width,465);

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
        [self label:
            CGRectMake(12,8,width-24,28)
                  font:16
                 color:UIColor.whiteColor
                parent:vc.view];

    title.text =
        @"CMSCrystalLogger v15";

    title.userInteractionEnabled = YES;

    [title addGestureRecognizer:
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(movePanel:)]];

    self.statusLabel =
        [self label:
            CGRectMake(12,40,width-24,22)
                  font:12
                 color:UIColor.whiteColor
                parent:vc.view];

    self.balanceLabel =
        [self label:
            CGRectMake(12,68,width-24,27)
                  font:15
                 color:UIColor.systemGreenColor
                parent:vc.view];

    self.betLabel =
        [self label:
            CGRectMake(12,99,width-24,24)
                  font:14
                 color:UIColor.whiteColor
                parent:vc.view];

    self.spinLabel =
        [self label:
            CGRectMake(12,127,width-24,25)
                  font:15
                 color:UIColor.systemCyanColor
                parent:vc.view];

    self.topLabel =
        [self label:
            CGRectMake(12,156,width-24,23)
                  font:13
                 color:UIColor.systemYellowColor
                parent:vc.view];

    self.screenLabel =
        [self label:
            CGRectMake(12,183,width-24,22)
                  font:11
                 color:UIColor.lightGrayColor
                parent:vc.view];

    self.logView =
        [[UITextView alloc] initWithFrame:
            CGRectMake(10,211,width-20,127)];

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
    CGFloat bw =
        (width-36-2*gap)/3;

    [self button:@"AUTO ON/OFF"
          frame:CGRectMake(12,345,bw,32)
         action:@selector(toggle)
         parent:vc.view];

    [self button:@"COPY LOG"
          frame:CGRectMake(18+bw,345,bw,32)
         action:@selector(copyLog)
         parent:vc.view];

    [self button:@"TRIM5"
          frame:CGRectMake(24+2*bw,345,bw,32)
         action:@selector(toggleTrim)
         parent:vc.view];

    [self button:@"BAL UP"
          frame:CGRectMake(12,385,bw,32)
         action:@selector(balanceUp)
         parent:vc.view];

    [self button:@"BAL DOWN"
          frame:CGRectMake(18+bw,385,bw,32)
         action:@selector(balanceDown)
         parent:vc.view];

    [self button:@"RESET BAL"
          frame:CGRectMake(24+2*bw,385,bw,32)
         action:@selector(resetBaseline)
         parent:vc.view];

    CGFloat half =
        (width-30)/2;

    [self button:@"BAL NARROW"
          frame:CGRectMake(12,425,half,30)
         action:@selector(balanceNarrow)
         parent:vc.view];

    [self button:@"BAL WIDE"
          frame:CGRectMake(18+half,425,half,30)
         action:@selector(balanceWide)
         parent:vc.view];

    self.panel.hidden = NO;
    [self.panel makeKeyAndVisible];

    [self refresh];

    [self log:@"V15 READY"];
    [self log:@"SMART BALANCE TRACKING ENABLED"];
    [self log:@"BET OCR X / MULTIPLY / STAR"];
    [self log:@"ESTIMATED AND CONFIRMED COUNTS SEPARATE"];
    [self log:@"CONFIRMED COUNT REQUIRES FUTURE VALIDATION"];
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

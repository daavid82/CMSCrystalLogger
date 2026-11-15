
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <CoreGraphics/CoreGraphics.h>
#import <stdlib.h>
#import <math.h>

typedef NS_ENUM(NSInteger, CMSSpinState) {
    CMSSpinStateReady = 0,
    CMSSpinStateSpinning,
    CMSSpinStateStopped,
    CMSSpinStateResult
};

@interface CMSLogger : NSObject

@property(nonatomic,strong) UIWindow *panel;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) UITextView *logView;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UILabel *balanceLabel;
@property(nonatomic,strong) UILabel *betLabel;
@property(nonatomic,strong) UILabel *spinLabel;
@property(nonatomic,strong) UILabel *stateLabel;
@property(nonatomic,strong) UILabel *topLabel;
@property(nonatomic,strong) UILabel *motionLabel;
@property(nonatomic,strong) NSMutableArray *events;

@property(nonatomic,assign) BOOL running;
@property(nonatomic,assign) BOOL busy;
@property(nonatomic,assign) BOOL gameVisible;
@property(nonatomic,assign) BOOL hasBalance;
@property(nonatomic,assign) BOOL trimFive;

@property(nonatomic,assign) NSInteger attempts;
@property(nonatomic,assign) NSInteger scans;
@property(nonatomic,assign) NSInteger visibleFrames;
@property(nonatomic,assign) NSInteger missedFrames;

@property(nonatomic,assign) NSInteger bet;
@property(nonatomic,assign) NSInteger pendingBet;
@property(nonatomic,assign) NSInteger betStreak;

@property(nonatomic,assign) long long balance;
@property(nonatomic,assign) long long rawBalance;
@property(nonatomic,assign) long long pendingBalance;
@property(nonatomic,assign) NSInteger balanceStreak;

@property(nonatomic,assign) NSInteger estimatedSpins;
@property(nonatomic,assign) NSInteger observedCycles;
@property(nonatomic,assign) NSInteger uncertainEvents;

@property(nonatomic,assign) CMSSpinState spinState;
@property(nonatomic,assign) NSInteger movingFrames;
@property(nonatomic,assign) NSInteger stableFrames;
@property(nonatomic,assign) NSInteger resultFrames;
@property(nonatomic,assign) double motionScore;
@property(nonatomic,assign) BOOL hasMotionReference;

@property(nonatomic,copy) NSData *previousPixels;
@property(nonatomic,copy) NSString *topResult;
@property(nonatomic,copy) NSString *pendingTop;
@property(nonatomic,assign) NSInteger topStreak;

@property(nonatomic,assign) CGFloat balanceY;
@property(nonatomic,assign) CGFloat balanceW;
@property(nonatomic,assign) CGFloat betY;
@property(nonatomic,assign) CGFloat topY;

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

        instance.balanceY = 0.828;
        instance.balanceW = 0.23;
        instance.betY = 0.711;
        instance.topY = 0.20;

        instance.trimFive = YES;
        instance.topResult = @"";
        instance.pendingTop = @"";
        instance.spinState = CMSSpinStateReady;
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

    NSDateFormatter *formatter = [NSDateFormatter new];
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

        if (all.length)
            [self.logView scrollRangeToVisible:
                NSMakeRange(all.length - 1, 1)];
    }

    NSString *path =
        [NSTemporaryDirectory()
            stringByAppendingPathComponent:
                @"CMSCrystalV16.log"];

    [all writeToFile:path
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:nil];

    NSLog(@"[CMSCrystalV16] %@", line);
}

- (NSString *)stateName {
    switch (self.spinState) {
        case CMSSpinStateReady: return @"READY";
        case CMSSpinStateSpinning: return @"SPINNING";
        case CMSSpinStateStopped: return @"STOPPED";
        case CMSSpinStateResult: return @"RESULT";
    }
    return @"UNKNOWN";
}

- (void)refresh {
    self.statusLabel.text =
        [NSString stringWithFormat:
            @"AUTO %@ | SCANS %ld | SCREEN %@",
            self.running ? @"ON" : @"OFF",
            (long)self.scans,
            self.gameVisible ? @"GAME" : @"OTHER"];

    self.statusLabel.textColor =
        self.running ?
            UIColor.systemGreenColor :
            UIColor.systemOrangeColor;

    self.balanceLabel.text =
        self.hasBalance ?
            [NSString stringWithFormat:
                @"BAL %lld | RAW %lld",
                self.balance,
                self.rawBalance] :
            @"BALANCE WAITING";

    self.betLabel.text =
        self.bet > 0 ?
            [NSString stringWithFormat:
                @"CURRENT BET x%ld",
                (long)self.bet] :
            @"CURRENT BET WAITING";

    self.spinLabel.text =
        [NSString stringWithFormat:
            @"EST %ld | CYCLES %ld | ? %ld",
            (long)self.estimatedSpins,
            (long)self.observedCycles,
            (long)self.uncertainEvents];

    self.stateLabel.text =
        [NSString stringWithFormat:
            @"STATE: %@", [self stateName]];

    self.topLabel.text =
        [NSString stringWithFormat:
            @"TOP CANDIDATE: %@",
            self.topResult.length ?
                self.topResult : @"UNKNOWN"];

    self.motionLabel.text =
        [NSString stringWithFormat:
            @"MOTION %.1f%% | TRIM5 %@",
            self.motionScore * 100.0,
            self.trimFive ? @"ON" : @"OFF"];
}

#pragma mark - Screenshot

- (UIWindow *)gameWindow {
    UIWindow *best = nil;

    for (UIScene *scene in
         UIApplication.sharedApplication.connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        for (UIWindow *window in
             ((UIWindowScene *)scene).windows) {

            if (window == self.panel || window.hidden)
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
        [UIGraphicsImageRendererFormat defaultFormat];

    format.scale = 1;
    format.opaque = YES;

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc]
            initWithSize:window.bounds.size
                  format:format];

    return [renderer imageWithActions:
        ^(UIGraphicsImageRendererContext *context) {
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
        CGRectMake(iw*x, ih*y,
                   iw*width, ih*height);

    rect = CGRectIntersection(
        rect, CGRectMake(0,0,iw,ih));

    if (CGRectIsEmpty(rect))
        return NULL;

    return CGImageCreateWithImageInRect(
        image, CGRectIntegral(rect));
}

#pragma mark - Wheel motion

// Produces a small grayscale image of the
// central wheel area for frame comparison.

- (NSData *)motionPixels:(CGImageRef)image {
    if (!image)
        return nil;

    const size_t width = 48;
    const size_t height = 32;
    const size_t count = width * height;

    NSMutableData *data =
        [NSMutableData dataWithLength:count];

    CGColorSpaceRef colorSpace =
        CGColorSpaceCreateDeviceGray();

    CGContextRef context =
        CGBitmapContextCreate(
            data.mutableBytes,
            width,
            height,
            8,
            width,
            colorSpace,
            kCGImageAlphaNone);

    CGColorSpaceRelease(colorSpace);

    if (!context)
        return nil;

    CGContextSetInterpolationQuality(
        context,
        kCGInterpolationLow);

    CGContextDrawImage(
        context,
        CGRectMake(0,0,width,height),
        image);

    CGContextRelease(context);

    return data;
}

- (double)difference:(NSData *)a
                    other:(NSData *)b {

    if (!a || !b || a.length != b.length)
        return -1;

    const uint8_t *pa = a.bytes;
    const uint8_t *pb = b.bytes;

    NSUInteger count = a.length;
    double sum = 0;

    for (NSUInteger i=0; i<count; i++)
        sum += abs((int)pa[i] - (int)pb[i]);

    return sum / ((double)count * 255.0);
}

- (void)resetMotion {
    self.previousPixels = nil;
    self.hasMotionReference = NO;
    self.movingFrames = 0;
    self.stableFrames = 0;
    self.resultFrames = 0;
    self.motionScore = 0;
    self.spinState = CMSSpinStateReady;
}

- (void)processMotion:(NSData *)pixels {
    if (!self.gameVisible || !pixels)
        return;

    if (!self.hasMotionReference) {
        self.previousPixels = pixels;
        self.hasMotionReference = YES;
        return;
    }

    double score =
        [self difference:self.previousPixels
                   other:pixels];

    self.previousPixels = pixels;

    if (score < 0)
        return;

    self.motionScore = score;

    // Thresholds are experimental and may need
    // adjustment for this game's animations.
    BOOL moving = score > 0.075;
    BOOL stable = score < 0.025;

    if (moving) {
        self.movingFrames++;
        self.stableFrames = 0;
    } else if (stable) {
        self.stableFrames++;
        self.movingFrames = 0;
    } else {
        self.movingFrames = 0;
        self.stableFrames = 0;
    }

    switch (self.spinState) {
        case CMSSpinStateReady:
            if (self.movingFrames >= 2) {
                self.spinState = CMSSpinStateSpinning;

                [self log:[NSString stringWithFormat:
                    @"SPIN MOTION START | SCORE %.3f",
                    score]];
            }
            break;

        case CMSSpinStateSpinning:
            if (self.stableFrames >= 3) {
                self.spinState = CMSSpinStateStopped;
                self.resultFrames = 0;

                [self log:@"WHEEL APPEARS STOPPED"];
            }
            break;

        case CMSSpinStateStopped:
            self.resultFrames++;

            if (self.resultFrames >= 2) {
                self.spinState = CMSSpinStateResult;
                self.observedCycles++;

                [self log:[NSString stringWithFormat:
                    @"OBSERVED WHEEL CYCLE #%ld",
                    (long)self.observedCycles]];

                [self log:
                    @"CYCLE NOT YET VERIFIED AS GAME SPIN"];
            }
            break;

        case CMSSpinStateResult:
            if (self.stableFrames >= 6) {
                self.spinState = CMSSpinStateReady;
                self.movingFrames = 0;

                [self log:@"READY FOR NEXT MOTION"];
            }
            break;
    }
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
    NSMutableArray *parts = [NSMutableArray new];

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
    long long best = -1;
    float bestConfidence = -1;

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
    NSInteger best = 0;
    float bestConfidence = -1;

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

        if (!number.length ||
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
        @[@"ATTACK",@"POINT",@"STEAL",
          @"SHIELD",@"SPINS"];

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
                best = name;
                confidence = score;
            }
        }
    }

    return confidence >= 0.75 ? best : @"";
}

#pragma mark - Balance and bet

- (long long)normalizeBalance:(long long)raw {
    if (raw < 0)
        return -1;

    // Experimental correction for observed
    // seven-digit readings ending in extra 5.
    if (self.trimFive &&
        raw >= 1000000 &&
        raw <= 9999999 &&
        raw % 10 == 5)
        return raw / 10;

    return raw;
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
        self.bet != value) {

        self.bet = value;

        [self log:[NSString stringWithFormat:
            @"BET VERIFIED: x%ld",
            (long)value]];
    }
}

- (void)processBalance:(long long)raw {
    if (raw < 0) {
        self.balanceStreak = 0;
        return;
    }

    long long value =
        [self normalizeBalance:raw];

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

    if (llabs(delta) > 100000) {
        if (self.scans % 10 == 0)
            [self log:[NSString stringWithFormat:
                @"OCR REJECTED: %lld -> %lld",
                old,value]];
        return;
    }

    self.balance = value;

    [self log:[NSString stringWithFormat:
        @"BALANCE: %lld -> %lld (%+lld)",
        old,value,delta]];

    if (delta >= 0) {
        [self log:
            @"BALANCE INCREASE / NO SPIN INFERENCE"];
        return;
    }

    if (self.bet <= 0) {
        self.uncertainEvents++;
        [self log:@"BET UNKNOWN"];
        return;
    }

    long long spent = -delta;

    if (spent % self.bet == 0) {
        long long count = spent / self.bet;

        if (count >= 1 && count <= 100) {
            self.estimatedSpins += (NSInteger)count;

            [self log:[NSString stringWithFormat:
                @"ESTIMATED SPINS +%lld | TOTAL %ld",
                count,
                (long)self.estimatedSpins]];

            return;
        }
    }

    self.uncertainEvents++;

    [self log:[NSString stringWithFormat:
        @"UNCLASSIFIED BALANCE DELTA %+lld",
        delta]];
}

#pragma mark - Screen state and top

- (void)processVisibility:(BOOL)visible {
    if (visible) {
        self.visibleFrames++;
        self.missedFrames = 0;

        if (!self.gameVisible &&
            self.visibleFrames >= 2) {

            self.gameVisible = YES;
            [self resetMotion];
            [self log:@"GAME SCREEN DETECTED"];
        }
    } else {
        self.missedFrames++;
        self.visibleFrames = 0;

        if (self.gameVisible &&
            self.missedFrames >= 3) {

            self.gameVisible = NO;
            [self resetMotion];

            self.pendingTop = @"";
            self.topStreak = 0;

            [self log:
                @"GAME SCREEN LOST - MOTION RESET"];
        }
    }
}

- (void)processTop:(NSString *)value {
    if (!self.gameVisible ||
        !value.length) {

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
            @"TOP CANDIDATE: %@",
            value]];
    }
}

#pragma mark - Scan

- (void)scan {
    if (!self.running || self.busy)
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
                x:0.39
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

    // Experimental motion region.
    // Avoids most of the upper UI and
    // the spin button at the bottom.
    CGImageRef wheelImage =
        [self crop:source
                x:0.23
                y:0.34
                w:0.54
                h:0.25];

    if (!balanceImage ||
        !betImage ||
        !topImage ||
        !wheelImage) {

        if (balanceImage) CGImageRelease(balanceImage);
        if (betImage) CGImageRelease(betImage);
        if (topImage) CGImageRelease(topImage);
        if (wheelImage) CGImageRelease(wheelImage);

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

            NSData *pixels =
                [self motionPixels:wheelImage];

            CGImageRelease(balanceImage);
            CGImageRelease(betImage);
            CGImageRelease(topImage);
            CGImageRelease(wheelImage);

            long long rawBalance =
                [self readRawBalance:balanceTexts];

            NSInteger bet =
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
                    bet > 0;

                [self processVisibility:visible];

                if (self.gameVisible) {
                    [self processBet:bet];
                    [self processBalance:rawBalance];
                    [self processMotion:pixels];
                    [self processTop:top];
                }

                if (self.scans % 10 == 0) {
                    [self log:[NSString stringWithFormat:
                        @"BAL OCR RAW: %@",rawBal]];

                    [self log:[NSString stringWithFormat:
                        @"BET OCR RAW: %@",rawBet]];

                    [self log:[NSString stringWithFormat:
                        @"TOP OCR RAW: %@",rawTop]];

                    [self log:[NSString stringWithFormat:
                        @"MOTION SCORE %.3f | STATE %@",
                        self.motionScore,
                        [self stateName]]];
                }

                [self refresh];
            });
        }
    });
}

- (void)tick:(NSTimer *)timer {
    [self scan];
}

#pragma mark - Buttons

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
        @"TRIM5 %@",self.trimFive ? @"ON" : @"OFF"]];
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
        self.observedCycles = 0;
        self.uncertainEvents = 0;

        self.bet = 0;
        self.betStreak = 0;
        self.gameVisible = NO;
        self.visibleFrames = 0;
        self.missedFrames = 0;

        self.topResult = @"";
        self.pendingTop = @"";
        self.topStreak = 0;

        [self resetMotion];
        [self resetBaseline];

        self.timer =
            [NSTimer scheduledTimerWithTimeInterval:0.35
                                             target:self
                                           selector:@selector(tick:)
                                           userInfo:nil
                                            repeats:YES];

        [self log:@"AUTO STARTED - V16"];
        [self scan];
    }

    [self refresh];
}

- (void)copyLog {
    [self log:@"LOG COPIED"];

    UIPasteboard.generalPasteboard.string =
        [self.events componentsJoinedByString:@"\n"];
}

- (void)balanceUp {
    self.balanceY =
        MAX(0.70,self.balanceY-0.01);
    [self resetBaseline];
}

- (void)balanceDown {
    self.balanceY =
        MIN(0.90,self.balanceY+0.01);
    [self resetBaseline];
}

- (void)balanceNarrow {
    self.balanceW =
        MAX(0.15,self.balanceW-0.01);
    [self resetBaseline];
}

- (void)balanceWide {
    self.balanceW =
        MIN(0.35,self.balanceW+0.01);
    [self resetBaseline];
}

#pragma mark - Overlay

- (UILabel *)label:(CGRect)frame
             font:(CGFloat)size
            color:(UIColor *)color
           parent:(UIView *)parent {

    UILabel *label =
        [[UILabel alloc] initWithFrame:frame];

    label.font =
        [UIFont boldSystemFontOfSize:size];

    label.textColor = color;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.7;

    [parent addSubview:label];

    return label;
}

- (void)button:(NSString *)title
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
        @"CMSCrystalLogger v16";

    title.userInteractionEnabled = YES;

    [title addGestureRecognizer:
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(movePanel:)]];

    self.statusLabel =
        [self label:CGRectMake(12,40,width-24,22)
                  font:11
                 color:UIColor.whiteColor
                parent:vc.view];

    self.balanceLabel =
        [self label:CGRectMake(12,68,width-24,26)
                  font:15
                 color:UIColor.systemGreenColor
                parent:vc.view];

    self.betLabel =
        [self label:CGRectMake(12,98,width-24,24)
                  font:14
                 color:UIColor.whiteColor
                parent:vc.view];

    self.spinLabel =
        [self label:CGRectMake(12,127,width-24,25)
                  font:15
                 color:UIColor.systemCyanColor
                parent:vc.view];

    self.stateLabel =
        [self label:CGRectMake(12,155,width-24,25)
                  font:15
                 color:UIColor.systemOrangeColor
                parent:vc.view];

    self.topLabel =
        [self label:CGRectMake(12,184,width-24,23)
                  font:13
                 color:UIColor.systemYellowColor
                parent:vc.view];

    self.motionLabel =
        [self label:CGRectMake(12,211,width-24,22)
                  font:11
                 color:UIColor.lightGrayColor
                parent:vc.view];

    self.logView =
        [[UITextView alloc] initWithFrame:
            CGRectMake(10,240,width-20,98)];

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

    CGFloat half = (width-30)/2;

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

    [self log:@"V16 READY"];
    [self log:@"WHEEL MOTION DETECTION ENABLED"];
    [self log:@"BET OCR X / MULTIPLY / STAR"];
    [self log:@"ESTIMATED SPINS AND OBSERVED CYCLES"];
    [self log:@"MOTION THRESHOLDS ARE EXPERIMENTAL"];
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

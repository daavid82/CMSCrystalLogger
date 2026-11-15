
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>
#import <stdlib.h>

typedef NS_ENUM(NSInteger, CMSWheelState) {
    CMSWheelStateReady,
    CMSWheelStateMoving,
    CMSWheelStateSettling
};

@interface CMSCrystalLogger : NSObject

@property(nonatomic,strong) UIWindow *panel;
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UITextView *logView;

@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UILabel *balanceLabel;
@property(nonatomic,strong) UILabel *betLabel;
@property(nonatomic,strong) UILabel *spinsLabel;
@property(nonatomic,strong) UILabel *wheelLabel;
@property(nonatomic,strong) UILabel *resultLabel;
@property(nonatomic,strong) UILabel *speedLabel;

@property(nonatomic,strong) NSTimer *motionTimer;
@property(nonatomic,strong) NSTimer *ocrTimer;
@property(nonatomic,strong) NSMutableArray<NSString *> *events;

@property(nonatomic,assign) BOOL running;
@property(nonatomic,assign) BOOL motionBusy;
@property(nonatomic,assign) BOOL ocrBusy;
@property(nonatomic,assign) BOOL gameVisible;
@property(nonatomic,assign) BOOL trimFive;
@property(nonatomic,assign) BOOL hasBalance;

@property(nonatomic,assign) NSUInteger generation;
@property(nonatomic,assign) NSInteger launchAttempts;
@property(nonatomic,assign) NSInteger motionFrames;
@property(nonatomic,assign) NSInteger ocrFrames;
@property(nonatomic,assign) NSInteger visibleCount;
@property(nonatomic,assign) NSInteger missingCount;

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

@property(nonatomic,assign) CMSWheelState wheelState;
@property(nonatomic,assign) NSInteger movingFrames;
@property(nonatomic,assign) NSInteger stableFrames;
@property(nonatomic,assign) NSInteger settleFrames;
@property(nonatomic,assign) double motionScore;
@property(nonatomic,assign) NSTimeInterval lastMotionTime;
@property(nonatomic,assign) NSTimeInterval lastCycleTime;
@property(nonatomic,assign) NSTimeInterval lastFPSCheck;
@property(nonatomic,assign) NSInteger framesAtFPSCheck;
@property(nonatomic,assign) double actualFPS;

@property(nonatomic,copy) NSData *previousPixels;
@property(nonatomic,copy) NSString *topCandidate;

@property(nonatomic,assign) CGFloat balanceY;
@property(nonatomic,assign) CGFloat wheelY;

+ (instancetype)shared;
- (void)start;

@end

@implementation CMSCrystalLogger

+ (instancetype)shared {
    static CMSCrystalLogger *instance;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        instance = [CMSCrystalLogger new];
        instance.events = [NSMutableArray new];
        instance.trimFive = YES;
        instance.balanceY = 0.828;
        instance.wheelY = 0.34;
        instance.topCandidate = @"";
        instance.wheelState = CMSWheelStateReady;
    });

    return instance;
}

#pragma mark - Log

- (void)log:(NSString *)message {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self log:message];
        });
        return;
    }

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"HH:mm:ss.SSS";

    NSString *line = [NSString stringWithFormat:
        @"%@ %@",
        [formatter stringFromDate:[NSDate date]],
        message];

    [self.events addObject:line];

    if (self.events.count > 800)
        [self.events removeObjectAtIndex:0];

    NSString *all =
        [self.events componentsJoinedByString:@"\n"];

    if (self.logView) {
        self.logView.text = all;
        if (all.length > 0) {
            [self.logView scrollRangeToVisible:
                NSMakeRange(all.length - 1, 1)];
        }
    }

    NSLog(@"[CMSCrystalV17] %@", line);
}

- (NSString *)wheelStateName {
    switch (self.wheelState) {
        case CMSWheelStateReady: return @"READY";
        case CMSWheelStateMoving: return @"MOVING";
        case CMSWheelStateSettling: return @"SETTLING";
    }
    return @"UNKNOWN";
}

- (void)refresh {
    self.statusLabel.text =
        [NSString stringWithFormat:
            @"AUTO %@ | SCREEN %@",
            self.running ? @"ON" : @"OFF",
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

    self.spinsLabel.text =
        [NSString stringWithFormat:
            @"EST %ld | CYCLES %ld | ? %ld",
            (long)self.estimatedSpins,
            (long)self.observedCycles,
            (long)self.uncertainEvents];

    self.wheelLabel.text =
        [NSString stringWithFormat:
            @"WHEEL %@ | MOTION %.1f%%",
            [self wheelStateName],
            self.motionScore * 100.0];

    self.resultLabel.text =
        [NSString stringWithFormat:
            @"TOP: %@",
            self.topCandidate.length ?
                self.topCandidate : @"UNKNOWN"];

    self.speedLabel.text =
        [NSString stringWithFormat:
            @"ACTUAL %.1f FPS | OCR %ld | TRIM5 %@",
            self.actualFPS,
            (long)self.ocrFrames,
            self.trimFive ? @"ON" : @"OFF"];
}

#pragma mark - Capture

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
    if (!window) return nil;

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
                CGRectMake(0,0,
                    window.bounds.size.width,
                    window.bounds.size.height)
                afterScreenUpdates:NO];
        }];
}

- (CGImageRef)crop:(CGImageRef)image
                x:(CGFloat)x
                y:(CGFloat)y
                w:(CGFloat)w
                h:(CGFloat)h {

    if (!image) return NULL;

    CGFloat iw = CGImageGetWidth(image);
    CGFloat ih = CGImageGetHeight(image);

    CGRect rect =
        CGRectMake(iw*x, ih*y, iw*w, ih*h);

    rect = CGRectIntersection(
        rect, CGRectMake(0,0,iw,ih));

    if (CGRectIsEmpty(rect))
        return NULL;

    return CGImageCreateWithImageInRect(
        image, CGRectIntegral(rect));
}

#pragma mark - Motion

- (NSData *)motionPixels:(CGImageRef)image {
    if (!image) return nil;

    const size_t width = 48;
    const size_t height = 32;

    NSMutableData *data =
        [NSMutableData dataWithLength:width*height];

    CGColorSpaceRef space =
        CGColorSpaceCreateDeviceGray();

    CGContextRef context =
        CGBitmapContextCreate(
            data.mutableBytes,
            width,
            height,
            8,
            width,
            space,
            kCGImageAlphaNone);

    CGColorSpaceRelease(space);

    if (!context) return nil;

    CGContextSetInterpolationQuality(
        context, kCGInterpolationLow);

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

    double sum = 0;

    for (NSUInteger i=0; i<a.length; i++) {
        sum += abs((int)pa[i] - (int)pb[i]);
    }

    return sum / (a.length * 255.0);
}

- (void)resetMotion {
    self.previousPixels = nil;
    self.wheelState = CMSWheelStateReady;
    self.movingFrames = 0;
    self.stableFrames = 0;
    self.settleFrames = 0;
    self.motionScore = 0;
    self.lastMotionTime = 0;
}

- (void)processMotion:(NSData *)pixels {
    if (!pixels || !self.gameVisible)
        return;

    if (!self.previousPixels) {
        self.previousPixels = pixels;
        return;
    }

    double score =
        [self difference:self.previousPixels
                   other:pixels];

    self.previousPixels = pixels;

    if (score < 0) return;

    self.motionScore = score;

    NSTimeInterval now =
        [NSDate date].timeIntervalSince1970;

    BOOL moving = score > 0.065;
    BOOL stable = score < 0.022;

    if (moving) {
        self.movingFrames++;
        self.stableFrames = 0;
        self.lastMotionTime = now;
    } else if (stable) {
        self.stableFrames++;
        self.movingFrames = 0;
    } else {
        self.movingFrames = 0;
        self.stableFrames = 0;
    }

    switch (self.wheelState) {
        case CMSWheelStateReady:
            if (self.movingFrames >= 1) {
                self.wheelState = CMSWheelStateMoving;

                [self log:[NSString stringWithFormat:
                    @"MOTION START | SCORE %.3f",
                    score]];
            }
            break;

        case CMSWheelStateMoving:
            if (self.stableFrames >= 2 &&
                now - self.lastMotionTime >= 0.10) {

                self.wheelState = CMSWheelStateSettling;
                self.settleFrames = 0;
                [self log:@"WHEEL APPEARS STOPPED"];
            }
            break;

        case CMSWheelStateSettling:
            if (moving) {
                self.wheelState = CMSWheelStateMoving;
                self.settleFrames = 0;
                [self log:@"MOTION RESUMED"];
            } else if (stable) {
                self.settleFrames++;

                if (self.settleFrames >= 2) {
                    if (now - self.lastCycleTime >= 0.25) {
                        self.observedCycles++;
                        self.lastCycleTime = now;

                        [self log:[NSString stringWithFormat:
                            @"OBSERVED CYCLE #%ld",
                            (long)self.observedCycles]];

                        [self requestResultScan];
                    }

                    self.wheelState = CMSWheelStateReady;
                    self.movingFrames = 0;
                    self.stableFrames = 0;
                }
            }
            break;
    }
}

- (void)updateFPS {
    NSTimeInterval now =
        [NSDate date].timeIntervalSince1970;

    if (self.lastFPSCheck == 0) {
        self.lastFPSCheck = now;
        self.framesAtFPSCheck = self.motionFrames;
        return;
    }

    NSTimeInterval elapsed =
        now - self.lastFPSCheck;

    if (elapsed >= 2.0) {
        NSInteger frames =
            self.motionFrames - self.framesAtFPSCheck;

        self.actualFPS = frames / elapsed;
        self.lastFPSCheck = now;
        self.framesAtFPSCheck = self.motionFrames;

        [self log:[NSString stringWithFormat:
            @"ACTUAL MOTION FPS: %.1f",
            self.actualFPS]];
    }
}

#pragma mark - OCR

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

- (long long)normalizeBalance:(long long)raw {
    if (raw < 0) return -1;

    if (self.trimFive &&
        raw >= 1000000 &&
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
            @"BALANCE INCREASE / REFUND / WIN"];
        return;
    }

    if (self.bet <= 0) {
        self.uncertainEvents++;
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
        @"UNCLASSIFIED DELTA %+lld",delta]];
}

#pragma mark - Screen detection

- (void)processVisibility:(BOOL)visible {
    if (visible) {
        self.visibleCount++;
        self.missingCount = 0;

        if (!self.gameVisible &&
            self.visibleCount >= 2) {

            self.gameVisible = YES;
            [self resetMotion];
            [self log:@"GAME SCREEN DETECTED"];
        }
    } else {
        self.missingCount++;
        self.visibleCount = 0;

        if (self.gameVisible &&
            self.missingCount >= 3) {

            self.gameVisible = NO;
            [self resetMotion];
            [self log:@"GAME SCREEN LOST"];
        }
    }
}

#pragma mark - Fast wheel scanning

- (void)motionTick:(NSTimer *)timer {
    if (!self.running ||
        self.motionBusy ||
        !self.gameVisible)
        return;

    self.motionBusy = YES;

    UIImage *image = [self capture];

    if (!image.CGImage) {
        self.motionBusy = NO;
        return;
    }

    CGImageRef region =
        [self crop:image.CGImage
                x:0.23
                y:self.wheelY
                w:0.54
                h:0.25];

    if (!region) {
        self.motionBusy = NO;
        return;
    }

    NSData *pixels =
        [self motionPixels:region];

    CGImageRelease(region);

    self.motionBusy = NO;
    self.motionFrames++;

    [self processMotion:pixels];
    [self updateFPS];

    if (self.motionFrames % 10 == 0)
        [self refresh];
}

#pragma mark - Balance OCR

- (void)ocrTick:(NSTimer *)timer {
    if (!self.running || self.ocrBusy)
        return;

    self.ocrBusy = YES;

    UIImage *image = [self capture];

    if (!image.CGImage) {
        self.ocrBusy = NO;
        return;
    }

    CGImageRef balanceImage =
        [self crop:image.CGImage
                x:0.39
                y:self.balanceY
                w:0.23
                h:0.036];

    CGImageRef betImage =
        [self crop:image.CGImage
                x:0.615
                y:0.711
                w:0.14
                h:0.055];

    if (!balanceImage || !betImage) {
        if (balanceImage) CGImageRelease(balanceImage);
        if (betImage) CGImageRelease(betImage);
        self.ocrBusy = NO;
        return;
    }

    NSUInteger scanGeneration = self.generation;

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED,0), ^{
        @autoreleasepool {

            NSArray *balanceTexts =
                [self ocr:balanceImage];

            NSArray *betTexts =
                [self ocr:betImage];

            CGImageRelease(balanceImage);
            CGImageRelease(betImage);

            long long rawBalance =
                [self readRawBalance:balanceTexts];

            NSInteger currentBet =
                [self readBet:betTexts];

            NSString *rawBal =
                [self raw:balanceTexts];

            NSString *rawBet =
                [self raw:betTexts];

            dispatch_async(
                dispatch_get_main_queue(), ^{

                self.ocrBusy = NO;

                if (!self.running ||
                    scanGeneration != self.generation)
                    return;

                self.ocrFrames++;

                [self processVisibility:
                    (rawBalance >= 0 || currentBet > 0)];

                if (self.gameVisible) {
                    [self processBet:currentBet];
                    [self processBalance:rawBalance];
                }

                if (self.ocrFrames % 10 == 0) {
                    [self log:[NSString stringWithFormat:
                        @"BAL OCR RAW: %@",rawBal]];

                    [self log:[NSString stringWithFormat:
                        @"BET OCR RAW: %@",rawBet]];
                }

                [self refresh];
            });
        }
    });
}

#pragma mark - Result OCR

- (void)requestResultScan {
    if (!self.running || !self.gameVisible)
        return;

    UIImage *image = [self capture];

    if (!image.CGImage)
        return;

    CGImageRef topImage =
        [self crop:image.CGImage
                x:0.20
                y:0.20
                w:0.60
                h:0.12];

    if (!topImage)
        return;

    NSUInteger scanGeneration = self.generation;

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED,0), ^{
        @autoreleasepool {

            NSArray *items = [self ocr:topImage];
            CGImageRelease(topImage);

            NSString *result = [self readTop:items];
            NSString *raw = [self raw:items];

            dispatch_async(
                dispatch_get_main_queue(), ^{

                if (!self.running ||
                    scanGeneration != self.generation)
                    return;

                [self log:[NSString stringWithFormat:
                    @"STOP TOP OCR: %@",raw]];

                if (result.length) {
                    self.topCandidate = result;

                    [self log:[NSString stringWithFormat:
                        @"POSSIBLE RESULT: %@",
                        result]];
                } else {
                    [self log:@"RESULT UNKNOWN"];
                }

                [self refresh];
            });
        }
    });
}

#pragma mark - Controls

- (void)resetBalance {
    self.hasBalance = NO;
    self.balanceStreak = 0;
    self.pendingBalance = 0;
    self.rawBalance = 0;

    [self log:@"BALANCE BASELINE RESET"];
    [self refresh];
}

- (void)toggleTrim {
    self.trimFive = !self.trimFive;
    [self resetBalance];

    [self log:[NSString stringWithFormat:
        @"TRIM5 %@",
        self.trimFive ? @"ON" : @"OFF"]];
}

- (void)toggle {
    if (self.running) {
        self.running = NO;
        self.generation++;

        [self.motionTimer invalidate];
        [self.ocrTimer invalidate];

        self.motionTimer = nil;
        self.ocrTimer = nil;

        [self log:@"AUTO STOPPED"];
    } else {
        self.running = YES;
        self.generation++;

        self.motionFrames = 0;
        self.ocrFrames = 0;
        self.estimatedSpins = 0;
        self.observedCycles = 0;
        self.uncertainEvents = 0;

        self.bet = 0;
        self.betStreak = 0;

        self.gameVisible = NO;
        self.visibleCount = 0;
        self.missingCount = 0;

        self.topCandidate = @"";
        self.lastFPSCheck = 0;
        self.framesAtFPSCheck = 0;
        self.actualFPS = 0;
        self.lastCycleTime = 0;

        [self resetMotion];
        [self resetBalance];

        self.motionTimer =
            [NSTimer scheduledTimerWithTimeInterval:0.05
                                             target:self
                                           selector:@selector(motionTick:)
                                           userInfo:nil
                                            repeats:YES];

        self.ocrTimer =
            [NSTimer scheduledTimerWithTimeInterval:0.60
                                             target:self
                                           selector:@selector(ocrTick:)
                                           userInfo:nil
                                            repeats:YES];

        [self log:@"AUTO STARTED - V17 FAST"];
        [self log:@"MOTION TARGET 20 FPS"];
        [self log:@"OCR TARGET 600 MS"];

        [self ocrTick:nil];
    }

    [self refresh];
}

- (void)copyLog {
    [self log:@"LOG COPIED"];

    UIPasteboard.generalPasteboard.string =
        [self.events componentsJoinedByString:@"\n"];
}

- (void)balanceUp {
    self.balanceY = MAX(0.70,self.balanceY-0.01);
    [self resetBalance];
    [self log:@"BALANCE AREA UP"];
}

- (void)balanceDown {
    self.balanceY = MIN(0.90,self.balanceY+0.01);
    [self resetBalance];
    [self log:@"BALANCE AREA DOWN"];
}

- (void)wheelUp {
    self.wheelY = MAX(0.15,self.wheelY-0.02);
    [self resetMotion];
    [self log:@"WHEEL AREA UP"];
}

- (void)wheelDown {
    self.wheelY = MIN(0.65,self.wheelY+0.02);
    [self resetMotion];
    [self log:@"WHEEL AREA DOWN"];
}

#pragma mark - UI

- (UILabel *)label:(CGRect)frame
             font:(CGFloat)size
            color:(UIColor *)color
           parent:(UIView *)parent {

    UILabel *label =
        [[UILabel alloc] initWithFrame:frame];

    label.font = [UIFont boldSystemFontOfSize:size];
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

    CGPoint point =
        [gesture translationInView:self.panel];

    CGRect frame = self.panel.frame;
    frame.origin.x += point.x;
    frame.origin.y += point.y;

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
        if (++self.launchAttempts < 60) {
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                    NSEC_PER_SEC),
                dispatch_get_main_queue(), ^{
                    [self showPanel];
                });
        }
        return;
    }

    CGFloat width =
        MIN(350,
            scene.coordinateSpace.bounds.size.width-24);

    self.panel =
        [[UIWindow alloc] initWithWindowScene:scene];

    self.panel.frame =
        CGRectMake(12,65,width,475);

    self.panel.windowLevel =
        UIWindowLevelAlert+1;

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
        [self label:CGRectMake(12,8,width-24,28)
                  font:16
                 color:UIColor.whiteColor
                parent:vc.view];

    title.text = @"CMSCrystalLogger v17 FAST";
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

    self.spinsLabel =
        [self label:CGRectMake(12,127,width-24,25)
                  font:15
                 color:UIColor.systemCyanColor
                parent:vc.view];

    self.wheelLabel =
        [self label:CGRectMake(12,155,width-24,25)
                  font:15
                 color:UIColor.systemOrangeColor
                parent:vc.view];

    self.resultLabel =
        [self label:CGRectMake(12,184,width-24,23)
                  font:13
                 color:UIColor.systemYellowColor
                parent:vc.view];

    self.speedLabel =
        [self label:CGRectMake(12,211,width-24,22)
                  font:11
                 color:UIColor.lightGrayColor
                parent:vc.view];

    self.logView =
        [[UITextView alloc] initWithFrame:
            CGRectMake(10,240,width-20,98)];

    self.logView.backgroundColor = UIColor.clearColor;
    self.logView.textColor = UIColor.systemGreenColor;

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

    [self button:@"WHEEL UP"
          frame:CGRectMake(24+2*bw,385,bw,32)
         action:@selector(wheelUp)
         parent:vc.view];

    CGFloat half = (width-30)/2;

    [self button:@"WHEEL DOWN"
          frame:CGRectMake(12,425,half,32)
         action:@selector(wheelDown)
         parent:vc.view];

    [self button:@"RESET BAL"
          frame:CGRectMake(18+half,425,half,32)
         action:@selector(resetBalance)
         parent:vc.view];

    self.panel.hidden = NO;
    [self.panel makeKeyAndVisible];

    [self refresh];

    [self log:@"V17 READY"];
    [self log:@"FAST WHEEL DETECTION ENABLED"];
    [self log:@"MOTION AND OCR SEPARATED"];
    [self log:@"ACTUAL FPS MONITOR ENABLED"];
    [self log:@"RESULTS ARE NOT YET CONFIRMED"];
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
        [[CMSCrystalLogger shared] start];
    });
}

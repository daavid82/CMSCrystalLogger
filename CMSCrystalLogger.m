#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>
#import <stdlib.h>

typedef NS_ENUM(NSInteger, CMSWheelState) {
    CMSReady,
    CMSMoving,
    CMSSettling
};

@interface CMSCrystalLogger : NSObject

@property(nonatomic,strong) UIWindow *panel;
@property(nonatomic,strong) UILabel *summary;
@property(nonatomic,strong) UITextView *logView;
@property(nonatomic,strong) NSTimer *motionTimer;
@property(nonatomic,strong) NSTimer *ocrTimer;

@property(nonatomic,strong) NSMutableArray<NSString *> *events;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *symbols;
@property(nonatomic,copy) NSData *previousPixels;

@property(nonatomic,assign) BOOL running;
@property(nonatomic,assign) BOOL motionBusy;
@property(nonatomic,assign) BOOL ocrBusy;
@property(nonatomic,assign) BOOL gameVisible;
@property(nonatomic,assign) BOOL trimFive;
@property(nonatomic,assign) BOOL hasBalance;
@property(nonatomic,assign) BOOL resultBusy;

@property(nonatomic,assign) NSUInteger generation;

@property(nonatomic,assign) NSInteger visibilityHits;
@property(nonatomic,assign) NSInteger visibilityMisses;
@property(nonatomic,assign) NSInteger bet;
@property(nonatomic,assign) NSInteger betCandidate;
@property(nonatomic,assign) NSInteger betHits;
@property(nonatomic,assign) NSInteger balanceHits;
@property(nonatomic,assign) NSInteger estimated;
@property(nonatomic,assign) NSInteger cycles;
@property(nonatomic,assign) NSInteger unknownResults;
@property(nonatomic,assign) NSInteger motionFrames;
@property(nonatomic,assign) NSInteger ocrFrames;
@property(nonatomic,assign) NSInteger movingHits;
@property(nonatomic,assign) NSInteger stableHits;
@property(nonatomic,assign) NSInteger settleHits;

@property(nonatomic,assign) long long balance;
@property(nonatomic,assign) long long balanceCandidate;

@property(nonatomic,assign) CMSWheelState wheelState;
@property(nonatomic,assign) NSTimeInterval lastMoving;
@property(nonatomic,assign) NSTimeInterval lastCycle;
@property(nonatomic,assign) NSTimeInterval fpsStart;
@property(nonatomic,assign) NSInteger fpsFrames;
@property(nonatomic,assign) double fps;
@property(nonatomic,assign) double motionScore;

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
        instance.symbols = [@{
            @"ATTACK": @0,
            @"STEAL": @0,
            @"POINT": @0,
            @"SHIELD": @0,
            @"SPINS": @0
        } mutableCopy];
        instance.trimFive = YES;
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
    formatter.dateFormat = @"HH:mm:ss.SSS";

    NSString *line = [NSString stringWithFormat:
        @"%@ %@",
        [formatter stringFromDate:[NSDate date]],
        message
    ];

    [self.events addObject:line];

    if (self.events.count > 700) {
        [self.events removeObjectAtIndex:0];
    }

    if (self.logView) {
        self.logView.text =
            [self.events componentsJoinedByString:@"\n"];

        if (self.logView.text.length > 0) {
            [self.logView scrollRangeToVisible:
                NSMakeRange(self.logView.text.length - 1, 1)];
        }
    }

    NSLog(@"[CMSCrystalV19] %@", line);
}

- (void)refresh {
    NSString *state = @"READY";

    if (self.wheelState == CMSMoving) {
        state = @"MOVING";
    } else if (self.wheelState == CMSSettling) {
        state = @"SETTLING";
    }

    NSString *balanceText = self.hasBalance
        ? [NSString stringWithFormat:@"%lld", self.balance]
        : @"WAIT";

    NSString *betText = self.bet > 0
        ? [NSString stringWithFormat:@"x%ld", (long)self.bet]
        : @"WAIT";

    self.summary.text = [NSString stringWithFormat:
        @"AUTO %@ | GAME %@\n"
        @"BAL %@ | BET %@\n"
        @"EST %ld | CYCLES %ld | UNKNOWN %ld\n"
        @"WHEEL %@ | %.1f FPS | %.1f%%\n"
        @"ATTACK %@ STEAL %@ POINT %@\n"
        @"SHIELD %@ SPINS %@",

        self.running ? @"ON" : @"OFF",
        self.gameVisible ? @"YES" : @"NO",
        balanceText,
        betText,
        (long)self.estimated,
        (long)self.cycles,
        (long)self.unknownResults,
        state,
        self.fps,
        self.motionScore * 100.0,
        self.symbols[@"ATTACK"],
        self.symbols[@"STEAL"],
        self.symbols[@"POINT"],
        self.symbols[@"SHIELD"],
        self.symbols[@"SPINS"]
    ];
}

#pragma mark - Screen capture

- (UIWindow *)gameWindow {
    UIWindow *best = nil;

    for (UIScene *scene in
         UIApplication.sharedApplication.connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        for (UIWindow *window in
             ((UIWindowScene *)scene).windows) {

            if (window == self.panel ||
                window.hidden ||
                window.bounds.size.width < 100 ||
                window.bounds.size.height < 100) {
                continue;
            }

            if (!best ||
                window.windowLevel < best.windowLevel) {
                best = window;
            }
        }
    }

    return best;
}

- (UIImage *)capture {
    UIWindow *window = [self gameWindow];

    if (!window) {
        return nil;
    }

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
                CGRectMake(
                    0,
                    0,
                    window.bounds.size.width,
                    window.bounds.size.height
                )
                afterScreenUpdates:NO];
        }];
}

- (CGImageRef)crop:(CGImageRef)image
                x:(CGFloat)x
                y:(CGFloat)y
                w:(CGFloat)width
                h:(CGFloat)height {

    if (!image) return NULL;

    CGRect bounds = CGRectMake(
        0, 0,
        CGImageGetWidth(image),
        CGImageGetHeight(image)
    );

    CGRect rect = CGRectMake(
        bounds.size.width * x,
        bounds.size.height * y,
        bounds.size.width * width,
        bounds.size.height * height
    );

    rect = CGRectIntersection(
        bounds,
        CGRectIntegral(rect)
    );

    if (CGRectIsEmpty(rect)) return NULL;

    return CGImageCreateWithImageInRect(image, rect);
}

#pragma mark - Motion pixels

- (NSData *)pixels:(CGImageRef)image {
    if (!image) return nil;

    const size_t width = 48;
    const size_t height = 32;

    NSMutableData *data =
        [NSMutableData dataWithLength:width * height];

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
            kCGImageAlphaNone
        );

    CGColorSpaceRelease(colorSpace);

    if (!context) return nil;

    CGContextSetInterpolationQuality(
        context,
        kCGInterpolationLow
    );

    CGContextDrawImage(
        context,
        CGRectMake(0, 0, width, height),
        image
    );

    CGContextRelease(context);

    return data;
}

- (double)difference:(NSData *)a
                   b:(NSData *)b {

    if (!a || !b || a.length != b.length) {
        return -1;
    }

    const uint8_t *first = a.bytes;
    const uint8_t *second = b.bytes;

    double total = 0;

    for (NSUInteger i = 0; i < a.length; i++) {
        total += abs(
            (int)first[i] - (int)second[i]
        );
    }

    return total / (a.length * 255.0);
}

- (void)resetMotion {
    self.previousPixels = nil;
    self.wheelState = CMSReady;
    self.movingHits = 0;
    self.stableHits = 0;
    self.settleHits = 0;
    self.motionScore = 0;
}

#pragma mark - OCR

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
            initWithCGImage:image
                    options:@{}];

    NSError *error = nil;

    if (![handler performRequests:@[request]
                            error:&error]) {
        return @[];
    }

    NSMutableArray *results = [NSMutableArray new];

    for (VNRecognizedTextObservation *observation
         in request.results) {

        VNRecognizedText *text =
            [[observation topCandidates:1] firstObject];

        if (text) {
            [results addObject:@{
                @"text": text.string,
                @"confidence": @(text.confidence)
            }];
        }
    }

    return results;
}

- (NSString *)raw:(NSArray<NSDictionary *> *)items {
    NSMutableArray *parts = [NSMutableArray new];

    for (NSDictionary *item in items) {
        [parts addObject:item[@"text"]];
    }

    return [parts componentsJoinedByString:@" | "];
}

- (NSString *)digits:(NSString *)input {
    NSMutableString *output = [NSMutableString new];

    for (NSUInteger i = 0; i < input.length; i++) {
        unichar c = [input characterAtIndex:i];

        if (c >= '0' && c <= '9') {
            [output appendFormat:@"%C", c];
        }
    }

    return output;
}

- (long long)readBalance:
    (NSArray<NSDictionary *> *)items {

    for (NSDictionary *item in items) {
        NSString *text =
            [item[@"text"]
                stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (![text hasPrefix:@"+"]) continue;

        NSString *tail = [text substringFromIndex:1];
        NSString *number = [self digits:tail];

        if (number.length < 4 || number.length > 12) {
            continue;
        }

        NSString *clean =
            [[[tail
                stringByReplacingOccurrencesOfString:@" "
                withString:@""]
                stringByReplacingOccurrencesOfString:@","
                withString:@""]
                stringByReplacingOccurrencesOfString:@"."
                withString:@""];

        if (![clean hasPrefix:number]) continue;

        long long value = number.longLongValue;

        if (self.trimFive &&
            number.length == 7 &&
            [number hasSuffix:@"5"]) {
            value /= 10;
        }

        return value;
    }

    return -1;
}

- (NSInteger)readBet:
    (NSArray<NSDictionary *> *)items {

    for (NSDictionary *item in items) {
        NSString *text =
            [[item[@"text"] uppercaseString]
                stringByReplacingOccurrencesOfString:@" "
                withString:@""];

        if (![text hasPrefix:@"X"] &&
            ![text hasPrefix:@"×"] &&
            ![text hasPrefix:@"*"]) {
            continue;
        }

        NSString *number = [text substringFromIndex:1];

        if (number.length == 0 ||
            number.length > 5 ||
            ![[self digits:number] isEqualToString:number]) {
            continue;
        }

        NSInteger value = number.integerValue;

        if (value > 0 && value <= 10000) {
            return value;
        }
    }

    return 0;
}

#pragma mark - Balance tracking

- (void)processBalance:(long long)value {
    if (value < 0) {
        self.balanceHits = 0;
        return;
    }

    if (self.balanceCandidate == value) {
        self.balanceHits++;
    } else {
        self.balanceCandidate = value;
        self.balanceHits = 1;
    }

    if (self.balanceHits < 2) return;

    if (!self.hasBalance) {
        self.hasBalance = YES;
        self.balance = value;

        [self log:[NSString stringWithFormat:
            @"BALANCE BASELINE %lld", value]];

        return;
    }

    if (value == self.balance) return;

    long long delta = value - self.balance;

    if (llabs(delta) > 100000) {
        [self log:[NSString stringWithFormat:
            @"BALANCE OCR REJECTED %lld", value]];
        return;
    }

    [self log:[NSString stringWithFormat:
        @"BALANCE %lld -> %lld (%+lld)",
        self.balance, value, delta]];

    self.balance = value;

    if (delta < 0 &&
        self.bet > 0 &&
        (-delta) % self.bet == 0) {

        long long count = (-delta) / self.bet;

        if (count > 0 && count <= 100) {
            self.estimated += (NSInteger)count;

            [self log:[NSString stringWithFormat:
                @"ESTIMATED SPINS +%lld | TOTAL %ld",
                count, (long)self.estimated]];
        }
    }
}

- (void)processBet:(NSInteger)value {
    if (value <= 0) {
        self.betHits = 0;
        return;
    }

    if (self.betCandidate == value) {
        self.betHits++;
    } else {
        self.betCandidate = value;
        self.betHits = 1;
    }

    if (self.betHits >= 2 && self.bet != value) {
        self.bet = value;

        [self log:[NSString stringWithFormat:
            @"BET VERIFIED x%ld", (long)value]];
    }
}

#pragma mark - Screen detection

- (void)visibility:(BOOL)found {
    if (found) {
        self.visibilityHits++;
        self.visibilityMisses = 0;

        if (!self.gameVisible &&
            self.visibilityHits >= 2) {

            self.gameVisible = YES;
            [self resetMotion];
            [self log:@"GAME SCREEN DETECTED"];
        }
    } else {
        self.visibilityMisses++;
        self.visibilityHits = 0;

        if (self.gameVisible &&
            self.visibilityMisses >= 3) {

            self.gameVisible = NO;
            [self resetMotion];
            [self log:@"GAME SCREEN LOST"];
        }
    }
}

#pragma mark - OCR timer

- (void)ocrTick:(NSTimer *)timer {
    if (!self.running || self.ocrBusy) return;

    self.ocrBusy = YES;

    UIImage *frame = [self capture];

    if (!frame.CGImage) {
        self.ocrBusy = NO;
        return;
    }

    CGImageRef balanceImage =
        [self crop:frame.CGImage
                x:0.39
                y:0.828
                w:0.23
                h:0.036];

    CGImageRef betImage =
        [self crop:frame.CGImage
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

    NSUInteger generation = self.generation;

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED, 0), ^{

        @autoreleasepool {
            NSArray *balanceTexts =
                [self ocr:balanceImage];

            NSArray *betTexts =
                [self ocr:betImage];

            CGImageRelease(balanceImage);
            CGImageRelease(betImage);

            long long balance =
                [self readBalance:balanceTexts];

            NSInteger bet =
                [self readBet:betTexts];

            NSString *rawBalance =
                [self raw:balanceTexts];

            NSString *rawBet =
                [self raw:betTexts];

            dispatch_async(
                dispatch_get_main_queue(), ^{

                self.ocrBusy = NO;

                if (!self.running ||
                    generation != self.generation) {
                    return;
                }

                self.ocrFrames++;

                [self visibility:
                    (balance >= 0 || bet > 0)];

                if (self.gameVisible) {
                    [self processBet:bet];
                    [self processBalance:balance];
                }

                if (self.ocrFrames % 8 == 0) {
                    [self log:[NSString stringWithFormat:
                        @"OCR BAL %@ | BET %@",
                        rawBalance, rawBet]];
                }

                [self refresh];
            });
        }
    });
}

#pragma mark - Symbol recognition

- (NSString *)symbolFrom:
    (NSArray<NSDictionary *> *)items {

    NSMutableSet<NSString *> *found =
        [NSMutableSet new];

    for (NSDictionary *item in items) {
        float confidence =
            [item[@"confidence"] floatValue];

        if (confidence < 0.55f) continue;

        NSString *text =
            [item[@"text"] uppercaseString];

        text =
            [[text componentsSeparatedByCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                componentsJoinedByString:@""];

        if ([text containsString:@"ATTACK"] ||
            [text isEqualToString:@"TTACK"]) {
            [found addObject:@"ATTACK"];
        }

        if ([text containsString:@"STEAL"]) {
            [found addObject:@"STEAL"];
        }

        if ([text containsString:@"POINT"] ||
            [text isEqualToString:@"OINT"]) {
            [found addObject:@"POINT"];
        }

        if ([text containsString:@"SHIELD"]) {
            [found addObject:@"SHIELD"];
        }

        if ([text containsString:@"SPINS"]) {
            [found addObject:@"SPINS"];
        }
    }

    return found.count == 1 ? found.anyObject : @"";
}

#pragma mark - Result sampling

- (void)resultScanForGeneration:(NSUInteger)generation
                          cycle:(NSInteger)cycle
                          index:(NSInteger)index
                          votes:(NSMutableDictionary *)votes {

    if (!self.running ||
        generation != self.generation ||
        !self.gameVisible) {
        return;
    }

    UIImage *frame = [self capture];

    if (!frame.CGImage) return;

    // V19: small, centered OCR area at top of wheel.
    CGImageRef region =
        [self crop:frame.CGImage
                x:0.39
                y:0.20
                w:0.22
                h:0.10];

    if (!region) return;

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED, 0), ^{

        @autoreleasepool {
            NSArray *items = [self ocr:region];
            CGImageRelease(region);

            NSString *candidate =
                [self symbolFrom:items];

            NSString *raw =
                [self raw:items];

            dispatch_async(
                dispatch_get_main_queue(), ^{

                if (!self.running ||
                    generation != self.generation) {
                    return;
                }

                [self log:[NSString stringWithFormat:
                    @"RESULT SAMPLE %ld/3 CYCLE %ld: %@ | %@",
                    (long)index,
                    (long)cycle,
                    candidate.length ? candidate : @"?",
                    raw]];

                if (candidate.length) {
                    NSInteger count =
                        [votes[candidate] integerValue];

                    votes[candidate] = @(count + 1);
                }

                if (index == 3) {
                    NSString *best = @"";
                    NSInteger bestVotes = 0;

                    for (NSString *name in votes) {
                        NSInteger count =
                            [votes[name] integerValue];

                        if (count > bestVotes) {
                            best = name;
                            bestVotes = count;
                        }
                    }

                    if (bestVotes >= 2) {
                        NSInteger previous =
                            [self.symbols[best] integerValue];

                        self.symbols[best] = @(previous + 1);

                        [self log:[NSString stringWithFormat:
                            @"REPEATED SYMBOL %@ (%ld/3) | NOT VERIFIED WINNER",
                            best, (long)bestVotes]];
                    } else {
                        self.unknownResults++;

                        [self log:
                            @"RESULT UNKNOWN | NO REPEATED SYMBOL"];
                    }

                    self.resultBusy = NO;
                }

                [self refresh];
            });
        }
    });
}

- (void)beginResultScan {
    if (self.resultBusy || !self.running) return;

    self.resultBusy = YES;

    NSUInteger generation = self.generation;
    NSInteger cycle = self.cycles;

    NSMutableDictionary *votes =
        [NSMutableDictionary new];

    for (NSInteger i = 1; i <= 3; i++) {
        NSInteger index = i;

        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,
                (int64_t)((i - 1) * 0.18 * NSEC_PER_SEC)
            ),
            dispatch_get_main_queue(), ^{

                if (!self.running ||
                    generation != self.generation) {
                    self.resultBusy = NO;
                    return;
                }

                [self resultScanForGeneration:generation
                                       cycle:cycle
                                       index:index
                                       votes:votes];
            });
    }
}

#pragma mark - Fast motion tracking

- (void)motionTick:(NSTimer *)timer {
    if (!self.running ||
        !self.gameVisible ||
        self.motionBusy) {
        return;
    }

    self.motionBusy = YES;

    UIImage *frame = [self capture];

    if (!frame.CGImage) {
        self.motionBusy = NO;
        return;
    }

    // V19: much smaller area near the top-center
    // of the wheel. Avoid unrelated screen animation.
    CGImageRef region =
        [self crop:frame.CGImage
                x:0.43
                y:0.30
                w:0.14
                h:0.10];

    NSData *pixels = [self pixels:region];

    if (region) CGImageRelease(region);

    self.motionBusy = NO;

    if (!pixels) return;

    self.motionFrames++;

    NSTimeInterval now =
        [NSDate date].timeIntervalSince1970;

    if (self.fpsStart == 0) {
        self.fpsStart = now;
        self.fpsFrames = self.motionFrames;

    } else if (now - self.fpsStart >= 2.0) {
        self.fps =
            (self.motionFrames - self.fpsFrames) /
            (now - self.fpsStart);

        self.fpsStart = now;
        self.fpsFrames = self.motionFrames;

        [self log:[NSString stringWithFormat:
            @"ACTUAL MOTION FPS %.1f", self.fps]];
    }

    if (!self.previousPixels) {
        self.previousPixels = pixels;
        return;
    }

    double score =
        [self difference:self.previousPixels b:pixels];

    self.previousPixels = pixels;

    if (score < 0) return;

    self.motionScore = score;

    BOOL moving = score > 0.065;
    BOOL stable = score < 0.022;

    if (moving) {
        self.movingHits++;
        self.stableHits = 0;
        self.lastMoving = now;

    } else if (stable) {
        self.stableHits++;
        self.movingHits = 0;

    } else {
        self.movingHits = 0;
        self.stableHits = 0;
    }

    if (self.wheelState == CMSReady &&
        self.movingHits >= 1) {

        self.wheelState = CMSMoving;

        [self log:[NSString stringWithFormat:
            @"MOTION START %.3f", score]];

    } else if (self.wheelState == CMSMoving &&
               self.stableHits >= 2 &&
               now - self.lastMoving >= 0.10) {

        self.wheelState = CMSSettling;
        self.settleHits = 0;

        [self log:@"WHEEL APPEARS STOPPED"];

    } else if (self.wheelState == CMSSettling) {

        if (moving) {
            self.wheelState = CMSMoving;
            self.settleHits = 0;

            [self log:@"MOTION RESUMED"];

        } else if (stable) {
            self.settleHits++;

            if (self.settleHits >= 2) {
                if (now - self.lastCycle >= 0.25) {
                    self.cycles++;
                    self.lastCycle = now;

                    [self log:[NSString stringWithFormat:
                        @"OBSERVED CYCLE #%ld",
                        (long)self.cycles]];

                    [self beginResultScan];
                }

                self.wheelState = CMSReady;
                self.movingHits = 0;
                self.stableHits = 0;
            }
        }
    }

    if (self.motionFrames % 10 == 0) {
        [self refresh];
    }
}

#pragma mark - Controls

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

        self.estimated = 0;
        self.cycles = 0;
        self.unknownResults = 0;
        self.motionFrames = 0;
        self.ocrFrames = 0;
        self.fps = 0;
        self.fpsStart = 0;
        self.lastCycle = 0;
        self.bet = 0;
        self.betHits = 0;
        self.hasBalance = NO;
        self.balanceHits = 0;
        self.gameVisible = NO;
        self.visibilityHits = 0;
        self.visibilityMisses = 0;
        self.resultBusy = NO;

        for (NSString *key in self.symbols.allKeys) {
            self.symbols[key] = @0;
        }

        [self resetMotion];

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

        [self log:
            @"AUTO STARTED V19 | SMALL TOP WHEEL AREA | TARGET 20 FPS"];

        [self ocrTick:nil];
    }

    [self refresh];
}

- (void)copyLog {
    [self log:@"LOG COPIED"];

    UIPasteboard.generalPasteboard.string =
        [self.events componentsJoinedByString:@"\n"];
}

- (void)toggleTrim {
    self.trimFive = !self.trimFive;
    self.hasBalance = NO;
    self.balanceHits = 0;

    [self log:[NSString stringWithFormat:
        @"TRIM5 %@ | BASELINE RESET",
        self.trimFive ? @"ON" : @"OFF"]];

    [self refresh];
}

- (void)resetBalance {
    self.hasBalance = NO;
    self.balanceHits = 0;

    [self log:@"BALANCE BASELINE RESET"];
    [self refresh];
}

#pragma mark - Panel

- (void)movePanel:(UIPanGestureRecognizer *)gesture {
    CGPoint point =
        [gesture translationInView:self.panel];

    CGRect frame = self.panel.frame;

    frame.origin.x += point.x;
    frame.origin.y += point.y;

    self.panel.frame = frame;

    [gesture setTranslation:CGPointZero
                    inView:self.panel];
}

- (void)addButton:(NSString *)title
                x:(CGFloat)x
                y:(CGFloat)y
            width:(CGFloat)width
           action:(SEL)action
           parent:(UIView *)parent {

    UIButton *button =
        [UIButton buttonWithType:UIButtonTypeSystem];

    button.frame = CGRectMake(x, y, width, 32);

    [button setTitle:title
           forState:UIControlStateNormal];

    [button setTitleColor:UIColor.whiteColor
                forState:UIControlStateNormal];

    button.backgroundColor =
        [UIColor colorWithWhite:0.23 alpha:1];

    button.layer.cornerRadius = 7;

    button.titleLabel.font =
        [UIFont boldSystemFontOfSize:11];

    [button addTarget:self
               action:action
     forControlEvents:UIControlEventTouchUpInside];

    [parent addSubview:button];
}

- (void)showPanel {
    if (self.panel) return;

    UIWindowScene *scene = nil;

    for (UIScene *candidate in
         UIApplication.sharedApplication.connectedScenes) {

        if ([candidate isKindOfClass:[UIWindowScene class]] &&
            candidate.activationState ==
                UISceneActivationStateForegroundActive) {

            scene = (UIWindowScene *)candidate;
            break;
        }
    }

    if (!scene) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
            dispatch_get_main_queue(), ^{
                [self showPanel];
            });
        return;
    }

    CGFloat width = MIN(
        350,
        scene.coordinateSpace.bounds.size.width - 24
    );

    self.panel =
        [[UIWindow alloc] initWithWindowScene:scene];

    self.panel.frame =
        CGRectMake(12, 65, width, 430);

    self.panel.windowLevel =
        UIWindowLevelAlert + 1;

    UIViewController *controller =
        [UIViewController new];

    controller.view.backgroundColor =
        [UIColor colorWithRed:0.06
                        green:0.08
                         blue:0.12
                        alpha:0.96];

    controller.view.layer.cornerRadius = 12;
    controller.view.clipsToBounds = YES;

    self.panel.rootViewController = controller;

    UILabel *title =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 8, width - 24, 28)];

    title.text = @"CMSCrystalLogger v19 TOP";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:16];
    title.userInteractionEnabled = YES;

    [title addGestureRecognizer:
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(movePanel:)]];

    [controller.view addSubview:title];

    self.summary =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 43, width - 24, 147)];

    self.summary.numberOfLines = 6;
    self.summary.textColor = UIColor.systemGreenColor;

    self.summary.font =
        [UIFont monospacedSystemFontOfSize:11
                                   weight:UIFontWeightMedium];

    self.summary.adjustsFontSizeToFitWidth = YES;
    self.summary.minimumScaleFactor = 0.75;

    [controller.view addSubview:self.summary];

    self.logView =
        [[UITextView alloc] initWithFrame:
            CGRectMake(10, 196, width - 20, 142)];

    self.logView.backgroundColor = UIColor.clearColor;
    self.logView.textColor = UIColor.systemGreenColor;

    self.logView.font =
        [UIFont monospacedSystemFontOfSize:10
                                   weight:UIFontWeightRegular];

    self.logView.editable = NO;

    [controller.view addSubview:self.logView];

    CGFloat gap = 6;
    CGFloat buttonWidth =
        (width - 36 - 2 * gap) / 3;

    [self addButton:@"AUTO ON/OFF"
                  x:12
                  y:345
              width:buttonWidth
             action:@selector(toggle)
             parent:controller.view];

    [self addButton:@"COPY LOG"
                  x:18 + buttonWidth
                  y:345
              width:buttonWidth
             action:@selector(copyLog)
             parent:controller.view];

    [self addButton:@"TRIM5"
                  x:24 + 2 * buttonWidth
                  y:345
              width:buttonWidth
             action:@selector(toggleTrim)
             parent:controller.view];

    [self addButton:@"RESET BAL"
                  x:12
                  y:385
              width:buttonWidth
             action:@selector(resetBalance)
             parent:controller.view];

    self.panel.hidden = NO;
    [self.panel makeKeyAndVisible];

    [self refresh];

    [self log:@"V19 READY"];
    [self log:@"MOTION ROI x=.43 y=.30 w=.14 h=.10"];
    [self log:@"RESULT ROI x=.39 y=.20 w=.22 h=.10"];
    [self log:@"SYMBOL COUNTS NOT VERIFIED"];
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

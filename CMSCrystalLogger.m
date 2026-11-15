
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>
#import <stdlib.h>

typedef NS_ENUM(NSInteger, CMSWheelState) {
    CMSWheelReady,
    CMSWheelMoving,
    CMSWheelSettling
};

@interface CMSCrystalLogger : NSObject

@property(nonatomic,strong) UIWindow *panel;
@property(nonatomic,strong) UILabel *summary;
@property(nonatomic,strong) UITextView *logView;
@property(nonatomic,strong) UIView *roiMarker;

@property(nonatomic,strong) NSTimer *motionTimer;
@property(nonatomic,strong) NSTimer *ocrTimer;

@property(nonatomic,strong) NSMutableArray<NSString *> *events;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *symbols;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSData *> *symbolImages;
@property(nonatomic,strong) NSMutableArray<NSNumber *> *pendingCycles;

@property(nonatomic,copy) NSData *previousPixels;
@property(nonatomic,copy) NSString *lastSymbol;

@property(nonatomic,assign) BOOL running;
@property(nonatomic,assign) BOOL ocrBusy;
@property(nonatomic,assign) BOOL resultBusy;
@property(nonatomic,assign) BOOL trimFive;
@property(nonatomic,assign) BOOL hasBalance;
@property(nonatomic,assign) BOOL markerVisible;
@property(nonatomic,assign) BOOL gameVisible;

@property(nonatomic,assign) NSUInteger generation;

@property(nonatomic,assign) NSInteger bet;
@property(nonatomic,assign) NSInteger betCandidate;
@property(nonatomic,assign) NSInteger betHits;
@property(nonatomic,assign) NSInteger balanceHits;

@property(nonatomic,assign) long long balance;
@property(nonatomic,assign) long long balanceCandidate;

@property(nonatomic,assign) NSInteger cycles;
@property(nonatomic,assign) NSInteger estimatedSpins;
@property(nonatomic,assign) NSInteger unknownResults;
@property(nonatomic,assign) NSInteger balanceEvents;
@property(nonatomic,assign) NSInteger repeatedCandidates;
@property(nonatomic,assign) NSInteger changedCandidates;
@property(nonatomic,assign) NSInteger uncertainCandidates;

@property(nonatomic,assign) NSInteger motionFrames;
@property(nonatomic,assign) NSInteger movingHits;
@property(nonatomic,assign) NSInteger stableHits;
@property(nonatomic,assign) NSInteger settleHits;
@property(nonatomic,assign) NSInteger fpsFrames;

@property(nonatomic,assign) NSTimeInterval fpsStart;
@property(nonatomic,assign) NSTimeInterval lastMoving;
@property(nonatomic,assign) NSTimeInterval lastCycle;

@property(nonatomic,assign) double fps;
@property(nonatomic,assign) CMSWheelState wheelState;

@property(nonatomic,assign) CGFloat roiX;
@property(nonatomic,assign) CGFloat roiY;
@property(nonatomic,assign) CGFloat roiW;
@property(nonatomic,assign) CGFloat roiH;

+ (instancetype)shared;
- (void)start;
- (void)scanResult:(NSUInteger)gen
            cycle:(NSInteger)cycle
            index:(NSInteger)index
            votes:(NSMutableDictionary *)votes
           images:(NSMutableDictionary *)images;
- (void)startPendingResultIfNeeded;

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

        instance.symbolImages = [NSMutableDictionary new];
        instance.pendingCycles = [NSMutableArray new];

        instance.trimFive = YES;
        instance.markerVisible = YES;

        instance.roiX = 0.390;
        instance.roiY = 0.230;
        instance.roiW = 0.220;
        instance.roiH = 0.100;

        instance.lastSymbol = @"";
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

    if (self.events.count > 1000) {
        [self.events removeObjectAtIndex:0];
    }

    NSLog(@"[CMSCrystalV22] %@", line);

    if (self.logView) {
        self.logView.text =
            [self.events componentsJoinedByString:@"\n"];

        if (self.logView.text.length) {
            [self.logView scrollRangeToVisible:
                NSMakeRange(self.logView.text.length - 1, 1)];
        }
    }
}

- (void)refresh {
    NSString *state = @"READY";

    if (self.wheelState == CMSWheelMoving) {
        state = @"MOVING";
    } else if (self.wheelState == CMSWheelSettling) {
        state = @"SETTLING";
    }

    self.summary.text = [NSString stringWithFormat:
        @"V22 AUTO %@ | %.1f FPS | %@\n"
        @"BAL %@ | BET %@\n"
        @"CYCLES %ld | EST %ld\n"
        @"NEW %ld | SAME %ld | UNCERTAIN %ld\n"
        @"ATT %@ STL %@ PNT %@\n"
        @"SHD %@ SPN %@ | UNKNOWN %ld\n"
        @"ROI %.3f %.3f",

        self.running ? @"ON" : @"OFF",
        self.fps,
        state,

        self.hasBalance
            ? [NSString stringWithFormat:@"%lld", self.balance]
            : @"WAIT",

        self.bet > 0
            ? [NSString stringWithFormat:@"x%ld", (long)self.bet]
            : @"WAIT",

        (long)self.cycles,
        (long)self.estimatedSpins,

        (long)self.changedCandidates,
        (long)self.repeatedCandidates,
        (long)self.uncertainCandidates,

        self.symbols[@"ATTACK"],
        self.symbols[@"STEAL"],
        self.symbols[@"POINT"],

        self.symbols[@"SHIELD"],
        self.symbols[@"SPINS"],
        (long)self.unknownResults,

        self.roiX,
        self.roiY
    ];
}

#pragma mark - Windows and ROI

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

            if (!best || window.windowLevel < best.windowLevel) {
                best = window;
            }
        }
    }

    return best;
}

- (void)updateMarker {
    UIWindow *window = [self gameWindow];
    if (!window) return;

    if (!self.roiMarker) {
        self.roiMarker = [UIView new];
        self.roiMarker.userInteractionEnabled = NO;

        self.roiMarker.backgroundColor =
            [UIColor colorWithRed:0 green:1 blue:0 alpha:0.08];

        self.roiMarker.layer.borderColor =
            UIColor.systemGreenColor.CGColor;

        self.roiMarker.layer.borderWidth = 2;
        self.roiMarker.layer.cornerRadius = 3;
    }

    if (self.roiMarker.superview != window) {
        [self.roiMarker removeFromSuperview];
        [window addSubview:self.roiMarker];
    }

    CGSize size = window.bounds.size;

    self.roiMarker.frame = CGRectMake(
        size.width * self.roiX,
        size.height * self.roiY,
        size.width * self.roiW,
        size.height * self.roiH
    );

    self.roiMarker.hidden = !self.markerVisible;
}

- (void)moveROIByX:(CGFloat)dx y:(CGFloat)dy {
    self.roiX = MAX(0, MIN(1 - self.roiW, self.roiX + dx));
    self.roiY = MAX(0, MIN(1 - self.roiH, self.roiY + dy));

    [self updateMarker];

    [self log:[NSString stringWithFormat:
        @"ROI MOVED x=%.3f y=%.3f",
        self.roiX,
        self.roiY]];

    [self refresh];
}

- (void)roiLeft {
    [self moveROIByX:-0.01 y:0];
}

- (void)roiRight {
    [self moveROIByX:0.01 y:0];
}

- (void)roiUp {
    [self moveROIByX:0 y:-0.01];
}

- (void)roiDown {
    [self moveROIByX:0 y:0.01];
}

- (void)toggleMarker {
    self.markerVisible = !self.markerVisible;
    [self updateMarker];
    [self log:self.markerVisible
        ? @"ROI VISIBLE"
        : @"ROI HIDDEN"];
}

#pragma mark - Capture

- (UIImage *)capture {
    UIWindow *window = [self gameWindow];
    if (!window) return nil;

    BOOL oldHidden = YES;

    if (self.roiMarker.superview == window) {
        oldHidden = self.roiMarker.hidden;
        self.roiMarker.hidden = YES;
    }

    UIGraphicsImageRendererFormat *format =
        [UIGraphicsImageRendererFormat defaultFormat];

    format.scale = 1;
    format.opaque = YES;

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc]
            initWithSize:window.bounds.size
                  format:format];

    UIImage *image =
        [renderer imageWithActions:
            ^(UIGraphicsImageRendererContext *context) {

                [window drawViewHierarchyInRect:
                    window.bounds
                    afterScreenUpdates:NO];
            }];

    if (self.roiMarker.superview == window) {
        self.roiMarker.hidden = oldHidden;
    }

    return image;
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

    CGRect rect = CGRectIntersection(
        bounds,
        CGRectIntegral(CGRectMake(
            bounds.size.width * x,
            bounds.size.height * y,
            bounds.size.width * width,
            bounds.size.height * height
        ))
    );

    if (CGRectIsEmpty(rect)) return NULL;

    return CGImageCreateWithImageInRect(image, rect);
}

#pragma mark - Image signatures

- (NSData *)pixels:(CGImageRef)image
             width:(size_t)width
            height:(size_t)height {

    if (!image) return nil;

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

- (double)difference:(NSData *)first
                   b:(NSData *)second {

    if (!first ||
        !second ||
        first.length != second.length) {
        return -1;
    }

    const uint8_t *a = first.bytes;
    const uint8_t *b = second.bytes;

    double total = 0;

    for (NSUInteger i = 0; i < first.length; i++) {
        total += abs((int)a[i] - (int)b[i]);
    }

    return total / (first.length * 255.0);
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

        NSString *number =
            [self digits:[text substringFromIndex:1]];

        if (number.length < 4 ||
            number.length > 12) continue;

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

        NSString *number =
            [text substringFromIndex:1];

        if (!number.length ||
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
    self.balanceEvents++;

    if (delta < 0 && self.bet > 0) {
        long long cost = -delta;

        if (cost % self.bet == 0) {
            long long count = cost / self.bet;

            if (count >= 1 && count <= 100) {
                self.estimatedSpins += (NSInteger)count;

                [self log:[NSString stringWithFormat:
                    @"BALANCE-BASED ESTIMATE +%lld | TOTAL %ld",
                    count,
                    (long)self.estimatedSpins]];
            }
        }
    }

    [self refresh];
}

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
                x:0.39 y:0.828 w:0.23 h:0.036];

    CGImageRef betImage =
        [self crop:frame.CGImage
                x:0.58 y:0.695 w:0.20 h:0.085];

    if (!balanceImage || !betImage) {
        if (balanceImage) CGImageRelease(balanceImage);
        if (betImage) CGImageRelease(betImage);
        self.ocrBusy = NO;
        return;
    }

    NSUInteger gen = self.generation;

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

            dispatch_async(dispatch_get_main_queue(), ^{
                if (gen != self.generation) return;

                self.ocrBusy = NO;
                if (!self.running) return;

                if ((balance >= 0 || bet > 0) &&
                    !self.gameVisible) {
                    self.gameVisible = YES;
                    [self log:@"GAME SCREEN DETECTED"];
                }

                [self processBet:bet];
                [self processBalance:balance];
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
        if ([item[@"confidence"] floatValue] < 0.40f) {
            continue;
        }

        NSString *text =
            [item[@"text"] uppercaseString];

        NSMutableString *letters =
            [NSMutableString new];

        for (NSUInteger i = 0; i < text.length; i++) {
            unichar c = [text characterAtIndex:i];

            if (c >= 'A' && c <= 'Z') {
                [letters appendFormat:@"%C", c];
            }
        }

        NSString *s = letters;

        if ([s containsString:@"ATTACK"] ||
            [s isEqualToString:@"TTACK"] ||
            [s isEqualToString:@"ATTAC"]) {
            [found addObject:@"ATTACK"];
        }

        if ([s containsString:@"STEAL"] ||
            [s isEqualToString:@"TEAL"]) {
            [found addObject:@"STEAL"];
        }

        if ([s containsString:@"POINT"] ||
            [s isEqualToString:@"OINT"] ||
            [s isEqualToString:@"POIN"]) {
            [found addObject:@"POINT"];
        }

        if ([s containsString:@"SHIELD"] ||
            [s isEqualToString:@"HIELD"] ||
            [s isEqualToString:@"AIELD"]) {
            [found addObject:@"SHIELD"];
        }

        if ([s containsString:@"SPINS"] ||
            [s isEqualToString:@"PINS"]) {
            [found addObject:@"SPINS"];
        }
    }

    return found.count == 1 ? found.anyObject : @"";
}

#pragma mark - V22 image verification

- (void)finishResult:(NSDictionary *)votes
              images:(NSDictionary *)images
               cycle:(NSInteger)cycle {

    NSString *best = @"";
    NSInteger bestVotes = 0;

    for (NSString *key in votes) {
        NSInteger count = [votes[key] integerValue];

        if (count > bestVotes) {
            bestVotes = count;
            best = key;
        }
    }

    if (bestVotes < 2) {
        self.unknownResults++;

        [self log:[NSString stringWithFormat:
            @"CYCLE %ld RESULT UNKNOWN",
            (long)cycle]];

    } else {
        NSData *currentImage = images[best];
        NSData *previousImage = self.symbolImages[best];

        if (!previousImage) {
            self.symbols[best] =
                @([self.symbols[best] integerValue] + 1);

            self.changedCandidates++;

            [self log:[NSString stringWithFormat:
                @"CYCLE %ld NEW %@ | FIRST IMAGE | %ld/3",
                (long)cycle, best, (long)bestVotes]];

            if (currentImage) {
                self.symbolImages[best] = currentImage;
            }

        } else if (!currentImage) {
            self.uncertainCandidates++;

            [self log:[NSString stringWithFormat:
                @"CYCLE %ld %@ | NO IMAGE TO COMPARE",
                (long)cycle, best]];

        } else {
            double difference =
                [self difference:previousImage b:currentImage];

            if (difference >= 0 &&
                difference < 0.035) {

                self.repeatedCandidates++;

                [self log:[NSString stringWithFormat:
                    @"CYCLE %ld SAME %@ IMAGE | DIFF %.4f | NOT ADDED",
                    (long)cycle, best, difference]];

            } else if (difference >= 0.120) {
                self.uncertainCandidates++;

                [self log:[NSString stringWithFormat:
                    @"CYCLE %ld CHANGED %@ IMAGE | DIFF %.4f | REVIEW",
                    (long)cycle, best, difference]];

                /*
                 A large change may be a new result,
                 but may also be animation or another
                 part of the UI. Do not count it
                 automatically without more evidence.
                */

                self.symbolImages[best] = currentImage;

            } else {
                self.uncertainCandidates++;

                [self log:[NSString stringWithFormat:
                    @"CYCLE %ld UNCERTAIN %@ | DIFF %.4f | NOT ADDED",
                    (long)cycle, best, difference]];
            }
        }

        self.lastSymbol = best;
    }

    self.resultBusy = NO;
    [self refresh];
    [self startPendingResultIfNeeded];
}

- (void)scheduleResult:(NSUInteger)gen
                 cycle:(NSInteger)cycle
                 index:(NSInteger)index
                 votes:(NSMutableDictionary *)votes
                images:(NSMutableDictionary *)images {

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.20 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(), ^{

            [self scanResult:gen
                      cycle:cycle
                      index:index
                      votes:votes
                     images:images];
        });
}

- (void)scanResult:(NSUInteger)gen
            cycle:(NSInteger)cycle
            index:(NSInteger)index
            votes:(NSMutableDictionary *)votes
           images:(NSMutableDictionary *)images {

    if (!self.running || gen != self.generation) {
        self.resultBusy = NO;
        return;
    }

    UIImage *frame = [self capture];

    CGImageRef region = frame.CGImage
        ? [self crop:frame.CGImage
                x:self.roiX
                y:self.roiY
                w:self.roiW
                h:self.roiH]
        : NULL;

    if (!region) {
        [self log:@"RESULT CAPTURE FAILED"];

        if (index < 3) {
            [self scheduleResult:gen
                          cycle:cycle
                          index:index + 1
                          votes:votes
                         images:images];
        } else {
            [self finishResult:votes
                        images:images
                         cycle:cycle];
        }
        return;
    }

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED, 0), ^{

        @autoreleasepool {
            NSData *signature =
                [self pixels:region
                       width:32
                      height:20];

            NSArray *items = [self ocr:region];
            CGImageRelease(region);

            NSString *symbol = [self symbolFrom:items];
            NSString *raw = [self raw:items];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (!self.running ||
                    gen != self.generation) {
                    self.resultBusy = NO;
                    return;
                }

                [self log:[NSString stringWithFormat:
                    @"RESULT %ld/3 CYCLE %ld: %@ | %@",
                    (long)index,
                    (long)cycle,
                    symbol.length ? symbol : @"?",
                    raw]];

                if (symbol.length) {
                    votes[symbol] =
                        @([votes[symbol] integerValue] + 1);

                    if (signature && !images[symbol]) {
                        images[symbol] = signature;
                    }
                }

                if (index < 3) {
                    [self scheduleResult:gen
                                  cycle:cycle
                                  index:index + 1
                                  votes:votes
                                 images:images];
                } else {
                    [self finishResult:votes
                                images:images
                                 cycle:cycle];
                }
            });
        }
    });
}

#pragma mark - Result queue

- (void)startPendingResultIfNeeded {
    if (!self.running ||
        self.resultBusy ||
        self.pendingCycles.count == 0) {
        return;
    }

    NSInteger cycle =
        self.pendingCycles.firstObject.integerValue;

    [self.pendingCycles removeObjectAtIndex:0];

    self.resultBusy = YES;

    NSUInteger gen = self.generation;

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(0.12 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(), ^{

            [self scanResult:gen
                      cycle:cycle
                      index:1
                      votes:[NSMutableDictionary new]
                     images:[NSMutableDictionary new]];
        });
}

- (void)beginResultScan {
    [self.pendingCycles addObject:@(self.cycles)];

    [self log:[NSString stringWithFormat:
        @"RESULT QUEUED CYCLE %ld | WAITING %ld",
        (long)self.cycles,
        (long)self.pendingCycles.count]];

    [self startPendingResultIfNeeded];
}

#pragma mark - Motion detection

- (void)resetMotion {
    self.previousPixels = nil;
    self.wheelState = CMSWheelReady;
    self.movingHits = 0;
    self.stableHits = 0;
    self.settleHits = 0;
}

- (void)motionTick:(NSTimer *)timer {
    if (!self.running) return;

    UIImage *frame = [self capture];
    if (!frame.CGImage) return;

    CGImageRef region =
        [self crop:frame.CGImage
                x:0.43 y:0.30
                w:0.14 h:0.10];

    NSData *pixels =
        [self pixels:region width:48 height:32];

    if (region) CGImageRelease(region);
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
            @"ACTUAL MOTION FPS %.1f",
            self.fps]];
    }

    if (!self.previousPixels) {
        self.previousPixels = pixels;
        return;
    }

    double score =
        [self difference:self.previousPixels b:pixels];

    self.previousPixels = pixels;

    if (score < 0) return;

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

    if (self.wheelState == CMSWheelReady &&
        self.movingHits >= 1) {

        self.wheelState = CMSWheelMoving;

        [self log:[NSString stringWithFormat:
            @"MOTION START %.3f", score]];

    } else if (self.wheelState == CMSWheelMoving &&
               self.stableHits >= 2 &&
               now - self.lastMoving >= 0.10) {

        self.wheelState = CMSWheelSettling;
        self.settleHits = 0;

        [self log:@"WHEEL APPEARS STOPPED"];

    } else if (self.wheelState == CMSWheelSettling) {

        if (moving) {
            self.wheelState = CMSWheelMoving;
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

                self.wheelState = CMSWheelReady;
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

        self.resultBusy = NO;
        self.ocrBusy = NO;

        [self.pendingCycles removeAllObjects];

        [self log:@"AUTO STOPPED V22"];

    } else {
        self.running = YES;
        self.generation++;

        self.cycles = 0;
        self.estimatedSpins = 0;
        self.unknownResults = 0;
        self.balanceEvents = 0;
        self.repeatedCandidates = 0;
        self.changedCandidates = 0;
        self.uncertainCandidates = 0;

        self.motionFrames = 0;
        self.fpsFrames = 0;
        self.fpsStart = 0;
        self.fps = 0;
        self.lastCycle = 0;

        self.hasBalance = NO;
        self.balanceHits = 0;

        self.bet = 0;
        self.betHits = 0;

        self.gameVisible = NO;
        self.ocrBusy = NO;
        self.resultBusy = NO;

        self.lastSymbol = @"";

        [self.pendingCycles removeAllObjects];
        [self.symbolImages removeAllObjects];

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

        [self log:@"AUTO STARTED V22"];
        [self log:@"IMAGE COMPARISON ENABLED"];
        [self log:@"RESULT QUEUE ENABLED"];
        [self log:@"MOTION DETECTION UNCHANGED"];

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
        @"TRIM5 %@",
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

    button.frame = CGRectMake(x, y, width, 29);

    [button setTitle:title
           forState:UIControlStateNormal];

    [button setTitleColor:UIColor.whiteColor
                forState:UIControlStateNormal];

    button.backgroundColor =
        [UIColor colorWithWhite:0.23 alpha:1];

    button.layer.cornerRadius = 6;

    button.titleLabel.font =
        [UIFont boldSystemFontOfSize:10];

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
        340,
        scene.coordinateSpace.bounds.size.width - 20
    );

    self.panel =
        [[UIWindow alloc] initWithWindowScene:scene];

    self.panel.frame =
        CGRectMake(10, 55, width, 410);

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
            CGRectMake(10, 5, width - 20, 26)];

    title.text = @"CMSCrystalLogger v22";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:15];
    title.userInteractionEnabled = YES;

    [title addGestureRecognizer:
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(movePanel:)]];

    [controller.view addSubview:title];

    self.summary =
        [[UILabel alloc] initWithFrame:
            CGRectMake(10, 32, width - 20, 126)];

    self.summary.numberOfLines = 7;
    self.summary.textColor = UIColor.systemGreenColor;

    self.summary.font =
        [UIFont monospacedSystemFontOfSize:10
                                   weight:UIFontWeightMedium];

    self.summary.adjustsFontSizeToFitWidth = YES;
    self.summary.minimumScaleFactor = 0.7;

    [controller.view addSubview:self.summary];

    self.logView =
        [[UITextView alloc] initWithFrame:
            CGRectMake(8, 160, width - 16, 110)];

    self.logView.backgroundColor = UIColor.clearColor;
    self.logView.textColor = UIColor.systemGreenColor;

    self.logView.font =
        [UIFont monospacedSystemFontOfSize:9
                                   weight:UIFontWeightRegular];

    self.logView.editable = NO;

    [controller.view addSubview:self.logView];

    CGFloat gap = 5;
    CGFloat buttonWidth =
        (width - 20 - 2 * gap) / 3;

    [self addButton:@"AUTO"
                  x:5 y:276 width:buttonWidth
             action:@selector(toggle)
             parent:controller.view];

    [self addButton:@"COPY LOG"
                  x:10 + buttonWidth y:276
              width:buttonWidth
             action:@selector(copyLog)
             parent:controller.view];

    [self addButton:@"ROI SHOW"
                  x:15 + 2 * buttonWidth y:276
              width:buttonWidth
             action:@selector(toggleMarker)
             parent:controller.view];

    [self addButton:@"LEFT"
                  x:5 y:311 width:buttonWidth
             action:@selector(roiLeft)
             parent:controller.view];

    [self addButton:@"UP"
                  x:10 + buttonWidth y:311
              width:buttonWidth
             action:@selector(roiUp)
             parent:controller.view];

    [self addButton:@"RIGHT"
                  x:15 + 2 * buttonWidth y:311
              width:buttonWidth
             action:@selector(roiRight)
             parent:controller.view];

    [self addButton:@"TRIM5"
                  x:5 y:346 width:buttonWidth
             action:@selector(toggleTrim)
             parent:controller.view];

    [self addButton:@"DOWN"
                  x:10 + buttonWidth y:346
              width:buttonWidth
             action:@selector(roiDown)
             parent:controller.view];

    [self addButton:@"RESET BAL"
                  x:15 + 2 * buttonWidth y:346
              width:buttonWidth
             action:@selector(resetBalance)
             parent:controller.view];

    self.panel.hidden = NO;
    [self.panel makeKeyAndVisible];

    [self updateMarker];
    [self refresh];

    [self log:@"V22 READY"];
    [self log:@"MOTION ROI x=.43 y=.30 w=.14 h=.10"];

    [self log:[NSString stringWithFormat:
        @"RESULT ROI x=%.3f y=%.3f w=%.2f h=%.2f",
        self.roiX,
        self.roiY,
        self.roiW,
        self.roiH]];

    [self log:@"NEW IMAGE REQUIRED FOR REPEATED SYMBOLS"];
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


#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>
#import <stdlib.h>

typedef NS_ENUM(NSInteger, CMSMotionState) {
    CMSReady = 0,
    CMSMoving = 1,
    CMSSettling = 2
};

@interface CMSSnapshot : NSObject
@property(nonatomic,assign) NSInteger cycle;
@property(nonatomic,strong) UIImage *image;
@property(nonatomic,assign) NSTimeInterval time;
@end

@implementation CMSSnapshot
@end

@interface CMSCrystalLogger : NSObject

@property(nonatomic,strong) UIWindow *panel;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UITextView *logView;
@property(nonatomic,strong) UIView *marker;

@property(nonatomic,strong) NSTimer *motionTimer;
@property(nonatomic,strong) NSTimer *balanceTimer;

@property(nonatomic,strong) NSMutableArray<NSString *> *logs;
@property(nonatomic,strong) NSMutableArray<CMSSnapshot *> *queue;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *counts;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSData *> *lastImages;

@property(nonatomic,strong) NSArray<NSData *> *previousMotion;
@property(nonatomic,copy) NSString *visibleSymbol;

@property(nonatomic,assign) BOOL running;
@property(nonatomic,assign) BOOL processing;
@property(nonatomic,assign) BOOL balanceBusy;
@property(nonatomic,assign) BOOL markerVisible;
@property(nonatomic,assign) BOOL trimFive;
@property(nonatomic,assign) BOOL hasBalance;
@property(nonatomic,assign) BOOL symbolDisappeared;

@property(nonatomic,assign) NSUInteger generation;
@property(nonatomic,assign) CMSMotionState motionState;

@property(nonatomic,assign) NSInteger cycles;
@property(nonatomic,assign) NSInteger recognized;
@property(nonatomic,assign) NSInteger unknown;
@property(nonatomic,assign) NSInteger duplicates;
@property(nonatomic,assign) NSInteger review;
@property(nonatomic,assign) NSInteger balanceEstimate;
@property(nonatomic,assign) NSInteger bet;

@property(nonatomic,assign) long long balance;
@property(nonatomic,assign) long long candidateBalance;
@property(nonatomic,assign) NSInteger balanceHits;
@property(nonatomic,assign) NSInteger candidateBet;
@property(nonatomic,assign) NSInteger betHits;

@property(nonatomic,assign) NSInteger motionHits;
@property(nonatomic,assign) NSInteger quietHits;
@property(nonatomic,assign) NSInteger frameCount;
@property(nonatomic,assign) NSInteger fpsStartFrames;

@property(nonatomic,assign) NSTimeInterval lastMotion;
@property(nonatomic,assign) NSTimeInterval lastCycle;
@property(nonatomic,assign) NSTimeInterval motionStarted;
@property(nonatomic,assign) NSTimeInterval fpsStart;
@property(nonatomic,assign) double fps;

@property(nonatomic,assign) CGFloat roiX;
@property(nonatomic,assign) CGFloat roiY;
@property(nonatomic,assign) CGFloat roiW;
@property(nonatomic,assign) CGFloat roiH;

+ (instancetype)shared;
- (void)start;
- (void)processNext;
@end

@implementation CMSCrystalLogger

+ (instancetype)shared {
    static CMSCrystalLogger *obj;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        obj = [CMSCrystalLogger new];

        obj.logs = [NSMutableArray new];
        obj.queue = [NSMutableArray new];

        obj.counts = [@{
            @"ATTACK": @0,
            @"STEAL": @0,
            @"SHIELD": @0,
            @"POINT": @0,
            @"SPINS": @0
        } mutableCopy];

        obj.lastImages = [NSMutableDictionary new];

        obj.visibleSymbol = @"";
        obj.symbolDisappeared = YES;
        obj.markerVisible = YES;
        obj.trimFive = YES;

        obj.roiX = .390;
        obj.roiY = .230;
        obj.roiW = .220;
        obj.roiH = .100;
    });

    return obj;
}

#pragma mark - Logging

- (void)log:(NSString *)message {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self log:message];
        });
        return;
    }

    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"HH:mm:ss.SSS";

    NSString *line = [NSString stringWithFormat:
        @"%@ %@",
        [fmt stringFromDate:[NSDate date]],
        message
    ];

    [self.logs addObject:line];

    if (self.logs.count > 1500) {
        [self.logs removeObjectAtIndex:0];
    }

    NSLog(@"[CMSCrystalV23] %@", line);

    if (self.logView) {
        self.logView.text =
            [self.logs componentsJoinedByString:@"\n"];

        NSUInteger length = self.logView.text.length;

        if (length) {
            [self.logView scrollRangeToVisible:
                NSMakeRange(length - 1, 1)];
        }
    }
}

- (void)refresh {
    NSString *state = @"READY";

    if (self.motionState == CMSMoving) {
        state = @"MOVING";
    } else if (self.motionState == CMSSettling) {
        state = @"SETTLING";
    }

    self.status.text = [NSString stringWithFormat:
        @"V23 %@ | %.1f FPS | %@\n"
        @"SPINS %ld | BAL EST %ld | BET x%ld\n"
        @"BAL %@ | QUEUE %ld\n"
        @"FOUND %ld | UNKNOWN %ld\n"
        @"SAME %ld | REVIEW %ld\n"
        @"ATT %@  STEAL %@  SHIELD %@\n"
        @"POINT %@  SPINS %@",

        self.running ? @"ON" : @"OFF",
        self.fps,
        state,

        (long)self.cycles,
        (long)self.balanceEstimate,
        (long)self.bet,

        self.hasBalance
            ? [NSString stringWithFormat:@"%lld", self.balance]
            : @"WAIT",

        (long)self.queue.count,
        (long)self.recognized,
        (long)self.unknown,

        (long)self.duplicates,
        (long)self.review,

        self.counts[@"ATTACK"],
        self.counts[@"STEAL"],
        self.counts[@"SHIELD"],
        self.counts[@"POINT"],
        self.counts[@"SPINS"]
    ];
}

#pragma mark - Game window

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

- (void)updateMarker {
    UIWindow *game = [self gameWindow];
    if (!game) return;

    if (!self.marker) {
        self.marker = [UIView new];

        self.marker.userInteractionEnabled = NO;

        self.marker.backgroundColor =
            [UIColor colorWithRed:0
                            green:1
                             blue:0
                            alpha:.08];

        self.marker.layer.borderWidth = 2;
        self.marker.layer.borderColor =
            UIColor.systemGreenColor.CGColor;
    }

    if (self.marker.superview != game) {
        [self.marker removeFromSuperview];
        [game addSubview:self.marker];
    }

    CGSize s = game.bounds.size;

    self.marker.frame = CGRectMake(
        s.width * self.roiX,
        s.height * self.roiY,
        s.width * self.roiW,
        s.height * self.roiH
    );

    self.marker.hidden = !self.markerVisible;
}

- (UIImage *)capture {
    UIWindow *game = [self gameWindow];
    if (!game) return nil;

    BOOL wasHidden = self.marker.hidden;
    self.marker.hidden = YES;

    UIGraphicsImageRendererFormat *format =
        [UIGraphicsImageRendererFormat defaultFormat];

    format.scale = 1;
    format.opaque = YES;

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc]
            initWithSize:game.bounds.size
                  format:format];

    UIImage *image =
        [renderer imageWithActions:
            ^(UIGraphicsImageRendererContext *context) {

                [game drawViewHierarchyInRect:
                    game.bounds
                    afterScreenUpdates:NO];
            }];

    self.marker.hidden = wasHidden;

    return image;
}

- (CGImageRef)crop:(CGImageRef)image
                x:(CGFloat)x
                y:(CGFloat)y
                w:(CGFloat)w
                h:(CGFloat)h {

    if (!image) return NULL;

    CGRect bounds = CGRectMake(
        0, 0,
        CGImageGetWidth(image),
        CGImageGetHeight(image)
    );

    CGRect region = CGRectIntersection(
        bounds,
        CGRectIntegral(CGRectMake(
            bounds.size.width * x,
            bounds.size.height * y,
            bounds.size.width * w,
            bounds.size.height * h
        ))
    );

    if (CGRectIsEmpty(region)) return NULL;

    return CGImageCreateWithImageInRect(
        image, region
    );
}

#pragma mark - Grayscale image signatures

- (NSData *)pixels:(CGImageRef)image
             width:(size_t)width
            height:(size_t)height {

    if (!image) return nil;

    NSMutableData *data =
        [NSMutableData dataWithLength:width * height];

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
            kCGImageAlphaNone
        );

    CGColorSpaceRelease(space);

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

    const uint8_t *pa = a.bytes;
    const uint8_t *pb = b.bytes;

    double sum = 0;

    for (NSUInteger i = 0; i < a.length; i++) {
        sum += abs((int)pa[i] - (int)pb[i]);
    }

    return sum / (a.length * 255.0);
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

    NSMutableArray *result = [NSMutableArray new];

    for (VNRecognizedTextObservation *obs
         in request.results) {

        VNRecognizedText *text =
            [[obs topCandidates:1] firstObject];

        if (text) {
            [result addObject:@{
                @"text": text.string,
                @"confidence": @(text.confidence)
            }];
        }
    }

    return result;
}

- (NSString *)raw:(NSArray<NSDictionary *> *)items {
    NSMutableArray *parts = [NSMutableArray new];

    for (NSDictionary *item in items) {
        [parts addObject:item[@"text"]];
    }

    return [parts componentsJoinedByString:@" | "];
}

- (NSString *)digits:(NSString *)text {
    NSMutableString *digits = [NSMutableString new];

    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];

        if (c >= '0' && c <= '9') {
            [digits appendFormat:@"%C", c];
        }
    }

    return digits;
}

- (NSString *)symbol:(NSArray<NSDictionary *> *)items {
    NSMutableSet<NSString *> *matches =
        [NSMutableSet new];

    for (NSDictionary *item in items) {
        if ([item[@"confidence"] floatValue] < .35f) {
            continue;
        }

        NSString *source =
            [item[@"text"] uppercaseString];

        NSMutableString *letters =
            [NSMutableString new];

        for (NSUInteger i = 0; i < source.length; i++) {
            unichar c = [source characterAtIndex:i];

            if (c >= 'A' && c <= 'Z') {
                [letters appendFormat:@"%C", c];
            }
        }

        NSString *s = letters;

        if ([s containsString:@"ATTACK"] ||
            [s isEqualToString:@"TTACK"] ||
            [s isEqualToString:@"ATTAC"]) {
            [matches addObject:@"ATTACK"];
        }

        if ([s containsString:@"STEAL"] ||
            [s isEqualToString:@"TEAL"]) {
            [matches addObject:@"STEAL"];
        }

        if ([s containsString:@"SHIELD"] ||
            [s isEqualToString:@"HIELD"] ||
            [s isEqualToString:@"AIELD"]) {
            [matches addObject:@"SHIELD"];
        }

        if ([s containsString:@"POINT"] ||
            [s isEqualToString:@"OINT"] ||
            [s isEqualToString:@"POIN"]) {
            [matches addObject:@"POINT"];
        }

        if ([s containsString:@"SPINS"] ||
            [s isEqualToString:@"PINS"]) {
            [matches addObject:@"SPINS"];
        }
    }

    return matches.count == 1
        ? matches.anyObject
        : @"";
}

#pragma mark - Snapshot result queue

- (void)queueSnapshot:(UIImage *)image {
    if (!image) {
        [self log:@"SNAPSHOT FAILED"];
        return;
    }

    CMSSnapshot *snapshot = [CMSSnapshot new];

    snapshot.cycle = self.cycles;
    snapshot.image = image;
    snapshot.time =
        [NSDate date].timeIntervalSince1970;

    [self.queue addObject:snapshot];

    [self log:[NSString stringWithFormat:
        @"SNAPSHOT SAVED CYCLE %ld | QUEUE %ld",
        (long)snapshot.cycle,
        (long)self.queue.count]];

    [self processNext];
}

- (void)processNext {
    if (!self.running ||
        self.processing ||
        self.queue.count == 0) {
        return;
    }

    self.processing = YES;

    CMSSnapshot *snapshot =
        self.queue.firstObject;

    [self.queue removeObjectAtIndex:0];

    NSUInteger gen = self.generation;

    CGFloat x = self.roiX;
    CGFloat y = self.roiY;
    CGFloat w = self.roiW;
    CGFloat h = self.roiH;

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED, 0), ^{

        @autoreleasepool {
            CGImageRef region =
                [self crop:snapshot.image.CGImage
                        x:x y:y w:w h:h];

            NSArray *items = [self ocr:region];
            NSString *symbol = [self symbol:items];
            NSString *raw = [self raw:items];

            /*
             Image signature uses the right-hand
             portion of the result ROI, where the
             symbol text has appeared in prior logs.
             This reduces interference from numbers
             on the left, but does not eliminate it.
            */

            CGImageRef symbolRegion = NULL;

            if (region) {
                symbolRegion =
                    [self crop:region
                            x:.52 y:.05
                            w:.46 h:.90];
            }

            NSData *signature =
                [self pixels:symbolRegion
                       width:32
                      height:24];

            if (symbolRegion) {
                CGImageRelease(symbolRegion);
            }

            if (region) {
                CGImageRelease(region);
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (gen != self.generation ||
                    !self.running) {
                    self.processing = NO;
                    return;
                }

                [self evaluateSymbol:symbol
                                raw:raw
                              image:signature
                              cycle:snapshot.cycle];

                self.processing = NO;
                [self refresh];
                [self processNext];
            });
        }
    });
}

- (void)evaluateSymbol:(NSString *)symbol
                   raw:(NSString *)raw
                 image:(NSData *)image
                 cycle:(NSInteger)cycle {

    [self log:[NSString stringWithFormat:
        @"SNAPSHOT RESULT CYCLE %ld: %@ | %@",
        (long)cycle,
        symbol.length ? symbol : @"?",
        raw]];

    if (!symbol.length) {
        self.unknown++;

        /*
         An unknown OCR result is not proof that
         the previous symbol disappeared.
         Therefore do not clear visibleSymbol.
        */

        [self log:[NSString stringWithFormat:
            @"CYCLE %ld UNKNOWN | NOT PROOF OF CLEAR",
            (long)cycle]];

        return;
    }

    NSData *oldImage = self.lastImages[symbol];

    BOOL sameVisible =
        [self.visibleSymbol isEqualToString:symbol];

    if (!oldImage) {
        self.counts[symbol] =
            @([self.counts[symbol] integerValue] + 1);

        self.recognized++;

        if (image) {
            self.lastImages[symbol] = image;
        }

        self.visibleSymbol = symbol;
        self.symbolDisappeared = NO;

        [self log:[NSString stringWithFormat:
            @"CYCLE %ld FIRST %@ | COUNTED",
            (long)cycle, symbol]];

        return;
    }

    double diff =
        [self difference:oldImage b:image];

    if (sameVisible && diff >= 0 && diff < .055) {
        self.duplicates++;

        [self log:[NSString stringWithFormat:
            @"CYCLE %ld SAME %@ IMAGE %.4f | NOT COUNTED",
            (long)cycle, symbol, diff]];

        return;
    }

    /*
     A changed image alone is not enough to prove
     a new ATTACK. A result must be seen after
     another recognized symbol to count a new
     occurrence automatically.

     Consecutive identical symbols with changed
     images are marked REVIEW instead.
    */

    if (!sameVisible && diff >= 0) {
        self.counts[symbol] =
            @([self.counts[symbol] integerValue] + 1);

        self.recognized++;
        self.visibleSymbol = symbol;

        if (image) {
            self.lastImages[symbol] = image;
        }

        [self log:[NSString stringWithFormat:
            @"CYCLE %ld NEW %@ AFTER SYMBOL CHANGE | DIFF %.4f | COUNTED",
            (long)cycle, symbol, diff]];

    } else {
        self.review++;

        [self log:[NSString stringWithFormat:
            @"CYCLE %ld %@ IMAGE CHANGE %.4f | REVIEW | NOT COUNTED",
            (long)cycle, symbol, diff]];

        /*
         Keep the previous reference image so
         later snapshots can still be compared
         against the original known result.
        */
    }
}

#pragma mark - Motion v23

- (NSArray<NSData *> *)motionPixels:(UIImage *)image {
    if (!image.CGImage) return nil;

    /*
     Three different areas are sampled.
     They are deliberately kept separate
     from the movable OCR ROI.
    */

    const CGFloat regions[3][4] = {
        { .43, .30, .14, .10 },
        { .34, .28, .12, .12 },
        { .56, .28, .12, .12 }
    };

    NSMutableArray *result = [NSMutableArray new];

    for (NSInteger i = 0; i < 3; i++) {
        CGImageRef crop =
            [self crop:image.CGImage
                    x:regions[i][0]
                    y:regions[i][1]
                    w:regions[i][2]
                    h:regions[i][3]];

        NSData *pixels =
            [self pixels:crop width:32 height:24];

        if (crop) CGImageRelease(crop);

        if (!pixels) return nil;

        [result addObject:pixels];
    }

    return result;
}

- (void)motionTick:(NSTimer *)timer {
    if (!self.running) return;

    UIImage *frame = [self capture];
    NSArray<NSData *> *current =
        [self motionPixels:frame];

    if (!current) return;

    NSTimeInterval now =
        [NSDate date].timeIntervalSince1970;

    self.frameCount++;

    if (self.fpsStart == 0) {
        self.fpsStart = now;
        self.fpsStartFrames = self.frameCount;

    } else if (now - self.fpsStart >= 2) {
        self.fps =
            (self.frameCount - self.fpsStartFrames) /
            (now - self.fpsStart);

        self.fpsStart = now;
        self.fpsStartFrames = self.frameCount;

        [self log:[NSString stringWithFormat:
            @"ACTUAL MOTION FPS %.1f",
            self.fps]];
    }

    if (!self.previousMotion) {
        self.previousMotion = current;
        return;
    }

    double scores[3] = {0, 0, 0};
    NSInteger active = 0;
    NSInteger quiet = 0;

    for (NSInteger i = 0; i < 3; i++) {
        scores[i] =
            [self difference:self.previousMotion[i]
                           b:current[i]];

        if (scores[i] > .045) active++;
        if (scores[i] < .018) quiet++;
    }

    self.previousMotion = current;

    BOOL moving =
        active >= 2 ||
        scores[0] > .075;

    BOOL stable = quiet >= 2;

    if (moving) {
        self.motionHits++;
        self.quietHits = 0;
        self.lastMotion = now;

    } else if (stable) {
        self.quietHits++;
        self.motionHits = 0;

    } else {
        self.motionHits = 0;
        self.quietHits = 0;
    }

    if (self.motionState == CMSReady) {
        if (moving && self.motionHits >= 1) {
            self.motionState = CMSMoving;
            self.motionStarted = now;

            [self log:[NSString stringWithFormat:
                @"MOTION START A%.3f B%.3f C%.3f",
                scores[0], scores[1], scores[2]]];
        }

    } else if (self.motionState == CMSMoving) {
        if (stable &&
            self.quietHits >= 2 &&
            now - self.lastMotion >= .10) {

            self.motionState = CMSSettling;

            [self log:@"WHEEL APPEARS STOPPED"];
        }

    } else if (self.motionState == CMSSettling) {
        if (moving) {
            self.motionState = CMSMoving;
            self.quietHits = 0;

            [self log:@"MOTION RESUMED"];

        } else if (stable && self.quietHits >= 4) {
            NSTimeInterval duration =
                now - self.motionStarted;

            if (now - self.lastCycle >= .28 &&
                duration >= .12) {

                self.cycles++;
                self.lastCycle = now;

                [self log:[NSString stringWithFormat:
                    @"OBSERVED CYCLE #%ld | DURATION %.2f",
                    (long)self.cycles, duration]];

                /*
                 The image is captured from the
                 current motion frame immediately.
                 OCR can run later without changing
                 which cycle the image belongs to.
                */

                [self queueSnapshot:frame];
            }

            self.motionState = CMSReady;
            self.motionHits = 0;
            self.quietHits = 0;
        }
    }

    if (self.frameCount % 10 == 0) {
        [self refresh];
    }
}

#pragma mark - Balance OCR

- (void)balanceTick:(NSTimer *)timer {
    if (!self.running || self.balanceBusy) return;

    self.balanceBusy = YES;

    UIImage *image = [self capture];

    if (!image.CGImage) {
        self.balanceBusy = NO;
        return;
    }

    CGImageRef balanceRegion =
        [self crop:image.CGImage
                x:.39 y:.828 w:.23 h:.036];

    CGImageRef betRegion =
        [self crop:image.CGImage
                x:.58 y:.695 w:.20 h:.085];

    NSUInteger gen = self.generation;

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED, 0), ^{

        @autoreleasepool {
            NSArray *balanceText =
                [self ocr:balanceRegion];

            NSArray *betText =
                [self ocr:betRegion];

            if (balanceRegion) {
                CGImageRelease(balanceRegion);
            }

            if (betRegion) {
                CGImageRelease(betRegion);
            }

            long long value = -1;
            NSInteger bet = 0;

            for (NSDictionary *item in balanceText) {
                NSString *s = item[@"text"];

                if (![s hasPrefix:@"+"]) continue;

                NSString *digits =
                    [self digits:s];

                if (digits.length < 4 ||
                    digits.length > 12) {
                    continue;
                }

                value = digits.longLongValue;

                if (self.trimFive &&
                    digits.length == 7 &&
                    [digits hasSuffix:@"5"]) {
                    value /= 10;
                }

                break;
            }

            for (NSDictionary *item in betText) {
                NSString *s =
                    [[item[@"text"] uppercaseString]
                        stringByReplacingOccurrencesOfString:@" "
                        withString:@""];

                if ([s hasPrefix:@"X"] ||
                    [s hasPrefix:@"×"] ||
                    [s hasPrefix:@"*"]) {

                    NSString *digits =
                        [s substringFromIndex:1];

                    if (digits.length &&
                        digits.length <= 5 &&
                        [[self digits:digits]
                            isEqualToString:digits]) {

                        bet = digits.integerValue;
                        break;
                    }
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (gen != self.generation) return;

                self.balanceBusy = NO;

                if (!self.running) return;

                [self processBalance:value bet:bet];
            });
        }
    });
}

- (void)processBalance:(long long)value
                   bet:(NSInteger)newBet {

    if (newBet > 0 && newBet <= 10000) {
        if (newBet == self.candidateBet) {
            self.betHits++;
        } else {
            self.candidateBet = newBet;
            self.betHits = 1;
        }

        if (self.betHits >= 2 && self.bet != newBet) {
            self.bet = newBet;

            [self log:[NSString stringWithFormat:
                @"BET VERIFIED x%ld",
                (long)newBet]];
        }
    }

    if (value < 0) return;

    if (value == self.candidateBalance) {
        self.balanceHits++;
    } else {
        self.candidateBalance = value;
        self.balanceHits = 1;
    }

    if (self.balanceHits < 2) return;

    if (!self.hasBalance) {
        self.hasBalance = YES;
        self.balance = value;

        [self log:[NSString stringWithFormat:
            @"BALANCE BASELINE %lld",
            value]];

        return;
    }

    if (value == self.balance) return;

    long long delta = value - self.balance;

    if (llabs(delta) > 100000) {
        [self log:[NSString stringWithFormat:
            @"BALANCE OCR REJECTED %lld",
            value]];
        return;
    }

    [self log:[NSString stringWithFormat:
        @"BALANCE %lld -> %lld (%+lld)",
        self.balance, value, delta]];

    self.balance = value;

    if (delta < 0 && self.bet > 0) {
        long long cost = -delta;

        if (cost % self.bet == 0) {
            long long spins = cost / self.bet;

            if (spins > 0 && spins <= 100) {
                self.balanceEstimate += (NSInteger)spins;

                [self log:[NSString stringWithFormat:
                    @"BALANCE ESTIMATE +%lld | TOTAL %ld | NOT VERIFIED",
                    spins,
                    (long)self.balanceEstimate]];
            }
        }
    }

    [self refresh];
}

#pragma mark - Controls

- (void)toggle {
    if (self.running) {
        self.running = NO;
        self.generation++;

        [self.motionTimer invalidate];
        [self.balanceTimer invalidate];

        self.motionTimer = nil;
        self.balanceTimer = nil;

        [self.queue removeAllObjects];

        self.processing = NO;
        self.balanceBusy = NO;

        [self log:@"AUTO STOPPED V23"];

    } else {
        self.running = YES;
        self.generation++;

        self.cycles = 0;
        self.recognized = 0;
        self.unknown = 0;
        self.duplicates = 0;
        self.review = 0;
        self.balanceEstimate = 0;

        self.bet = 0;
        self.betHits = 0;
        self.candidateBet = 0;

        self.hasBalance = NO;
        self.balanceHits = 0;

        self.motionState = CMSReady;
        self.previousMotion = nil;

        self.motionHits = 0;
        self.quietHits = 0;

        self.frameCount = 0;
        self.fpsStartFrames = 0;
        self.fpsStart = 0;
        self.fps = 0;

        self.lastCycle = 0;
        self.lastMotion = 0;

        self.processing = NO;
        self.balanceBusy = NO;

        self.visibleSymbol = @"";
        self.symbolDisappeared = YES;

        [self.queue removeAllObjects];
        [self.lastImages removeAllObjects];

        for (NSString *key in self.counts.allKeys) {
            self.counts[key] = @0;
        }

        self.motionTimer =
            [NSTimer scheduledTimerWithTimeInterval:.05
                                             target:self
                                           selector:@selector(motionTick:)
                                           userInfo:nil
                                            repeats:YES];

        self.balanceTimer =
            [NSTimer scheduledTimerWithTimeInterval:.60
                                             target:self
                                           selector:@selector(balanceTick:)
                                           userInfo:nil
                                            repeats:YES];

        [self log:@"AUTO STARTED V23"];
        [self log:@"THREE MOTION REGIONS ENABLED"];
        [self log:@"IMMEDIATE RESULT SNAPSHOTS ENABLED"];
        [self log:@"OCR SNAPSHOT QUEUE ENABLED"];
        [self log:@"REPEATED ATTACK REQUIRES NEW EVIDENCE"];

        [self balanceTick:nil];
    }

    [self refresh];
}

- (void)copyLog {
    [self log:@"LOG COPIED"];

    UIPasteboard.generalPasteboard.string =
        [self.logs componentsJoinedByString:@"\n"];
}

- (void)moveROI:(CGFloat)dx dy:(CGFloat)dy {
    self.roiX =
        MAX(0, MIN(1 - self.roiW, self.roiX + dx));

    self.roiY =
        MAX(0, MIN(1 - self.roiH, self.roiY + dy));

    [self updateMarker];

    [self log:[NSString stringWithFormat:
        @"ROI x=%.3f y=%.3f",
        self.roiX, self.roiY]];
}

- (void)left {
    [self moveROI:-.01 dy:0];
}

- (void)right {
    [self moveROI:.01 dy:0];
}

- (void)up {
    [self moveROI:0 dy:-.01];
}

- (void)down {
    [self moveROI:0 dy:.01];
}

- (void)toggleMarker {
    self.markerVisible = !self.markerVisible;
    [self updateMarker];

    [self log:self.markerVisible
        ? @"ROI VISIBLE"
        : @"ROI HIDDEN"];
}

- (void)toggleTrim {
    self.trimFive = !self.trimFive;
    self.hasBalance = NO;
    self.balanceHits = 0;

    [self log:self.trimFive
        ? @"TRIM5 ON"
        : @"TRIM5 OFF"];
}

- (void)resetBalance {
    self.hasBalance = NO;
    self.balanceHits = 0;

    [self log:@"BALANCE BASELINE RESET"];
}

#pragma mark - UI

- (void)movePanel:(UIPanGestureRecognizer *)gesture {
    CGPoint delta =
        [gesture translationInView:self.panel];

    CGRect frame = self.panel.frame;

    frame.origin.x += delta.x;
    frame.origin.y += delta.y;

    self.panel.frame = frame;

    [gesture setTranslation:CGPointZero
                    inView:self.panel];
}

- (void)button:(NSString *)title
             x:(CGFloat)x
             y:(CGFloat)y
             w:(CGFloat)width
        action:(SEL)action
          view:(UIView *)view {

    UIButton *button =
        [UIButton buttonWithType:UIButtonTypeSystem];

    button.frame =
        CGRectMake(x, y, width, 29);

    [button setTitle:title
           forState:UIControlStateNormal];

    [button setTitleColor:UIColor.whiteColor
                forState:UIControlStateNormal];

    button.backgroundColor =
        [UIColor colorWithWhite:.23 alpha:1];

    button.layer.cornerRadius = 6;

    button.titleLabel.font =
        [UIFont boldSystemFontOfSize:10];

    [button addTarget:self
               action:action
     forControlEvents:UIControlEventTouchUpInside];

    [view addSubview:button];
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
        [UIColor colorWithRed:.06
                        green:.08
                         blue:.12
                        alpha:.96];

    controller.view.layer.cornerRadius = 12;
    controller.view.clipsToBounds = YES;

    self.panel.rootViewController = controller;

    UILabel *title =
        [[UILabel alloc] initWithFrame:
            CGRectMake(10, 5, width - 20, 26)];

    title.text = @"CMSCrystalLogger v23";
    title.textColor = UIColor.whiteColor;

    title.font =
        [UIFont boldSystemFontOfSize:15];

    title.userInteractionEnabled = YES;

    [title addGestureRecognizer:
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(movePanel:)]];

    [controller.view addSubview:title];

    self.status =
        [[UILabel alloc] initWithFrame:
            CGRectMake(10, 32, width - 20, 126)];

    self.status.numberOfLines = 7;

    self.status.textColor =
        UIColor.systemGreenColor;

    self.status.font =
        [UIFont monospacedSystemFontOfSize:10
                                   weight:UIFontWeightMedium];

    self.status.adjustsFontSizeToFitWidth = YES;
    self.status.minimumScaleFactor = .7;

    [controller.view addSubview:self.status];

    self.logView =
        [[UITextView alloc] initWithFrame:
            CGRectMake(8, 160, width - 16, 110)];

    self.logView.backgroundColor =
        UIColor.clearColor;

    self.logView.textColor =
        UIColor.systemGreenColor;

    self.logView.font =
        [UIFont monospacedSystemFontOfSize:9
                                   weight:UIFontWeightRegular];

    self.logView.editable = NO;

    [controller.view addSubview:self.logView];

    CGFloat bw = (width - 30) / 3;

    [self button:@"AUTO"
               x:5 y:276 w:bw
          action:@selector(toggle)
            view:controller.view];

    [self button:@"COPY LOG"
               x:10 + bw y:276 w:bw
          action:@selector(copyLog)
            view:controller.view];

    [self button:@"ROI SHOW"
               x:15 + bw * 2 y:276 w:bw
          action:@selector(toggleMarker)
            view:controller.view];

    [self button:@"LEFT"
               x:5 y:311 w:bw
          action:@selector(left)
            view:controller.view];

    [self button:@"UP"
               x:10 + bw y:311 w:bw
          action:@selector(up)
            view:controller.view];

    [self button:@"RIGHT"
               x:15 + bw * 2 y:311 w:bw
          action:@selector(right)
            view:controller.view];

    [self button:@"TRIM5"
               x:5 y:346 w:bw
          action:@selector(toggleTrim)
            view:controller.view];

    [self button:@"DOWN"
               x:10 + bw y:346 w:bw
          action:@selector(down)
            view:controller.view];

    [self button:@"RESET BAL"
               x:15 + bw * 2 y:346 w:bw
          action:@selector(resetBalance)
            view:controller.view];

    self.panel.hidden = NO;
    [self.panel makeKeyAndVisible];

    [self updateMarker];
    [self refresh];

    [self log:@"V23 READY"];
    [self log:@"MOTION REGIONS 3 | TARGET 20 FPS"];

    [self log:[NSString stringWithFormat:
        @"RESULT ROI x=%.3f y=%.3f w=%.2f h=%.2f",
        self.roiX, self.roiY,
        self.roiW, self.roiH]];

    [self log:@"SNAPSHOTS SAVED AT CYCLE END"];
    [self log:@"SYMBOL COUNTS ARE UNVERIFIED"];
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

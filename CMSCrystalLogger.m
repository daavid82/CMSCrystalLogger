
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>

#pragma mark - CMSCrystalLogger v27

@interface CMSLoggerWindow : UIWindow
@property(nonatomic,weak) UIView *activeArea;
@end

@implementation CMSLoggerWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *a = self.activeArea;
    if (!a || a.hidden) return nil;
    CGPoint q = [a convertPoint:p fromView:self];
    if (![a pointInside:q withEvent:e]) return nil;
    UIView *v = [super hitTest:p withEvent:e];
    return v == self || v == self.rootViewController.view
        ? nil : v;
}
@end

@interface CMSCrystalLogger : NSObject

@property(nonatomic,strong) UIWindow *panel;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UITextView *logView;
@property(nonatomic,strong) UIView *marker;
@property(nonatomic,strong) NSTimer *timer;

@property(nonatomic,strong) NSMutableArray<NSString *> *logs;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSNumber *> *counts;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSData *> *symbolImages;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *snapshots;
@property(nonatomic,strong) NSArray<NSData *> *previousMotion;

@property(nonatomic,copy) NSString *lastSymbol;
@property(nonatomic,strong) NSData *previousResultSignature;

@property(nonatomic,assign) BOOL resultTransitionSeen;
@property(nonatomic,assign) BOOL running,ocrBusy,processing;
@property(nonatomic,assign) BOOL markerVisible,trimFive,hasBalance,motionActive;
@property(nonatomic,assign) NSUInteger generation;

@property(nonatomic,assign) NSInteger motionStarts,motionStops;
@property(nonatomic,assign) NSInteger visualCycles,unknown,review,duplicates;
@property(nonatomic,assign) NSInteger bet,betCandidate,betHits,balanceHits;
@property(nonatomic,assign) NSInteger frameCount,motionQuiet,spinCandidates;
@property(nonatomic,assign) NSInteger ignoredOnsets,balanceEvents,positiveBalanceEvents;

@property(nonatomic,assign) long long balance,balanceCandidate;
@property(nonatomic,assign) long long estimatedSpins,positiveBalanceTotal;

@property(nonatomic,assign) NSTimeInterval lastTick,lastMotionStart;
@property(nonatomic,assign) NSTimeInterval lastVisualCycle,lastBalanceCheck;
@property(nonatomic,assign) NSTimeInterval lastResultCheck,lastFpsLog;
@property(nonatomic,assign) NSTimeInterval lastCandidateTime,lastResultSnapshotTime;

@property(nonatomic,assign) NSInteger fpsFrames;
@property(nonatomic,assign) double fps;
@property(nonatomic,assign) CGFloat rx,ry,rw,rh;

@property(nonatomic,strong) CMSLoggerWindow *overlay;
@property(nonatomic,strong) UIView *bubble;
@property(nonatomic,strong) UIView *expandedView;
@property(nonatomic,strong) UIButton *bubbleButton;
@property(nonatomic,assign) BOOL expanded;

+ (instancetype)shared;
@end

@implementation CMSCrystalLogger

+ (instancetype)shared {
    static CMSCrystalLogger *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [CMSCrystalLogger new];
        s.logs = [NSMutableArray new];
        s.snapshots = [NSMutableArray new];
        s.counts = [@{
            @"ATTACK":@0,
            @"STEAL":@0,
            @"SHIELD":@0,
            @"POINT":@0,
            @"SPINS":@0
        } mutableCopy];
        s.symbolImages = [NSMutableDictionary new];
        s.lastSymbol = @"";
        s.markerVisible = NO;
        s.trimFive = YES;
        s.rx = .390;
        s.ry = .230;
        s.rw = .220;
        s.rh = .100;
    });
    return s;
}

#pragma mark - Logging

- (void)log:(NSString *)s {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self log:s];
        });
        return;
    }

    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"HH:mm:ss.SSS";

    NSString *line = [NSString stringWithFormat:@"%@ %@",
        [f stringFromDate:[NSDate date]], s];

    [self.logs addObject:line];

    if (self.logs.count > 2000)
        [self.logs removeObjectAtIndex:0];

    NSLog(@"[CMSCrystalV27] %@", line);

    if (self.expanded && self.logView) {
        self.logView.text =
            [self.logs componentsJoinedByString:@"\n"];

        NSUInteger n = self.logView.text.length;
        if (n)
            [self.logView scrollRangeToVisible:
                NSMakeRange(n-1, 1)];
    }
}

#pragma mark - Game capture

- (UIWindow *)gameWindow {
    UIWindow *best = nil;

    for (UIScene *scene in
         UIApplication.sharedApplication.connectedScenes) {

        if (![scene isKindOfClass:UIWindowScene.class])
            continue;

        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w == self.overlay ||
                w == self.panel ||
                w.hidden ||
                w.bounds.size.width < 100 ||
                w.bounds.size.height < 100)
                continue;

            if (!best || w.windowLevel < best.windowLevel)
                best = w;
        }
    }

    return best;
}

- (void)markerUpdate {
    UIWindow *w = [self gameWindow];
    if (!w) return;

    if (!self.marker) {
        self.marker = [UIView new];
        self.marker.userInteractionEnabled = NO;
        self.marker.layer.borderWidth = 2;
        self.marker.layer.borderColor =
            UIColor.systemGreenColor.CGColor;
        self.marker.backgroundColor =
            [UIColor colorWithRed:0 green:1 blue:0 alpha:.08];
    }

    if (self.marker.superview != w) {
        [self.marker removeFromSuperview];
        [w addSubview:self.marker];
    }

    CGSize s = w.bounds.size;
    self.marker.frame = CGRectMake(
        s.width*self.rx,
        s.height*self.ry,
        s.width*self.rw,
        s.height*self.rh);

    self.marker.hidden = !self.markerVisible;
}

- (UIImage *)capture {
    UIWindow *w = [self gameWindow];
    if (!w) return nil;

    BOOL hidden = self.marker.hidden;
    self.marker.hidden = YES;

    UIGraphicsImageRendererFormat *fmt =
        [UIGraphicsImageRendererFormat defaultFormat];

    fmt.scale = 1;
    fmt.opaque = YES;

    UIGraphicsImageRenderer *r =
        [[UIGraphicsImageRenderer alloc]
            initWithSize:w.bounds.size format:fmt];

    UIImage *img = [r imageWithActions:
        ^(UIGraphicsImageRendererContext *ctx) {
            [w drawViewHierarchyInRect:w.bounds
                    afterScreenUpdates:NO];
        }];

    self.marker.hidden = hidden;
    return img;
}

- (CGImageRef)crop:(CGImageRef)img
                 x:(CGFloat)x
                 y:(CGFloat)y
                 w:(CGFloat)w
                 h:(CGFloat)h {

    if (!img) return NULL;

    CGRect bounds = CGRectMake(
        0,0,CGImageGetWidth(img),CGImageGetHeight(img));

    CGRect rect = CGRectIntersection(
        bounds,
        CGRectIntegral(CGRectMake(
            bounds.size.width*x,
            bounds.size.height*y,
            bounds.size.width*w,
            bounds.size.height*h)));

    return CGRectIsEmpty(rect)
        ? NULL
        : CGImageCreateWithImageInRect(img,rect);
}

- (NSData *)pixels:(CGImageRef)img
             width:(size_t)w
            height:(size_t)h {

    if (!img) return nil;

    NSMutableData *d =
        [NSMutableData dataWithLength:w*h];

    CGColorSpaceRef sp =
        CGColorSpaceCreateDeviceGray();

    CGContextRef ctx = CGBitmapContextCreate(
        d.mutableBytes,w,h,8,w,sp,kCGImageAlphaNone);

    CGColorSpaceRelease(sp);

    if (!ctx) return nil;

    CGContextSetInterpolationQuality(
        ctx,kCGInterpolationLow);

    CGContextDrawImage(
        ctx,CGRectMake(0,0,w,h),img);

    CGContextRelease(ctx);
    return d;
}

- (double)difference:(NSData *)a b:(NSData *)b {
    if (!a || !b || a.length != b.length)
        return -1;

    const uint8_t *x = a.bytes;
    const uint8_t *y = b.bytes;
    double sum = 0;

    for (NSUInteger i=0;i<a.length;i++)
        sum += abs((int)x[i]-(int)y[i]);

    return sum/(a.length*255.0);
}

#pragma mark - OCR

- (NSArray<NSDictionary *> *)ocr:(CGImageRef)img {
    if (!img) return @[];

    VNRecognizeTextRequest *req =
        [VNRecognizeTextRequest new];

    req.recognitionLevel =
        VNRequestTextRecognitionLevelAccurate;

    req.usesLanguageCorrection = NO;
    req.recognitionLanguages = @[@"en-US"];

    VNImageRequestHandler *handler =
        [[VNImageRequestHandler alloc]
            initWithCGImage:img options:@{}];

    NSError *err = nil;

    if (![handler performRequests:@[req] error:&err])
        return @[];

    NSMutableArray *a = [NSMutableArray new];

    for (VNRecognizedTextObservation *o in req.results) {
        VNRecognizedText *t =
            [[o topCandidates:1] firstObject];

        if (t) {
            [a addObject:@{
                @"text":t.string,
                @"confidence":@(t.confidence)
            }];
        }
    }

    return a;
}

- (NSString *)raw:(NSArray *)items {
    NSMutableArray *a = [NSMutableArray new];

    for (NSDictionary *d in items)
        [a addObject:d[@"text"]];

    return [a componentsJoinedByString:@" | "];
}

- (NSString *)digits:(NSString *)s {
    NSMutableString *d = [NSMutableString new];

    for (NSUInteger i=0;i<s.length;i++) {
        unichar c = [s characterAtIndex:i];
        if (c>='0' && c<='9')
            [d appendFormat:@"%C",c];
    }

    return d;
}

- (NSString *)symbol:(NSArray *)items {
    NSMutableSet *found = [NSMutableSet new];

    for (NSDictionary *d in items) {
        if ([d[@"confidence"] doubleValue] < .35)
            continue;

        NSString *s = [d[@"text"] uppercaseString];
        NSMutableString *letters = [NSMutableString new];

        for (NSUInteger i=0;i<s.length;i++) {
            unichar c = [s characterAtIndex:i];
            if (c>='A' && c<='Z')
                [letters appendFormat:@"%C",c];
        }

        if ([letters containsString:@"ATTACK"] ||
            [letters isEqualToString:@"TTACK"])
            [found addObject:@"ATTACK"];

        if ([letters containsString:@"STEAL"] ||
            [letters isEqualToString:@"TEAL"])
            [found addObject:@"STEAL"];

        if ([letters containsString:@"SHIELD"] ||
            [letters isEqualToString:@"HIELD"])
            [found addObject:@"SHIELD"];

        if ([letters containsString:@"POINT"] ||
            [letters isEqualToString:@"OINT"])
            [found addObject:@"POINT"];

        if ([letters containsString:@"SPINS"] ||
            [letters isEqualToString:@"PINS"])
            [found addObject:@"SPINS"];
    }

    return found.count == 1 ? found.anyObject : @"";
}

#pragma mark - Result queue

- (void)enqueueResult:(UIImage *)img
               reason:(NSString *)reason {

    if (!img) return;

    if (self.snapshots.count >= 12) {
        [self.snapshots removeObjectAtIndex:0];
        [self log:@"SNAPSHOT QUEUE FULL: OLDEST DROPPED"];
    }

    [self.snapshots addObject:@{
        @"image":img,
        @"reason":reason,
        @"time":@([NSDate date].timeIntervalSince1970)
    }];

    [self processNext];
}

- (void)processNext {
    if (!self.running ||
        self.processing ||
        self.snapshots.count == 0)
        return;

    self.processing = YES;

    NSDictionary *entry = self.snapshots.firstObject;
    [self.snapshots removeObjectAtIndex:0];

    UIImage *img = entry[@"image"];
    NSString *reason = entry[@"reason"];
    NSUInteger gen = self.generation;

    CGFloat x=self.rx,y=self.ry,w=self.rw,h=self.rh;

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED,0), ^{

        @autoreleasepool {
            CGImageRef region =
                [self crop:img.CGImage x:x y:y w:w h:h];

            NSArray *items = [self ocr:region];
            NSString *sym = [self symbol:items];
            NSString *raw = [self raw:items];

            CGImageRef sr =
                [self crop:region
                         x:.52 y:.05 w:.46 h:.90];

            NSData *sig =
                [self pixels:sr width:32 height:24];

            if (sr) CGImageRelease(sr);
            if (region) CGImageRelease(region);

            dispatch_async(dispatch_get_main_queue(), ^{
                if (gen != self.generation ||
                    !self.running) {
                    self.processing = NO;
                    return;
                }

                if (sym.length) {
                    NSData *old = self.symbolImages[sym];
                    double diff =
                        [self difference:old b:sig];

                    BOOL same =
                        [self.lastSymbol isEqualToString:sym];

                    if (!old) {
                        self.counts[sym] =
                            @([self.counts[sym] integerValue]+1);

                        self.symbolImages[sym] = sig;
                        self.lastSymbol = sym;

                        [self log:[NSString stringWithFormat:
                            @"RESULT %@ FIRST %@ COUNTED | %@",
                            reason,sym,raw]];

                    } else if (same) {
                        if (diff >= 0 && diff < .055) {
                            self.duplicates++;

                            [self log:[NSString stringWithFormat:
                                @"RESULT %@ SAME %@ %.4f NOT COUNTED",
                                reason,sym,diff]];
                        } else {
                            self.review++;

                            [self log:[NSString stringWithFormat:
                                @"RESULT %@ %@ CHANGE %.4f REVIEW NOT COUNTED",
                                reason,sym,diff]];
                        }

                    } else {
                        self.counts[sym] =
                            @([self.counts[sym] integerValue]+1);

                        self.symbolImages[sym] = sig;
                        self.lastSymbol = sym;

                        [self log:[NSString stringWithFormat:
                            @"RESULT %@ NEW %@ AFTER DIFFERENT SYMBOL COUNTED | DIFF %.4f",
                            reason,sym,diff]];
                    }

                } else {
                    self.unknown++;

                    [self log:[NSString stringWithFormat:
                        @"RESULT %@ UNKNOWN | %@",
                        reason,raw]];
                }

                self.processing = NO;
                [self refresh];
                [self processNext];
            });
        }
    });
}

#pragma mark - Balance OCR

- (void)readBalance:(UIImage *)img {
    if (self.ocrBusy || !img.CGImage)
        return;

    self.ocrBusy = YES;
    NSUInteger gen = self.generation;

    CGImageRef bal =
        [self crop:img.CGImage
                 x:.39 y:.828 w:.23 h:.036];

    CGImageRef bet =
        [self crop:img.CGImage
                 x:.58 y:.695 w:.20 h:.085];

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED,0), ^{

        @autoreleasepool {
            NSArray *b = [self ocr:bal];
            NSArray *t = [self ocr:bet];

            if (bal) CGImageRelease(bal);
            if (bet) CGImageRelease(bet);

            long long value = -1;
            NSInteger wager = 0;

            for (NSDictionary *d in b) {
                NSString *s = d[@"text"];

                if (![s hasPrefix:@"+"])
                    continue;

                NSString *n = [self digits:s];

                if (n.length < 4 || n.length > 12)
                    continue;

                value = n.longLongValue;

                if (self.trimFive &&
                    n.length == 7 &&
                    [n hasSuffix:@"5"])
                    value /= 10;

                break;
            }

            for (NSDictionary *d in t) {
                NSString *s =
                    [[d[@"text"] uppercaseString]
                        stringByReplacingOccurrencesOfString:@" "
                        withString:@""];

                if ([s hasPrefix:@"X"] ||
                    [s hasPrefix:@"×"] ||
                    [s hasPrefix:@"*"]) {

                    NSString *n =
                        [s substringFromIndex:1];

                    if (n.length &&
                        n.length <= 5 &&
                        [[self digits:n] isEqualToString:n]) {

                        wager = n.integerValue;
                        break;
                    }
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (gen != self.generation)
                    return;

                self.ocrBusy = NO;

                if (self.running)
                    [self applyBalance:value wager:wager];
            });
        }
    });
}

- (void)applyBalance:(long long)value
               wager:(NSInteger)wager {

    if (wager > 0 && wager <= 10000) {
        if (wager == self.betCandidate)
            self.betHits++;
        else {
            self.betCandidate = wager;
            self.betHits = 1;
        }

        if (self.betHits >= 2 && self.bet != wager) {
            self.bet = wager;
            [self log:[NSString stringWithFormat:
                @"BET VERIFIED x%ld",(long)wager]];
        }
    }

    if (value < 0) return;

    if (value == self.balanceCandidate)
        self.balanceHits++;
    else {
        self.balanceCandidate = value;
        self.balanceHits = 1;
    }

    if (self.balanceHits < 2) return;

    if (!self.hasBalance) {
        self.balance = value;
        self.hasBalance = YES;

        [self log:[NSString stringWithFormat:
            @"BALANCE BASELINE %lld",value]];
        return;
    }

    if (value == self.balance) return;

    long long delta = value - self.balance;

    if (llabs(delta) > 100000) {
        [self log:[NSString stringWithFormat:
            @"BALANCE REJECTED %lld",value]];
        return;
    }

    [self log:[NSString stringWithFormat:
        @"BALANCE %lld -> %lld (%+lld)",
        self.balance,value,delta]];

    self.balance = value;

    if (delta < 0 &&
        self.bet > 0 &&
        (-delta)%self.bet == 0) {

        long long spins = (-delta)/self.bet;

        if (spins > 0 && spins <= 100) {
            self.estimatedSpins += spins;
            self.balanceEvents++;

            [self log:[NSString stringWithFormat:
                @"ESTIMATED SPINS +%lld TOTAL %lld | BALANCE-BASED NOT VERIFIED",
                spins,self.estimatedSpins]];
        }
    }

    if (delta > 0) {
        self.positiveBalanceEvents++;
        self.positiveBalanceTotal += delta;

        [self log:[NSString stringWithFormat:
            @"BALANCE CREDIT +%lld | NOT A SPIN",
            delta]];
    }

    if (delta < 0 &&
        (self.bet <= 0 || (-delta)%self.bet != 0))
        [self log:@"BALANCE DEBIT UNCLASSIFIED | NO SPINS ADDED"];

    [self refresh];
}

#pragma mark - Motion detection

- (NSArray<NSData *> *)motionData:(UIImage *)img {
    if (!img.CGImage) return nil;

    const CGFloat r[3][4] = {
        {.43,.30,.14,.10},
        {.34,.28,.12,.12},
        {.56,.28,.12,.12}
    };

    NSMutableArray *a = [NSMutableArray new];

    for (int i=0;i<3;i++) {
        CGImageRef c =
            [self crop:img.CGImage
                     x:r[i][0]
                     y:r[i][1]
                     w:r[i][2]
                     h:r[i][3]];

        NSData *d =
            [self pixels:c width:32 height:24];

        if (c) CGImageRelease(c);
        if (!d) return nil;

        [a addObject:d];
    }

    return a;
}

- (void)tick:(NSTimer *)timer {
    if (!self.running) return;

    NSTimeInterval now =
        [NSDate date].timeIntervalSince1970;

    if (self.lastTick > 0 &&
        now-self.lastTick > 1.0) {

        [self log:[NSString stringWithFormat:
            @"CAPTURE GAP %.2fs | MOTION BASELINE RESET",
            now-self.lastTick]];

        self.previousMotion = nil;
        self.motionActive = NO;
        self.motionQuiet = 0;
        self.lastCandidateTime = now;
    }

    self.lastTick = now;

    UIImage *img = [self capture];
    if (!img) return;

    NSArray *current = [self motionData:img];
    if (!current) return;

    self.frameCount++;
    self.fpsFrames++;

    if (self.lastFpsLog == 0)
        self.lastFpsLog = now;

    if (now-self.lastFpsLog >= 2) {
        self.fps =
            self.fpsFrames/(now-self.lastFpsLog);

        self.fpsFrames = 0;
        self.lastFpsLog = now;

        [self log:[NSString stringWithFormat:
            @"ACTUAL FPS %.1f",self.fps]];
    }

    if (self.previousMotion) {
        double s[3];

        for (int i=0;i<3;i++)
            s[i] = [self difference:
                self.previousMotion[i]
                b:current[i]];

        double peak =
            fmax(s[0],fmax(s[1],s[2]));

        if (peak < .025)
            self.motionQuiet++;
        else
            self.motionQuiet = 0;

        if (self.motionQuiet >= 2 &&
            self.motionActive) {

            self.motionActive = NO;
            self.motionStops++;

            [self log:[NSString stringWithFormat:
                @"MOTION QUIET | STOPS %ld",
                (long)self.motionStops]];
        }

        if (!self.motionActive &&
            peak > .085 &&
            now-self.lastMotionStart > .18) {

            self.motionActive = YES;
            self.motionStarts++;
            self.lastMotionStart = now;

            [self log:[NSString stringWithFormat:
                @"MOTION ONSET #%ld A%.3f B%.3f C%.3f",
                (long)self.motionStarts,
                s[0],s[1],s[2]]];

            if (self.lastCandidateTime == 0 ||
                now-self.lastCandidateTime >= .65) {

                self.spinCandidates++;
                self.lastCandidateTime = now;

                [self log:[NSString stringWithFormat:
                    @"SPIN CANDIDATE #%ld | MOTION-BASED UNVERIFIED",
                    (long)self.spinCandidates]];

            } else {
                self.ignoredOnsets++;

                [self log:[NSString stringWithFormat:
                    @"ONSET SUPPRESSED | %.2fs SINCE CANDIDATE",
                    now-self.lastCandidateTime]];
            }
        }

        if (self.motionQuiet == 2 &&
            now-self.lastResultSnapshotTime > 1.00) {

            self.visualCycles++;
            self.lastVisualCycle = now;
            self.lastResultSnapshotTime = now;

            [self enqueueResult:img
                         reason:[NSString stringWithFormat:
                            @"QUIET-%ld",
                            (long)self.visualCycles]];
        }
    }

    self.previousMotion = current;

    if (now-self.lastBalanceCheck >= .60) {
        self.lastBalanceCheck = now;
        [self readBalance:img];
    }

    if (self.expanded && self.frameCount%10 == 0)
        [self refresh];
}

#pragma mark - Status

- (void)refresh {
    if (!self.expanded || !self.status)
        return;

    self.status.text =
        [NSString stringWithFormat:
            @"V27 %@ | FPS %.1f\n"
             "BALANCE ESTIMATE ~%lld | x%ld\n"
             "CANDIDATES %ld | ONSETS %ld\n"
             "BAL EVENTS %ld | CREDITS %ld\n"
             "RESULT FRAMES %ld | UNKNOWN %ld\n"
             "ATT %@  STEAL %@  SHIELD %@\n"
             "POINT %@  SPINS %@\n"
             "REVIEW %ld | SAME %ld",
            self.running?@"ON":@"OFF",
            self.fps,
            self.estimatedSpins,
            (long)self.bet,
            (long)self.spinCandidates,
            (long)self.motionStarts,
            (long)self.balanceEvents,
            (long)self.positiveBalanceEvents,
            (long)self.visualCycles,
            (long)self.unknown,
            self.counts[@"ATTACK"],
            self.counts[@"STEAL"],
            self.counts[@"SHIELD"],
            self.counts[@"POINT"],
            self.counts[@"SPINS"],
            (long)self.review,
            (long)self.duplicates];
}

#pragma mark - Auto start and stop

- (void)toggle {
    if (self.running) {
        self.running = NO;
        self.generation++;

        [self.timer invalidate];
        self.timer = nil;

        [self.snapshots removeAllObjects];

        self.processing = NO;
        self.ocrBusy = NO;

        [self log:@"AUTO STOPPED V27"];

    } else {
        self.running = YES;
        self.generation++;

        self.motionStarts = 0;
        self.motionStops = 0;
        self.spinCandidates = 0;
        self.ignoredOnsets = 0;
        self.lastCandidateTime = 0;

        self.motionActive = NO;
        self.motionQuiet = 0;

        self.visualCycles = 0;
        self.unknown = 0;
        self.review = 0;
        self.duplicates = 0;

        self.estimatedSpins = 0;
        self.balanceEvents = 0;
        self.positiveBalanceEvents = 0;
        self.positiveBalanceTotal = 0;

        self.lastResultSnapshotTime = 0;

        self.bet = 0;
        self.betHits = 0;
        self.balanceHits = 0;
        self.hasBalance = NO;

        self.frameCount = 0;
        self.fpsFrames = 0;
        self.fps = 0;

        self.lastTick = 0;
        self.lastMotionStart = 0;
        self.lastVisualCycle = 0;
        self.lastBalanceCheck = 0;
        self.lastFpsLog = 0;

        self.previousMotion = nil;
        self.lastSymbol = @"";

        self.processing = NO;
        self.ocrBusy = NO;

        [self.snapshots removeAllObjects];
        [self.symbolImages removeAllObjects];

        for (NSString *k in self.counts.allKeys)
            self.counts[k] = @0;

        self.timer =
            [NSTimer scheduledTimerWithTimeInterval:.05
                                             target:self
                                           selector:@selector(tick:)
                                           userInfo:nil
                                            repeats:YES];

        [self log:
            @"AUTO STARTED V27 | BALANCE PRIMARY ESTIMATE + MOTION DIAGNOSTICS"];

        [self log:
            @"SPIN CANDIDATES ARE NOT CONFIRMED SPINS"];

        [self log:
            @"BALANCE ESTIMATE IS NOT CONFIRMED SPINS"];
    }

    [self refresh];
    [self updateBubble];
}

#pragma mark - Existing controls

- (void)copyLog {
    [self log:@"LOG COPIED"];

    UIPasteboard.generalPasteboard.string =
        [self.logs componentsJoinedByString:@"\n"];
}

- (void)moveROI:(CGFloat)dx dy:(CGFloat)dy {
    self.rx =
        fmax(0,fmin(1-self.rw,self.rx+dx));

    self.ry =
        fmax(0,fmin(1-self.rh,self.ry+dy));

    [self markerUpdate];

    [self log:[NSString stringWithFormat:
        @"ROI x=%.3f y=%.3f",
        self.rx,self.ry]];
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
    [self markerUpdate];

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

    [self log:@"BALANCE RESET"];
}

- (void)button:(NSString *)s
             x:(CGFloat)x
             y:(CGFloat)y
             w:(CGFloat)w
        action:(SEL)sel
          view:(UIView *)v {

    UIButton *b =
        [UIButton buttonWithType:UIButtonTypeSystem];

    b.frame = CGRectMake(x,y,w,29);

    [b setTitle:s forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor
           forState:UIControlStateNormal];

    b.backgroundColor =
        [UIColor colorWithWhite:.23 alpha:1];

    b.layer.cornerRadius = 6;
    b.titleLabel.font =
        [UIFont boldSystemFontOfSize:10];

    [b addTarget:self
          action:sel
forControlEvents:UIControlEventTouchUpInside];

    [v addSubview:b];
}

#pragma mark - Small transparent icon

- (void)updateBubble {
    if (!self.bubbleButton)
        return;

    [self.bubbleButton setTitle:
        self.running ? @"◉" : @"○"
        forState:UIControlStateNormal];

    self.bubbleButton.accessibilityLabel =
        self.running
            ? @"Logger aktiv. Öppna panel"
            : @"Logger stoppad. Öppna panel";

    self.bubble.layer.borderColor =
        (self.running
            ? UIColor.systemGreenColor
            : UIColor.systemOrangeColor).CGColor;
}

- (void)expandLogger {
    self.expanded = YES;

    self.bubble.hidden = YES;
    self.expandedView.hidden = NO;

    self.overlay.activeArea = self.expandedView;

    self.logView.text =
        [self.logs componentsJoinedByString:@"\n"];

    [self refresh];
}

- (void)minimizeLogger {
    self.expanded = NO;

    self.expandedView.hidden = YES;
    self.bubble.hidden = NO;

    self.overlay.activeArea = self.bubble;

    [self updateBubble];
}

#pragma mark - Dragging

- (void)dragBubble:(UIPanGestureRecognizer *)g {
    CGPoint delta =
        [g translationInView:
            self.overlay.rootViewController.view];

    CGRect f = self.bubble.frame;

    CGSize s =
        self.overlay.rootViewController.view.bounds.size;

    f.origin.x = MAX(0,
        MIN(s.width-f.size.width,
            f.origin.x+delta.x));

    f.origin.y = MAX(0,
        MIN(s.height-f.size.height,
            f.origin.y+delta.y));

    self.bubble.frame = f;

    [g setTranslation:CGPointZero
              inView:self.overlay.rootViewController.view];
}

- (void)movePanel:(UIPanGestureRecognizer *)g {
    CGPoint delta =
        [g translationInView:
            self.overlay.rootViewController.view];

    CGRect f = self.expandedView.frame;

    CGSize s =
        self.overlay.rootViewController.view.bounds.size;

    f.origin.x = MAX(0,
        MIN(s.width-f.size.width,
            f.origin.x+delta.x));

    f.origin.y = MAX(0,
        MIN(s.height-f.size.height,
            f.origin.y+delta.y));

    self.expandedView.frame = f;

    [g setTranslation:CGPointZero
              inView:self.overlay.rootViewController.view];
}

#pragma mark - Full panel

- (void)showPanel {
    if (self.overlay)
        return;

    UIWindowScene *scene = nil;

    for (UIScene *s in
         UIApplication.sharedApplication.connectedScenes) {

        if ([s isKindOfClass:UIWindowScene.class] &&
            s.activationState ==
                UISceneActivationStateForegroundActive) {

            scene = (UIWindowScene *)s;
            break;
        }
    }

    if (!scene) {
        dispatch_after(
            dispatch_time(
                DISPATCH_TIME_NOW,NSEC_PER_SEC),
            dispatch_get_main_queue(), ^{

                [self showPanel];
            });

        return;
    }

    self.overlay =
        [[CMSLoggerWindow alloc]
            initWithWindowScene:scene];

    self.overlay.frame =
        scene.coordinateSpace.bounds;

    self.overlay.windowLevel =
        UIWindowLevelAlert+1;

    UIViewController *vc =
        [UIViewController new];

    vc.view.backgroundColor =
        UIColor.clearColor;

    self.overlay.rootViewController = vc;

    CGFloat width =
        MIN(340,vc.view.bounds.size.width-20);

    // Small 44x44 icon.

    self.bubble =
        [[UIView alloc]
            initWithFrame:CGRectMake(
                vc.view.bounds.size.width-56,
                105,44,44)];

    self.bubble.backgroundColor =
        [UIColor colorWithRed:.04
                       green:.10
                        blue:.15
                       alpha:.38];

    self.bubble.layer.cornerRadius = 22;
    self.bubble.layer.borderWidth = 1.5;

    self.bubbleButton =
        [UIButton buttonWithType:UIButtonTypeSystem];

    self.bubbleButton.frame =
        self.bubble.bounds;

    self.bubbleButton.titleLabel.font =
        [UIFont boldSystemFontOfSize:29];

    [self.bubbleButton
        setTitleColor:UIColor.systemGreenColor
        forState:UIControlStateNormal];

    [self.bubbleButton
        addTarget:self
        action:@selector(expandLogger)
        forControlEvents:UIControlEventTouchUpInside];

    [self.bubble addSubview:self.bubbleButton];

    [self.bubble addGestureRecognizer:
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
            action:@selector(dragBubble:)]];

    [vc.view addSubview:self.bubble];

    // Expanded 410-point panel.

    self.expandedView =
        [[UIView alloc]
            initWithFrame:CGRectMake(
                10,65,width,410)];

    self.expandedView.backgroundColor =
        [UIColor colorWithRed:.06
                       green:.08
                        blue:.12
                       alpha:.96];

    self.expandedView.layer.cornerRadius = 12;
    self.expandedView.clipsToBounds = YES;

    [vc.view addSubview:self.expandedView];

    UILabel *title =
        [[UILabel alloc]
            initWithFrame:CGRectMake(
                10,5,width-112,26)];

    title.text = @"CMSCrystalLogger v27";
    title.textColor = UIColor.whiteColor;

    title.font =
        [UIFont boldSystemFontOfSize:15];

    title.userInteractionEnabled = YES;

    [title addGestureRecognizer:
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
            action:@selector(movePanel:)]];

    [self.expandedView addSubview:title];

    [self button:@"MINIMERA"
               x:width-100
               y:5
               w:94
          action:@selector(minimizeLogger)
            view:self.expandedView];

    self.status =
        [[UILabel alloc]
            initWithFrame:CGRectMake(
                10,32,width-20,126)];

    self.status.numberOfLines = 8;
    self.status.textColor =
        UIColor.systemGreenColor;

    self.status.font =
        [UIFont monospacedSystemFontOfSize:10
                                   weight:UIFontWeightMedium];

    self.status.adjustsFontSizeToFitWidth = YES;
    self.status.minimumScaleFactor = .7;

    [self.expandedView addSubview:self.status];

    self.logView =
        [[UITextView alloc]
            initWithFrame:CGRectMake(
                8,160,width-16,110)];

    self.logView.backgroundColor =
        UIColor.clearColor;

    self.logView.textColor =
        UIColor.systemGreenColor;

    self.logView.font =
        [UIFont monospacedSystemFontOfSize:9
                                   weight:UIFontWeightRegular];

    self.logView.editable = NO;

    [self.expandedView addSubview:self.logView];

    CGFloat bw = (width-30)/3;

    [self button:@"AUTO"
               x:5 y:276 w:bw
          action:@selector(toggle)
            view:self.expandedView];

    [self button:@"COPY LOG"
               x:10+bw y:276 w:bw
          action:@selector(copyLog)
            view:self.expandedView];

    [self button:@"ROI SHOW"
               x:15+2*bw y:276 w:bw
          action:@selector(toggleMarker)
            view:self.expandedView];

    [self button:@"LEFT"
               x:5 y:311 w:bw
          action:@selector(left)
            view:self.expandedView];

    [self button:@"UP"
               x:10+bw y:311 w:bw
          action:@selector(up)
            view:self.expandedView];

    [self button:@"RIGHT"
               x:15+2*bw y:311 w:bw
          action:@selector(right)
            view:self.expandedView];

    [self button:@"TRIM5"
               x:5 y:346 w:bw
          action:@selector(toggleTrim)
            view:self.expandedView];

    [self button:@"DOWN"
               x:10+bw y:346 w:bw
          action:@selector(down)
            view:self.expandedView];

    [self button:@"RESET BAL"
               x:15+2*bw y:346 w:bw
          action:@selector(resetBalance)
            view:self.expandedView];

    // Show the icon first, not the large panel.

    self.panel = self.overlay;
    self.overlay.hidden = NO;
    self.expanded = YES;

    [self minimizeLogger];
    [self markerUpdate];

    [self log:@"V27 READY | MINIMIZED BY DEFAULT"];

    // Automatically start Logger.
    if (!self.running)
        [self toggle];
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showPanel];
    });
}

@end

#pragma mark - Automatic initialization

__attribute__((constructor))
static void CMSCrystalInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[CMSCrystalLogger shared] start];
    });
}

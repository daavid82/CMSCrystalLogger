
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <math.h>

@interface CMSLogger : NSObject
@property(nonatomic,strong) UIWindow *panel;
@property(nonatomic,strong) UITextView *logView;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UILabel *result;
@property(nonatomic,strong) UILabel *areaLabel;
@property(nonatomic,strong) UIView *areaOverlay;
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,strong) NSTimer *timer;

@property(nonatomic,assign) BOOL running;
@property(nonatomic,assign) BOOL busy;
@property(nonatomic,assign) NSInteger attempts;
@property(nonatomic,assign) NSInteger scans;
@property(nonatomic,assign) NSInteger candidates;
@property(nonatomic,assign) NSInteger stableCount;
@property(nonatomic,assign) NSInteger motionCount;

@property(nonatomic,copy) NSString *lastLabel;
@property(nonatomic,copy) NSString *lastLogged;
@property(nonatomic,assign) CGFloat topPosition;
@property(nonatomic,assign) CGFloat regionHeight;
@property(nonatomic,assign) uint64_t previousHash;
@property(nonatomic,assign) BOOL hasHash;
@property(nonatomic,assign) BOOL armed;
@property(nonatomic,assign) BOOL hasResult;

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
        instance.topPosition = 0.24;
        instance.regionHeight = 0.16;
        instance.lastLabel = @"";
        instance.lastLogged = @"";
        instance.armed = YES;
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

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"HH:mm:ss";

    NSString *line = [NSString stringWithFormat:
        @"%@ %@",
        [formatter stringFromDate:[NSDate date]],
        message];

    [self.events addObject:line];
    if (self.events.count > 300)
        [self.events removeObjectAtIndex:0];

    NSString *all =
        [self.events componentsJoinedByString:@"\n"];

    self.logView.text = all;

    if (all.length)
        [self.logView scrollRangeToVisible:
            NSMakeRange(all.length - 1, 1)];

    [all writeToFile:
        [NSTemporaryDirectory()
            stringByAppendingPathComponent:@"CMSCrystalV11.log"]
        atomically:YES
        encoding:NSUTF8StringEncoding
        error:nil];

    NSLog(@"[CMSCrystal] %@", line);
}

- (void)refresh {
    self.status.text = [NSString stringWithFormat:
        @"AUTO %@ | SCANS %ld | EVENTS %ld",
        self.running ? @"ON" : @"OFF",
        (long)self.scans,
        (long)self.candidates];

    self.status.textColor =
        self.running ? UIColor.systemGreenColor :
                       UIColor.systemOrangeColor;

    self.areaLabel.text = [NSString stringWithFormat:
        @"TOP %.0f%% | HEIGHT %.0f%%",
        self.topPosition * 100,
        self.regionHeight * 100];
}

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

    CGSize size = window.bounds.size;
    if (size.width <= 0 || size.height <= 0)
        return nil;

    UIGraphicsImageRendererFormat *format =
        [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.opaque = YES;

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc]
            initWithSize:size format:format];

    return [renderer imageWithActions:
        ^(UIGraphicsImageRendererContext *context) {
            [window drawViewHierarchyInRect:
                CGRectMake(0, 0, size.width, size.height)
                afterScreenUpdates:NO];
        }];
}

- (CGRect)scanRectForSize:(CGSize)size {
    CGFloat y = size.height * self.topPosition;
    CGFloat h = size.height * self.regionHeight;

    // Middle 76% of the screen width.
    return CGRectMake(
        size.width * 0.12,
        y,
        size.width * 0.76,
        MIN(h, size.height - y));
}

- (uint64_t)hashImage:(CGImageRef)image {
    uint8_t pixels[16 * 16 * 4] = {0};

    CGColorSpaceRef cs =
        CGColorSpaceCreateDeviceRGB();

    CGContextRef ctx = CGBitmapContextCreate(
        pixels, 16, 16, 8, 16 * 4, cs,
        kCGImageAlphaPremultipliedLast |
        kCGBitmapByteOrder32Big);

    CGColorSpaceRelease(cs);
    if (!ctx) return 0;

    CGContextDrawImage(
        ctx, CGRectMake(0, 0, 16, 16), image);
    CGContextRelease(ctx);

    uint64_t hash = 1469598103934665603ULL;

    for (size_t i = 0; i < sizeof(pixels); i++) {
        // Quantize to reduce tiny pixel changes.
        hash ^= (pixels[i] >> 4);
        hash *= 1099511628211ULL;
    }
    return hash;
}

- (NSString *)classify:(NSString *)text {
    NSString *s = text.uppercaseString;

    if ([s containsString:@"ATTACK"]) return @"ATTACK";
    if ([s containsString:@"POINT"]) return @"POINT";
    if ([s containsString:@"STEAL"]) return @"STEAL";
    if ([s containsString:@"SHIELD"]) return @"SHIELD";
    if ([s containsString:@"SPINS"]) return @"SPINS";

    return nil;
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
    size_t w = CGImageGetWidth(original);
    size_t h = CGImageGetHeight(original);

    CGRect rect = [self scanRectForSize:
        CGSizeMake(w, h)];

    CGImageRef cropped =
        CGImageCreateWithImageInRect(original, rect);

    if (!cropped) {
        self.busy = NO;
        [self log:@"CROP FAILED"];
        return;
    }

    uint64_t hash = [self hashImage:cropped];

    BOOL changed =
        self.hasHash && hash != self.previousHash;

    self.previousHash = hash;
    self.hasHash = YES;

    if (changed) self.motionCount++;
    else self.motionCount = 0;

    // A visual change alone is not proof
    // that another spin has started.
    // Log candidates only, never count wins.
    VNRecognizeTextRequest *request =
        [VNRecognizeTextRequest new];

    request.recognitionLevel =
        VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = NO;
    request.recognitionLanguages = @[@"en-US"];

    CGImageRef retained = cropped;

    dispatch_async(
        dispatch_get_global_queue(
            QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSError *error = nil;

            VNImageRequestHandler *handler =
                [[VNImageRequestHandler alloc]
                    initWithCGImage:retained
                           options:@{}];

            BOOL ok =
                [handler performRequests:@[request]
                                   error:&error];

            NSMutableDictionary *found =
                [NSMutableDictionary new];

            if (ok) {
                for (VNRecognizedTextObservation *obs
                     in request.results) {

                    VNRecognizedText *text =
                        [[obs topCandidates:1] firstObject];
                    if (!text) continue;

                    NSString *label =
                        [self classify:text.string];
                    if (!label) continue;

                    NSNumber *previous = found[label];
                    if (!previous ||
                        text.confidence > previous.floatValue)
                        found[label] = @(text.confidence);
                }
            }

            CGImageRelease(retained);

            dispatch_async(dispatch_get_main_queue(), ^{
                self.busy = NO;
                [self refresh];

                if (!ok) {
                    [self log:[NSString stringWithFormat:
                        @"OCR ERROR: %@",
                        error.localizedDescription ?: @"UNKNOWN"]];
                    return;
                }

                NSArray *labels = found.allKeys;

                if (labels.count != 1) {
                    self.stableCount = 0;
                    self.lastLabel = @"";

                    if (labels.count > 1 &&
                        self.scans % 5 == 0) {
                        [self log:[NSString stringWithFormat:
                            @"TOP MULTIPLE: %@",
                            [labels componentsJoinedByString:@","]]];
                    }
                    return;
                }

                NSString *label = labels.firstObject;
                float confidence =
                    [found[label] floatValue];

                if (confidence < 0.70) {
                    self.stableCount = 0;
                    return;
                }

                if ([label isEqualToString:self.lastLabel])
                    self.stableCount++;
                else {
                    self.lastLabel = label;
                    self.stableCount = 1;
                }

                self.result.text =
                    [NSString stringWithFormat:
                        @"TOP: %@ (%.2f) | STABLE %ld",
                        label, confidence,
                        (long)self.stableCount];

                if (self.stableCount == 2 &&
                    ![self.lastLogged isEqualToString:label]) {

                    self.candidates++;
                    self.lastLogged = label;

                    [self log:[NSString stringWithFormat:
                        @"POSSIBLE TOP RESULT: %@",
                        label]];
                }

                if (self.scans % 15 == 0) {
                    [self log:[NSString stringWithFormat:
                        @"SCAN STATUS: %@ / motion=%ld",
                        label, (long)self.motionCount]];
                }
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
        self.stableCount = 0;
        self.lastLabel = @"";
        self.lastLogged = @"";
        self.hasHash = NO;

        self.timer =
            [NSTimer scheduledTimerWithTimeInterval:0.5
                                             target:self
                                           selector:@selector(tick:)
                                           userInfo:nil
                                            repeats:YES];

        [self log:@"AUTO STARTED"];
        [self scan];
    }
    [self refresh];
}

- (void)moveAreaUp {
    self.topPosition =
        MAX(0.02, self.topPosition - 0.02);
    [self refresh];
    [self log:@"SCAN AREA MOVED UP"];
}

- (void)moveAreaDown {
    self.topPosition =
        MIN(0.80, self.topPosition + 0.02);
    [self refresh];
    [self log:@"SCAN AREA MOVED DOWN"];
}

- (void)showArea {
    UIWindow *game = [self gameWindow];
    if (!game) {
        [self log:@"NO GAME WINDOW"];
        return;
    }

    if (self.areaOverlay) {
        [self.areaOverlay removeFromSuperview];
        self.areaOverlay = nil;
        [self log:@"AREA HIDDEN"];
        return;
    }

    CGRect rect =
        [self scanRectForSize:game.bounds.size];

    UIView *overlay =
        [[UIView alloc] initWithFrame:rect];

    overlay.backgroundColor =
        [UIColor colorWithRed:0 green:1 blue:0 alpha:0.15];

    overlay.layer.borderColor =
        UIColor.systemGreenColor.CGColor;
    overlay.layer.borderWidth = 2;
    overlay.userInteractionEnabled = NO;

    [game addSubview:overlay];
    self.areaOverlay = overlay;

    [self log:@"GREEN SCAN AREA VISIBLE"];
}

- (void)copyLog {
    UIPasteboard.generalPasteboard.string =
        [self.events componentsJoinedByString:@"\n"];
    [self log:@"LOG COPIED"];
}

- (void)movePanel:(UIPanGestureRecognizer *)gesture {
    CGPoint p = [gesture translationInView:self.panel];
    CGRect f = self.panel.frame;
    f.origin.x += p.x;
    f.origin.y += p.y;
    self.panel.frame = f;
    [gesture setTranslation:CGPointZero
                    inView:self.panel];
}

- (UIButton *)button:(NSString *)text
                frame:(CGRect)frame
               action:(SEL)action
               parent:(UIView *)parent {
    UIButton *button =
        [UIButton buttonWithType:UIButtonTypeSystem];

    button.frame = frame;
    [button setTitle:text forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor
                forState:UIControlStateNormal];

    button.backgroundColor =
        [UIColor colorWithWhite:0.22 alpha:1];
    button.titleLabel.font =
        [UIFont boldSystemFontOfSize:11];
    button.layer.cornerRadius = 8;

    [button addTarget:self action:action
     forControlEvents:UIControlEventTouchUpInside];

    [parent addSubview:button];
    return button;
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
        MIN(350, scene.coordinateSpace.bounds.size.width - 24);

    self.panel =
        [[UIWindow alloc] initWithWindowScene:scene];
    self.panel.frame = CGRectMake(12, 70, width, 355);
    self.panel.windowLevel = UIWindowLevelAlert + 1;

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor =
        [UIColor colorWithRed:0.06 green:0.08
                        blue:0.12 alpha:0.96];
    vc.view.layer.cornerRadius = 12;
    vc.view.clipsToBounds = YES;

    self.panel.rootViewController = vc;

    UILabel *title =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 8, width - 24, 28)];

    title.text = @"CMSCrystalLogger v11 TOP TRACKER";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:14];
    title.userInteractionEnabled = YES;

    [title addGestureRecognizer:
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(movePanel:)]];

    [vc.view addSubview:title];

    self.status =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 40, width - 24, 22)];
    self.status.font = [UIFont systemFontOfSize:12];
    [vc.view addSubview:self.status];

    self.result =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 65, width - 24, 24)];
    self.result.text = @"TOP: WAITING";
    self.result.textColor = UIColor.systemYellowColor;
    self.result.font = [UIFont systemFontOfSize:12];
    [vc.view addSubview:self.result];

    self.areaLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 92, width - 24, 22)];
    self.areaLabel.textColor = UIColor.whiteColor;
    self.areaLabel.font = [UIFont systemFontOfSize:11];
    [vc.view addSubview:self.areaLabel];

    self.logView =
        [[UITextView alloc] initWithFrame:
            CGRectMake(10, 120, width - 20, 135)];
    self.logView.backgroundColor = UIColor.clearColor;
    self.logView.textColor = UIColor.systemGreenColor;
    self.logView.font =
        [UIFont monospacedSystemFontOfSize:10
                                   weight:UIFontWeightRegular];
    self.logView.editable = NO;
    self.logView.text =
        [self.events componentsJoinedByString:@"\n"];
    [vc.view addSubview:self.logView];

    CGFloat gap = 6;
    CGFloat bw = (width - 36 - gap * 2) / 3;

    [self button:@"AUTO ON/OFF"
          frame:CGRectMake(12, 265, bw, 35)
         action:@selector(toggle) parent:vc.view];

    [self button:@"SHOW AREA"
          frame:CGRectMake(18+bw, 265, bw, 35)
         action:@selector(showArea) parent:vc.view];

    [self button:@"COPY LOG"
          frame:CGRectMake(24+2*bw, 265, bw, 35)
         action:@selector(copyLog) parent:vc.view];

    [self button:@"AREA UP"
          frame:CGRectMake(12, 307, (width-30)/2, 35)
         action:@selector(moveAreaUp) parent:vc.view];

    [self button:@"AREA DOWN"
          frame:CGRectMake(18+(width-30)/2, 307,
                           (width-30)/2, 35)
         action:@selector(moveAreaDown) parent:vc.view];

    self.panel.hidden = NO;
    [self.panel makeKeyAndVisible];

    [self refresh];
    [self log:@"V11 READY - TOP OCR"];
    [self log:@"CANDIDATES ONLY - NO AUTO COUNTS"];
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

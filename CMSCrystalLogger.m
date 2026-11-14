
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <mach-o/dyld.h>

@interface CMSLogger : NSObject

@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UITextView *logView;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UILabel *countLabel;
@property(nonatomic,strong) UILabel *resultLabel;
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) UIImage *lastImage;

@property(nonatomic,assign) BOOL autoScan;
@property(nonatomic,assign) BOOL processing;
@property(nonatomic,assign) NSInteger scans;
@property(nonatomic,assign) NSInteger attempts;
@property(nonatomic,copy) NSString *lastCandidate;
@property(nonatomic,assign) NSInteger repeatedCandidate;

@property(nonatomic,assign) NSInteger spins;
@property(nonatomic,assign) NSInteger attacks;
@property(nonatomic,assign) NSInteger points;
@property(nonatomic,assign) NSInteger steals;
@property(nonatomic,assign) NSInteger shields;
@property(nonatomic,assign) NSInteger spinResults;
@property(nonatomic,assign) NSInteger raidStack;

+ (instancetype)shared;
- (void)start;

@end

@implementation CMSLogger

+ (instancetype)shared {
    static CMSLogger *obj;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        obj = [CMSLogger new];
        obj.events = [NSMutableArray new];
        obj.lastCandidate = @"";
    });
    return obj;
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
        @"%@ %@", [fmt stringFromDate:[NSDate date]],
        message];

    [self.events addObject:line];

    if (self.events.count > 250) {
        [self.events removeObjectAtIndex:0];
    }

    NSString *all =
        [self.events componentsJoinedByString:@"\n"];

    self.logView.text = all;

    if (all.length) {
        [self.logView scrollRangeToVisible:
            NSMakeRange(all.length - 1, 1)];
    }

    [all writeToFile:
        [NSTemporaryDirectory()
            stringByAppendingPathComponent:@"CMSLoggerV10.log"]
        atomically:YES
        encoding:NSUTF8StringEncoding
        error:nil];

    NSLog(@"[CMSLogger] %@", line);
}

- (void)refresh {
    self.statusLabel.text = [NSString stringWithFormat:
        @"AUTO %@  |  SCANS %ld",
        self.autoScan ? @"ON" : @"OFF",
        (long)self.scans];

    self.statusLabel.textColor =
        self.autoScan ? UIColor.systemGreenColor :
                        UIColor.systemOrangeColor;

    self.countLabel.text = [NSString stringWithFormat:
        @"MANUAL SPINS %ld  |  RAID STACK %ld",
        (long)self.spins, (long)self.raidStack];
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self log:@"CMSCRYSTALLOGGER V10"];
        [self log:@"VISION OCR TRACKER"];
        [self log:@"NO DOBBY / NO HOOKS"];
        [self showPanel];
    });
}

- (UIWindow *)gameWindow {
    UIWindow *best = nil;

    for (UIScene *s in
         UIApplication.sharedApplication.connectedScenes) {

        if (![s isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *scene = (UIWindowScene *)s;

        for (UIWindow *w in scene.windows) {
            if (w == self.window || w.hidden) continue;
            if (w.bounds.size.width < 100) continue;
            if (w.bounds.size.height < 100) continue;

            if (!best || w.windowLevel < best.windowLevel) {
                best = w;
            }
        }
    }
    return best;
}

- (UIImage *)capture {
    UIWindow *w = [self gameWindow];
    if (!w) return nil;

    CGSize size = w.bounds.size;
    if (size.width <= 0 || size.height <= 0) {
        return nil;
    }

    UIGraphicsImageRendererFormat *format =
        [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1.0;
    format.opaque = YES;

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc]
            initWithSize:size format:format];

    return [renderer imageWithActions:
        ^(UIGraphicsImageRendererContext *ctx) {
            [w drawViewHierarchyInRect:
                CGRectMake(0, 0, size.width, size.height)
                afterScreenUpdates:NO];
        }];
}

- (NSString *)categoryForText:(NSString *)raw {
    NSString *s = raw.uppercaseString;

    if ([s containsString:@"ATTACK"]) return @"ATTACK";
    if ([s containsString:@"POINT"]) return @"POINT";
    if ([s containsString:@"STEAL"]) return @"STEAL";
    if ([s containsString:@"SHIELD"]) return @"SHIELD";
    if ([s containsString:@"SPINS"]) return @"SPINS";

    return nil;
}

- (void)scan {
    if (self.processing) return;
    self.processing = YES;

    UIImage *image = [self capture];

    if (!image || !image.CGImage) {
        self.processing = NO;
        [self log:@"CAPTURE FAILED"];
        return;
    }

    self.lastImage = image;
    self.scans++;
    [self refresh];

    CGImageRef cg = CGImageRetain(image.CGImage);

    dispatch_async(
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
        ^{
        @autoreleasepool {
            VNRecognizeTextRequest *request =
                [VNRecognizeTextRequest new];

            request.recognitionLevel =
                VNRequestTextRecognitionLevelAccurate;
            request.usesLanguageCorrection = NO;
            request.recognitionLanguages = @[@"en-US"];

            NSError *error = nil;

            VNImageRequestHandler *handler =
                [[VNImageRequestHandler alloc]
                    initWithCGImage:cg options:@{}];

            BOOL success =
                [handler performRequests:@[request]
                                   error:&error];

            NSMutableDictionary<NSString *, NSNumber *> *found =
                [NSMutableDictionary new];

            NSMutableArray<NSString *> *rawTexts =
                [NSMutableArray new];

            if (success) {
                for (VNRecognizedTextObservation *obs
                     in request.results) {

                    VNRecognizedText *text =
                        [[obs topCandidates:1] firstObject];

                    if (!text) continue;

                    NSString *raw = text.string;
                    if (!raw.length) continue;

                    if (rawTexts.count < 20) {
                        [rawTexts addObject:raw];
                    }

                    NSString *category =
                        [self categoryForText:raw];

                    if (!category) continue;

                    NSNumber *old = found[category];

                    if (!old ||
                        text.confidence > old.floatValue) {
                        found[category] =
                            @(text.confidence);
                    }
                }
            }

            CGImageRelease(cg);

            dispatch_async(dispatch_get_main_queue(), ^{
                self.processing = NO;

                if (!success) {
                    [self log:[NSString stringWithFormat:
                        @"OCR ERROR: %@",
                        error.localizedDescription ?: @"UNKNOWN"]];
                    return;
                }

                NSArray *categories =
                    [[found allKeys] sortedArrayUsingSelector:
                        @selector(compare:)];

                if (categories.count == 0) {
                    self.lastCandidate = @"";
                    self.repeatedCandidate = 0;
                    self.resultLabel.text = @"OCR: UNKNOWN";

                    if (self.scans % 10 == 0) {
                        [self log:[NSString stringWithFormat:
                            @"OCR RAW: %@",
                            [rawTexts componentsJoinedByString:@" | "]]];
                    }
                    return;
                }

                NSMutableArray *parts =
                    [NSMutableArray new];

                for (NSString *category in categories) {
                    [parts addObject:[NSString stringWithFormat:
                        @"%@ %.2f",
                        category,
                        found[category].floatValue]];
                }

                NSString *summary =
                    [parts componentsJoinedByString:@" | "];

                self.resultLabel.text =
                    [NSString stringWithFormat:
                        @"OCR: %@", summary];

                // Multiple result words can be visible on
                // the wheel. They are NOT confirmed events.
                if (categories.count != 1) {
                    self.lastCandidate = @"";
                    self.repeatedCandidate = 0;

                    if (self.scans % 5 == 0) {
                        [self log:[NSString stringWithFormat:
                            @"MULTIPLE LABELS: %@", summary]];
                    }
                    return;
                }

                NSString *candidate = categories.firstObject;
                float confidence =
                    found[candidate].floatValue;

                if (confidence < 0.65f) {
                    self.lastCandidate = @"";
                    self.repeatedCandidate = 0;
                    return;
                }

                if ([candidate isEqualToString:
                     self.lastCandidate]) {
                    self.repeatedCandidate++;
                } else {
                    self.lastCandidate = candidate;
                    self.repeatedCandidate = 1;
                    [self log:[NSString stringWithFormat:
                        @"OCR CANDIDATE: %@ (%.2f)",
                        candidate, confidence]];
                }

                if (self.repeatedCandidate == 2) {
                    [self log:[NSString stringWithFormat:
                        @"STABLE TEXT: %@ - NOT CONFIRMED RESULT",
                        candidate]];
                }
            });
        }
    });
}

- (void)tick:(NSTimer *)timer {
    if (self.autoScan) [self scan];
}

- (void)toggleScan {
    if (self.autoScan) {
        self.autoScan = NO;
        [self.timer invalidate];
        self.timer = nil;
        [self log:@"AUTO SCAN STOPPED"];
    } else {
        self.autoScan = YES;
        self.scans = 0;
        self.lastCandidate = @"";
        self.repeatedCandidate = 0;

        self.timer =
            [NSTimer scheduledTimerWithTimeInterval:1.0
                                             target:self
                                           selector:@selector(tick:)
                                           userInfo:nil
                                            repeats:YES];

        [self log:@"AUTO SCAN STARTED"];
        [self scan];
    }
    [self refresh];
}

- (void)manualSpin {
    self.spins++;
    [self refresh];
    [self log:@"MANUAL SPIN +1"];
}

- (void)stackPlus {
    self.raidStack++;
    [self refresh];
    [self log:@"MANUAL STACK +1"];
}

- (void)stackMinus {
    if (self.raidStack > 0) self.raidStack--;
    [self refresh];
    [self log:@"MANUAL STACK -1"];
}

- (void)copyLog {
    UIPasteboard.generalPasteboard.string =
        [self.events componentsJoinedByString:@"\n"];
    [self log:@"LOG COPIED"];
}

- (void)reset {
    self.spins = 0;
    self.attacks = 0;
    self.points = 0;
    self.steals = 0;
    self.shields = 0;
    self.spinResults = 0;
    self.raidStack = 0;
    [self refresh];
    [self log:@"MANUAL COUNTERS RESET"];
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

    b.titleLabel.font =
        [UIFont boldSystemFontOfSize:12];

    b.backgroundColor =
        [UIColor colorWithWhite:0.22 alpha:1];

    b.layer.cornerRadius = 8;

    [b addTarget:self action:action
     forControlEvents:UIControlEventTouchUpInside];

    [parent addSubview:b];
    return b;
}

- (void)move:(UIPanGestureRecognizer *)pan {
    CGPoint p = [pan translationInView:self.window];
    CGRect f = self.window.frame;
    f.origin.x += p.x;
    f.origin.y += p.y;
    self.window.frame = f;
    [pan setTranslation:CGPointZero inView:self.window];
}

- (void)showPanel {
    if (self.window) return;

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
        if (++self.attempts < 60) {
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                dispatch_get_main_queue(), ^{
                    [self showPanel];
                });
        }
        return;
    }

    CGFloat width =
        MIN(350, scene.coordinateSpace.bounds.size.width - 24);

    self.window =
        [[UIWindow alloc] initWithWindowScene:scene];

    self.window.frame =
        CGRectMake(12, 70, width, 345);

    self.window.windowLevel = UIWindowLevelAlert + 1;

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor =
        [UIColor colorWithRed:0.06 green:0.08
                        blue:0.12 alpha:0.95];

    vc.view.layer.cornerRadius = 12;
    vc.view.clipsToBounds = YES;
    self.window.rootViewController = vc;

    UILabel *title =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 8, width - 24, 28)];

    title.text = @"CMSCrystalLogger v10 OCR";
    title.textColor = UIColor.whiteColor;
    title.font =
        [UIFont boldSystemFontOfSize:16];
    title.userInteractionEnabled = YES;

    [title addGestureRecognizer:
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(move:)]];

    [vc.view addSubview:title];

    self.statusLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 40, width - 24, 22)];

    self.statusLabel.font =
        [UIFont monospacedSystemFontOfSize:11
                                   weight:UIFontWeightBold];
    [vc.view addSubview:self.statusLabel];

    self.countLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 64, width - 24, 22)];

    self.countLabel.textColor = UIColor.whiteColor;
    self.countLabel.font =
        [UIFont systemFontOfSize:12];
    [vc.view addSubview:self.countLabel];

    self.resultLabel =
        [[UILabel alloc] initWithFrame:
            CGRectMake(12, 88, width - 24, 35)];

    self.resultLabel.text = @"OCR: WAITING";
    self.resultLabel.textColor =
        UIColor.systemYellowColor;
    self.resultLabel.font =
        [UIFont systemFontOfSize:11];
    self.resultLabel.numberOfLines = 2;
    [vc.view addSubview:self.resultLabel];

    self.logView =
        [[UITextView alloc] initWithFrame:
            CGRectMake(10, 128, width - 20, 120)];

    self.logView.backgroundColor = UIColor.clearColor;
    self.logView.textColor = UIColor.greenColor;
    self.logView.font =
        [UIFont monospacedSystemFontOfSize:10
                                   weight:UIFontWeightRegular];
    self.logView.editable = NO;
    self.logView.text =
        [self.events componentsJoinedByString:@"\n"];
    [vc.view addSubview:self.logView];

    CGFloat gap = 6;
    CGFloat bw = (width - 36 - gap * 2) / 3;

    [self button:@"AUTO SCAN"
          frame:CGRectMake(12, 255, bw, 34)
         action:@selector(toggleScan)
         parent:vc.view];

    [self button:@"SPIN +1"
          frame:CGRectMake(18 + bw, 255, bw, 34)
         action:@selector(manualSpin)
         parent:vc.view];

    [self button:@"COPY LOG"
          frame:CGRectMake(24 + 2*bw, 255, bw, 34)
         action:@selector(copyLog)
         parent:vc.view];

    [self button:@"STACK +1"
          frame:CGRectMake(12, 295, bw, 34)
         action:@selector(stackPlus)
         parent:vc.view];

    [self button:@"STACK -1"
          frame:CGRectMake(18 + bw, 295, bw, 34)
         action:@selector(stackMinus)
         parent:vc.view];

    [self button:@"RESET"
          frame:CGRectMake(24 + 2*bw, 295, bw, 34)
         action:@selector(reset)
         parent:vc.view];

    self.window.hidden = NO;
    [self.window makeKeyAndVisible];

    [self refresh];
    [self log:@"PANEL READY"];
}

@end

__attribute__((constructor))
static void CMSLoggerInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[CMSLogger shared] start];
    });
}

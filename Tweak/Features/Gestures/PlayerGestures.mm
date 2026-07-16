#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <MediaPlayer/MediaPlayer.h>
#import <objc/message.h>
#import <objc/runtime.h>

static IMP OriginalOverlayDidMoveToWindow;
static const void *YTKACEPanAssociation = &YTKACEPanAssociation;
static const void *YTKACELongPressAssociation = &YTKACELongPressAssociation;
static const void *YTKACEGestureModeAssociation = &YTKACEGestureModeAssociation;
static const void *YTKACEGestureStartAssociation = &YTKACEGestureStartAssociation;
static const void *YTKACEIndicatorAssociation = &YTKACEIndicatorAssociation;
static const void *YTKACEVolumeViewAssociation = &YTKACEVolumeViewAssociation;

@interface YTKACEGestureCoordinator : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)sharedCoordinator;
@property(nonatomic, strong) NSTimer *seekTimer;
@property(nonatomic, weak) UIResponder *seekTarget;
@property(nonatomic, weak) UIView *seekView;
@property(nonatomic, assign) double seekTime;
@property(nonatomic, assign) NSInteger seekDirection;
- (void)handlePan:(UIPanGestureRecognizer *)recognizer;
- (void)handleHold:(UILongPressGestureRecognizer *)recognizer;
@end

@implementation YTKACEGestureCoordinator

+ (instancetype)sharedCoordinator {
    static YTKACEGestureCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [YTKACEGestureCoordinator new];
    });
    return coordinator;
}

- (UISlider *)volumeSliderInView:(UIView *)view {
    MPVolumeView *volumeView =
        objc_getAssociatedObject(view, YTKACEVolumeViewAssociation);
    if (volumeView == nil) {
        volumeView = [[MPVolumeView alloc] initWithFrame:CGRectMake(-100, -100, 1, 1)];
        volumeView.alpha = 0.01;
        [view addSubview:volumeView];
        objc_setAssociatedObject(view,
                                 YTKACEVolumeViewAssociation,
                                 volumeView,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *subview in volumeView.subviews) {
        if ([subview isKindOfClass:UISlider.class]) {
            return (UISlider *)subview;
        }
    }
    return nil;
}

- (UILabel *)indicatorInView:(UIView *)view {
    UILabel *label = objc_getAssociatedObject(view, YTKACEIndicatorAssociation);
    if (label != nil) {
        return label;
    }

    label = [UILabel new];
    label.textColor = UIColor.whiteColor;
    label.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.65];
    label.font = [UIFont monospacedDigitSystemFontOfSize:15.0
                                                 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;
    label.layer.cornerRadius = 10.0;
    label.clipsToBounds = YES;
    label.alpha = 0.0;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
        [label.widthAnchor constraintGreaterThanOrEqualToConstant:124.0],
        [label.heightAnchor constraintEqualToConstant:44.0]
    ]];
    objc_setAssociatedObject(view,
                             YTKACEIndicatorAssociation,
                             label,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return label;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    (void)gestureRecognizer;
    (void)other;
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (![gestureRecognizer isKindOfClass:UILongPressGestureRecognizer.class]) {
        return YES;
    }
    if (!YTKACEFeatureEnabled(@"kEnableHoldToSeek")) {
        return NO;
    }
    UIView *view = gestureRecognizer.view;
    CGPoint location = [gestureRecognizer locationInView:view];
    CGRect bounds = view.bounds;
    return location.x > CGRectGetWidth(bounds) * 0.2 &&
        location.x < CGRectGetWidth(bounds) * 0.8 &&
        location.y > CGRectGetHeight(bounds) * 0.15 &&
        location.y < CGRectGetHeight(bounds) * 0.85;
}

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    UIView *view = recognizer.view;
    CGPoint location = [recognizer locationInView:view];
    BOOL left = location.x < CGRectGetMidX(view.bounds);

    if (recognizer.state == UIGestureRecognizerStateBegan) {
        NSString *mode = nil;
        double start = 0.0;
        id volumeValue = YTKACEPreferenceObject(@"kVolumeSide");
        id brightnessValue = YTKACEPreferenceObject(@"kBrightnessSide");
        NSInteger volumeSide = volumeValue == nil ? 2 : [volumeValue integerValue];
        NSInteger brightnessSide = brightnessValue == nil ? 2 : [brightnessValue integerValue];
        BOOL volumeMatches = volumeSide != 2 && left == (volumeSide == 0);
        BOOL brightnessMatches = brightnessSide != 2 && left == (brightnessSide == 0);
        if (YTKACEMasterEnabled() && volumeMatches) {
            mode = @"volume";
            start = [self volumeSliderInView:view].value;
        } else if (YTKACEMasterEnabled() && brightnessMatches) {
            mode = @"brightness";
            start = UIScreen.mainScreen.brightness;
        }
        objc_setAssociatedObject(recognizer,
                                 YTKACEGestureModeAssociation,
                                 mode,
                                 OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(recognizer,
                                 YTKACEGestureStartAssociation,
                                 @(start),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSString *mode =
        objc_getAssociatedObject(recognizer, YTKACEGestureModeAssociation);
    if (mode == nil) {
        return;
    }

    CGFloat height = MAX(1.0, CGRectGetHeight(view.bounds));
    CGFloat delta = -[recognizer translationInView:view].y / height;
    double start =
        [objc_getAssociatedObject(recognizer, YTKACEGestureStartAssociation) doubleValue];
    double value = MIN(1.0, MAX(0.0, start + delta));
    UILabel *indicator = [self indicatorInView:view];

    if ([mode isEqualToString:@"volume"]) {
        UISlider *slider = [self volumeSliderInView:view];
        [slider setValue:(float)value animated:NO];
        [slider sendActionsForControlEvents:UIControlEventValueChanged];
        indicator.text =
            [NSString stringWithFormat:@"Volume  %.0f%%", value * 100.0];
    } else {
        UIScreen.mainScreen.brightness = value;
        indicator.text =
            [NSString stringWithFormat:@"Brightness  %.0f%%", value * 100.0];
    }

    indicator.alpha = 1.0;
    if (recognizer.state == UIGestureRecognizerStateEnded ||
        recognizer.state == UIGestureRecognizerStateCancelled) {
        [UIView animateWithDuration:0.2
                              delay:0.35
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            indicator.alpha = 0.0;
        } completion:nil];
        objc_setAssociatedObject(recognizer,
                                 YTKACEGestureModeAssociation,
                                 nil,
                                 OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
}

- (double)seekStep {
    NSDictionary *legacy =
        [NSUserDefaults.standardUserDefaults dictionaryForKey:@"YTKPlus"];
    id nested = legacy[@"kSeekDuration"];
    double value = [nested respondsToSelector:@selector(doubleValue)]
        ? [nested doubleValue]
        : [NSUserDefaults.standardUserDefaults doubleForKey:@"kSeekDuration"];
    return MIN(60.0, MAX(1.0, value > 0.0 ? value : 10.0));
}

- (UIResponder *)seekResponderForView:(UIView *)view {
    UIResponder *responder = view;
    while (responder != nil) {
        BOOL hasTime =
            [responder respondsToSelector:NSSelectorFromString(@"currentVideoMediaTime")] ||
            [responder respondsToSelector:NSSelectorFromString(@"mediaTime")];
        BOOL canSeek =
            [responder respondsToSelector:NSSelectorFromString(@"seekToTime:")] ||
            [responder respondsToSelector:
                NSSelectorFromString(@"didSeekToTime:toleranceBefore:toleranceAfter:")];
        if (hasTime && canSeek) {
            return responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

- (double)doubleFromResponder:(id)responder selectors:(NSArray<NSString *> *)names {
    for (NSString *name in names) {
        SEL selector = NSSelectorFromString(name);
        if ([responder respondsToSelector:selector]) {
            return ((double (*)(id, SEL))objc_msgSend)(responder, selector);
        }
    }
    return 0.0;
}

- (void)performSeek {
    id target = self.seekTarget;
    if (target == nil) {
        [self.seekTimer invalidate];
        self.seekTimer = nil;
        return;
    }

    self.seekTime += self.seekStep * self.seekDirection;
    double minimum = [self doubleFromResponder:target
                                     selectors:@[@"minimumSeekableTime"]];
    double maximum = [self doubleFromResponder:target
                                     selectors:@[
                                         @"maximumSeekableTime",
                                         @"currentVideoTotalTime",
                                         @"currentVideoDuration"
                                     ]];
    self.seekTime = MAX(minimum, self.seekTime);
    if (maximum > minimum) {
        self.seekTime = MIN(maximum, self.seekTime);
    }

    SEL detailed =
        NSSelectorFromString(@"didSeekToTime:toleranceBefore:toleranceAfter:");
    SEL simple = NSSelectorFromString(@"seekToTime:");
    if ([target respondsToSelector:detailed]) {
        ((void (*)(id, SEL, double, double, double))objc_msgSend)(
            target, detailed, self.seekTime, 0.0, 0.0
        );
    } else if ([target respondsToSelector:simple]) {
        ((void (*)(id, SEL, double))objc_msgSend)(
            target, simple, self.seekTime
        );
    }

    UILabel *indicator = [self indicatorInView:self.seekView];
    indicator.text = [NSString stringWithFormat:@"%@  %.0fs",
                      self.seekDirection < 0 ? @"Rewind" : @"Forward",
                      self.seekStep];
    indicator.alpha = 1.0;
}

- (void)handleHold:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        UIView *view = recognizer.view;
        self.seekTarget = [self seekResponderForView:view];
        if (self.seekTarget == nil) {
            return;
        }
        self.seekView = view;
        CGPoint location = [recognizer locationInView:view];
        self.seekDirection =
            location.x < CGRectGetMidX(view.bounds) ? -1 : 1;
        self.seekTime = [self doubleFromResponder:self.seekTarget
                                       selectors:@[
                                           @"currentVideoMediaTime",
                                           @"mediaTime"
                                       ]];
        [self performSeek];
        __weak YTKACEGestureCoordinator *weakSelf = self;
        self.seekTimer =
            [NSTimer scheduledTimerWithTimeInterval:0.1
                                           repeats:YES
                                             block:^(NSTimer *timer) {
            (void)timer;
            [weakSelf performSeek];
        }];
    } else if (recognizer.state == UIGestureRecognizerStateEnded ||
               recognizer.state == UIGestureRecognizerStateCancelled ||
               recognizer.state == UIGestureRecognizerStateFailed) {
        [self.seekTimer invalidate];
        self.seekTimer = nil;
        UILabel *indicator = [self indicatorInView:self.seekView];
        [UIView animateWithDuration:0.2
                              delay:0.35
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            indicator.alpha = 0.0;
        } completion:nil];
        self.seekTarget = nil;
        self.seekView = nil;
    }
}

@end

static void YTKACEOverlayDidMoveToWindow(UIView *receiver, SEL selector) {
    if (OriginalOverlayDidMoveToWindow != NULL) {
        ((void (*)(id, SEL))OriginalOverlayDidMoveToWindow)(receiver, selector);
    }
    if (objc_getAssociatedObject(receiver, YTKACEPanAssociation) != nil) {
        return;
    }

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:YTKACEGestureCoordinator.sharedCoordinator
                                                action:@selector(handlePan:)];
    pan.maximumNumberOfTouches = 1;
    pan.cancelsTouchesInView = NO;
    pan.delegate = YTKACEGestureCoordinator.sharedCoordinator;
    [receiver addGestureRecognizer:pan];
    objc_setAssociatedObject(receiver,
                             YTKACEPanAssociation,
                             pan,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILongPressGestureRecognizer *hold =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:YTKACEGestureCoordinator.sharedCoordinator
                    action:@selector(handleHold:)];
    hold.minimumPressDuration = 0.5;
    hold.cancelsTouchesInView = NO;
    hold.delegate = YTKACEGestureCoordinator.sharedCoordinator;
    [receiver addGestureRecognizer:hold];
    objc_setAssociatedObject(receiver,
                             YTKACELongPressAssociation,
                             hold,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void YTKACEInstallPlayerGestureHooks(void) {
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayView",
                              @"didMoveToWindow",
                              (IMP)YTKACEOverlayDidMoveToWindow,
                              &OriginalOverlayDidMoveToWindow);
}

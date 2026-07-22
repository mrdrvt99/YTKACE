#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../Downloads/DownloadCoordinator.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSHashTable<UIView *> *YTKACEReelViews;
static NSMutableDictionary<NSString *, NSValue *> *YTKACEShortsOriginals;
static const void *YTKACEShortsTrackAssociation = &YTKACEShortsTrackAssociation;
static const void *YTKACEShortsFillAssociation = &YTKACEShortsFillAssociation;
static const void *YTKACEShortsSkipAssociation = &YTKACEShortsSkipAssociation;
static const void *YTKACEShortsDownloadAssociation = &YTKACEShortsDownloadAssociation;
static const void *YTKACEShortsHiddenAssociation = &YTKACEShortsHiddenAssociation;
static NSInteger const YTKACEShortsDownloadTag = 0x59544B44;
static double YTKACELastShortsTime;
static double YTKACELastShortsDuration;
static id YTKACELatestShortsPlayerResponse;

static void YTKACESetShortsHidden(UIView *view, BOOL hidden) {
    NSNumber *baseline = objc_getAssociatedObject(
        view, YTKACEShortsHiddenAssociation);
    if (hidden) {
        if (baseline == nil) {
            objc_setAssociatedObject(view, YTKACEShortsHiddenAssociation,
                                     @(view.hidden),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.hidden = YES;
        view.userInteractionEnabled = NO;
    } else if (baseline != nil) {
        view.hidden = baseline.boolValue;
        view.userInteractionEnabled = YES;
        objc_setAssociatedObject(view, YTKACEShortsHiddenAssociation, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static NSString *YTKACEShortsHookKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%@|%@", NSStringFromClass(cls),
                                      NSStringFromSelector(selector)];
}

static IMP YTKACEShortsOriginal(id receiver, SEL selector) {
    for (Class cls = object_getClass(receiver); cls != Nil;
         cls = class_getSuperclass(cls)) {
        IMP original = (IMP)[YTKACEShortsOriginals[
            YTKACEShortsHookKey(cls, selector)] pointerValue];
        if (original != NULL) {
            return original;
        }
    }
    return NULL;
}

static id YTKACEShortsObject(id receiver, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return [receiver respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector) : nil;
}

static id YTKACEShortsResponseFromObject(id object,
                                         NSHashTable *visited,
                                         NSUInteger depth) {
    if (object == nil || depth > 7 || [visited containsObject:object]) {
        return nil;
    }
    [visited addObject:object];
    id response = YTKACEShortsObject(object, @"contentPlayerResponse") ?:
        YTKACEShortsObject(object, @"playerResponse");
    if (response != nil) {
        return response;
    }
    for (NSString *name in @[@"_youtubeiOSPlayerViewController", @"parentResponder",
                              @"parentViewController", @"eventsDelegate",
                              @"playbackController", @"activeVideoPlayerOverlay"]) {
        id related = YTKACEShortsObject(object, name);
        response = YTKACEShortsResponseFromObject(related, visited, depth + 1);
        if (response != nil) {
            return response;
        }
    }
    if ([object isKindOfClass:UIResponder.class]) {
        return YTKACEShortsResponseFromObject(
            ((UIResponder *)object).nextResponder, visited, depth + 1);
    }
    return nil;
}

static id YTKACEShortsPlayerResponseFromObject(id object) {
    NSHashTable *visited = [NSHashTable hashTableWithOptions:
        NSPointerFunctionsObjectPointerPersonality];
    return YTKACEShortsResponseFromObject(object, visited, 0);
}

@interface YTKACEShortsDownloadTarget : NSObject
+ (instancetype)sharedTarget;
- (void)downloadTapped:(UIButton *)sender;
@end

@implementation YTKACEShortsDownloadTarget
+ (instancetype)sharedTarget {
    static YTKACEShortsDownloadTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ target = [YTKACEShortsDownloadTarget new]; });
    return target;
}
- (void)downloadTapped:(UIButton *)sender {
    id response = YTKACEShortsPlayerResponseFromObject(sender) ?:
        YTKACELatestShortsPlayerResponse;
    YTKACEDownloadCoordinator.sharedCoordinator.playerResponse = response;
    [YTKACEDownloadCoordinator.sharedCoordinator
        showShortsDownloadMenuFromView:sender];
}
@end

static double YTKACEShortsDouble(id receiver, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        SEL selector = NSSelectorFromString(name);
        if ([receiver respondsToSelector:selector]) {
            return ((double (*)(id, SEL))objc_msgSend)(receiver, selector);
        }
    }
    return 0.0;
}

static id YTKACEShortsParent(id receiver) {
    SEL selector = NSSelectorFromString(@"parentViewController");
    return [receiver respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector)
        : nil;
}

static id YTKACEFindShortsController(id receiver) {
    id current = receiver;
    for (NSInteger index = 0; current != nil && index < 10; index++) {
        NSString *name = NSStringFromClass([current class]).lowercaseString;
        if ([name containsString:@"shorts"] || [name containsString:@"reel"]) {
            return current;
        }
        id parent = YTKACEShortsParent(current);
        if (parent != nil && parent != current) {
            current = parent;
        } else if ([current isKindOfClass:UIResponder.class]) {
            current = ((UIResponder *)current).nextResponder;
        } else {
            break;
        }
    }
    return nil;
}

static BOOL YTKACEAdvanceShort(id controller, id sender) {
    for (NSString *name in @[
        @"reelContentViewRequestsAdvanceToNextVideo:",
        @"advanceToNextVideo:",
        @"advanceToNextVideo",
        @"scrollToNextVideo"
    ]) {
        SEL selector = NSSelectorFromString(name);
        Method method = class_getInstanceMethod([controller class], selector);
        if (method == NULL) {
            continue;
        }
        if (method_getNumberOfArguments(method) == 3) {
            ((void (*)(id, SEL, id))objc_msgSend)(controller, selector, sender);
        } else {
            ((void (*)(id, SEL))objc_msgSend)(controller, selector);
        }
        return YES;
    }
    return NO;
}

static void YTKACEUpdateShortsProgress(void) {
    BOOL enabled = YTKACEFeatureEnabled(@"shortsProgress");
    CGFloat ratio = YTKACELastShortsDuration > 0.0
        ? (CGFloat)MIN(1.0, MAX(0.0, YTKACELastShortsTime / YTKACELastShortsDuration))
        : 0.0;
    for (UIView *view in YTKACEReelViews.allObjects) {
        CALayer *track = objc_getAssociatedObject(view, YTKACEShortsTrackAssociation);
        CALayer *fill = objc_getAssociatedObject(view, YTKACEShortsFillAssociation);
        track.hidden = !enabled;
        fill.hidden = !enabled;
        if (enabled) {
            CGFloat height = 3.0;
            track.frame = CGRectMake(0.0,
                                     MAX(0.0, CGRectGetHeight(view.bounds) - height),
                                     CGRectGetWidth(view.bounds),
                                     height);
            fill.frame = CGRectMake(0.0, 0.0,
                                    CGRectGetWidth(track.bounds) * ratio,
                                    height);
        }
    }
}

static void YTKACEConfigureReelView(UIView *receiver, BOOL showDownload) {
    [YTKACEReelViews addObject:receiver];
    CALayer *track = objc_getAssociatedObject(receiver, YTKACEShortsTrackAssociation);
    CALayer *fill = objc_getAssociatedObject(receiver, YTKACEShortsFillAssociation);
    if (track == nil) {
        track = [CALayer layer];
        track.backgroundColor = [UIColor colorWithWhite:0.45 alpha:0.55].CGColor;
        track.zPosition = 10000.0;
        fill = [CALayer layer];
        fill.backgroundColor = UIColor.redColor.CGColor;
        [track addSublayer:fill];
        [receiver.layer addSublayer:track];
        objc_setAssociatedObject(receiver, YTKACEShortsTrackAssociation,
                                 track, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(receiver, YTKACEShortsFillAssociation,
                                 fill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIButton *download = [receiver viewWithTag:YTKACEShortsDownloadTag];
    if (showDownload && download == nil) {
        download = [UIButton buttonWithType:UIButtonTypeSystem];
        download.tag = YTKACEShortsDownloadTag;
        download.accessibilityIdentifier = @"YTKACE Shorts Download";
        download.accessibilityLabel = @"Download Short";
        download.tintColor = UIColor.whiteColor;
        [download setImage:YTKACEDownloadGlyphImage()
                  forState:UIControlStateNormal];
        download.layer.shadowColor = UIColor.blackColor.CGColor;
        download.layer.shadowOpacity = 0.55;
        download.layer.shadowRadius = 4.0;
        download.layer.shadowOffset = CGSizeMake(0.0, 2.0);
        download.translatesAutoresizingMaskIntoConstraints = NO;
        [download addTarget:YTKACEShortsDownloadTarget.sharedTarget
                     action:@selector(downloadTapped:)
           forControlEvents:UIControlEventTouchUpInside];
        [receiver addSubview:download];
        [NSLayoutConstraint activateConstraints:@[
            [download.widthAnchor constraintEqualToConstant:40.0],
            [download.heightAnchor constraintEqualToConstant:40.0],
            [download.trailingAnchor constraintEqualToAnchor:
                receiver.safeAreaLayoutGuide.trailingAnchor constant:-12.0],
            [download.topAnchor constraintEqualToAnchor:
                receiver.safeAreaLayoutGuide.topAnchor constant:65.0]
        ]];
        objc_setAssociatedObject(receiver, YTKACEShortsDownloadAssociation,
            download, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (download != nil) {
        download.hidden = !YTKACEFeatureEnabled(YTKACEDownloadKey);
        [receiver bringSubviewToFront:download];
    }
    id response = YTKACEShortsPlayerResponseFromObject(receiver);
    if (response != nil) {
        YTKACELatestShortsPlayerResponse = response;
    }
    YTKACEUpdateShortsProgress();
}

static void YTKACEReelLayout(UIView *receiver, SEL selector) {
    IMP original = YTKACEShortsOriginal(receiver, selector);
    if (original != NULL) {
        ((void (*)(id, SEL))original)(receiver, selector);
    }
    YTKACEConfigureReelView(receiver, NO);
}

static void YTKACEShortsControllerLayout(UIViewController *receiver,
                                         SEL selector) {
    IMP original = YTKACEShortsOriginal(receiver, selector);
    if (original != NULL) {
        ((void (*)(id, SEL))original)(receiver, selector);
    }
    YTKACEConfigureReelView(receiver.view, YES);
}

static void YTKACEPausedLayout(UIView *receiver, SEL selector) {
    IMP original = YTKACEShortsOriginal(receiver, selector);
    if (original != NULL) {
        ((void (*)(id, SEL))original)(receiver, selector);
    }
    BOOL hidden = YTKACEFeatureEnabled(@"kEnableBlockShortsOverlays");
    YTKACESetShortsHidden(receiver, hidden);
}

static void YTKACEInteractiveStickerLayout(UIView *receiver, SEL selector) {
    IMP original = YTKACEShortsOriginal(receiver, selector);
    if (original != NULL) {
        ((void (*)(id, SEL))original)(receiver, selector);
    }
    NSString *token = [NSString stringWithFormat:@"%@ %@ %@",
        NSStringFromClass(receiver.class).lowercaseString,
        receiver.accessibilityIdentifier.lowercaseString ?: @"",
        receiver.description.lowercaseString ?: @""];
    BOOL product = YTKACEFeatureEnabled(@"kEnableHideShortsProducts") &&
        ([token containsString:@"product"] ||
         [token containsString:@"shopping"]);
    BOOL stickerAd = YTKACEFeatureEnabled(@"kEnableHideShortsStickerAds") &&
        (([token containsString:@"sticker"] &&
          ([token containsString:@"sponsor"] ||
           [token containsString:@"promot"] ||
           [token containsString:@"brand"] ||
           [token containsString:@"product"])) ||
         [token containsString:@"shorts_ads_shopping"]);
    YTKACESetShortsHidden(receiver, product || stickerAd);
}

static void YTKACEInstallShortsLayout(NSString *className, IMP replacement) {
    IMP original = NULL;
    if (YTKACEInstallInstanceHook(className, @"layoutSubviews",
                                  replacement, &original) &&
        original != NULL) {
        Class cls = NSClassFromString(className);
        YTKACEShortsOriginals[YTKACEShortsHookKey(
            cls, @selector(layoutSubviews))] =
            [NSValue valueWithPointer:(const void *)original];
    }
}

static void YTKACEInstallShortsController(NSString *className) {
    SEL selector = @selector(viewDidLayoutSubviews);
    IMP original = NULL;
    if (YTKACEInstallInstanceHook(className,
                                  NSStringFromSelector(selector),
                                  (IMP)YTKACEShortsControllerLayout,
                                  &original) && original != NULL) {
        Class cls = NSClassFromString(className);
        YTKACEShortsOriginals[YTKACEShortsHookKey(cls, selector)] =
            [NSValue valueWithPointer:(const void *)original];
    }
}

static void YTKACEShortsTimeChanged(NSNotification *notification) {
    id player = notification.object;
    id shorts = YTKACEFindShortsController(player);
    if (shorts == nil) {
        return;
    }
    id response = YTKACEShortsPlayerResponseFromObject(player) ?:
        YTKACEShortsPlayerResponseFromObject(shorts);
    if (response != nil) {
        YTKACELatestShortsPlayerResponse = response;
    }
    double time = [notification.userInfo[@"time"] doubleValue];
    double duration = YTKACEShortsDouble(player, @[
        @"currentVideoTotalMediaTime",
        @"currentVideoTotalTime",
        @"currentVideoDuration",
        @"totalMediaTime"
    ]);
    YTKACELastShortsTime = time;
    YTKACELastShortsDuration = duration;
    YTKACEUpdateShortsProgress();

    if (!YTKACEFeatureEnabled(@"autoSkipShorts") || duration <= 1.0) {
        return;
    }
    if (time < duration * 0.5) {
        objc_setAssociatedObject(shorts, YTKACEShortsSkipAssociation, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (time >= duration - 0.35 &&
        ![objc_getAssociatedObject(shorts, YTKACEShortsSkipAssociation) boolValue]) {
        if (YTKACEAdvanceShort(shorts, player)) {
            objc_setAssociatedObject(shorts, YTKACEShortsSkipAssociation, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

void YTKACEInstallShortsHooks(void) {
    if (YTKACEReelViews == nil) {
        YTKACEReelViews = [NSHashTable weakObjectsHashTable];
        YTKACEShortsOriginals = [NSMutableDictionary dictionary];
        [NSNotificationCenter.defaultCenter
            addObserverForName:@"YTKACEPlaybackTimeDidChange"
            object:nil
            queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *notification) {
                YTKACEShortsTimeChanged(notification);
            }];
    }
    for (NSString *className in @[
        @"YTReelContentView",
        @"YTReelPlayerView",
        @"YTShortsPlayerView",
        @"YTShortsPlayerViewControllerView",
        @"YTShortsPlayerViewSwift"
    ]) {
        YTKACEInstallShortsLayout(className, (IMP)YTKACEReelLayout);
    }
    for (NSString *className in @[
        @"YTAppReelWatchRootViewController",
        @"YTReelWatchRootViewController",
        @"YTReelContainerViewController",
        @"YTReelPlaybackViewController",
        @"YTReelPlayerViewController",
        @"YTShortsPlayerViewController"
    ]) {
        YTKACEInstallShortsController(className);
    }
    for (NSString *className in @[
        @"YTReelPausedStateCarouselView",
        @"YTReelPlayerPausedStateView"
    ]) {
        YTKACEInstallShortsLayout(className, (IMP)YTKACEPausedLayout);
    }
    for (NSString *className in @[
        @"YTReelInteractiveStickerView",
        @"YTShortsStickersView",
        @"YTShortsStickersViewSwift"
    ]) {
        YTKACEInstallShortsLayout(className,
                                  (IMP)YTKACEInteractiveStickerLayout);
    }
}

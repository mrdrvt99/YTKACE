#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdlib.h>

static IMP OriginalDeviceIdiom;
static IMP OriginalAddInteraction;
static IMP OriginalSemanticContent;
static IMP OriginalSetSemanticContent;
static IMP OriginalCaptionTracks;
static IMP OriginalCaptionControllerAlloc;
static NSMutableDictionary<NSString *, NSValue *> *YTKACEMiscOriginals;
static const void *YTKACECaptionTracksAssociation =
    &YTKACECaptionTracksAssociation;
static const void *YTKACELastCaptionTrackAssociation =
    &YTKACELastCaptionTrackAssociation;
static const void *YTKACEAppliedCaptionAssociation =
    &YTKACEAppliedCaptionAssociation;
static NSHashTable *YTKACECaptionControllers;

static void YTKACEInstallCurrentMiniPlayerHooks(void);

static NSString *YTKACECaptionTrackKey(id track) {
    if (track == nil) {
        return nil;
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *key in @[@"languageCode", @"displayName", @"vssId",
                             @"kind"]) {
        @try {
            id value = [track valueForKey:key];
            if (value != nil) {
                [parts addObject:[value description]];
            }
        } @catch (__unused NSException *exception) {
        }
    }
    return parts.count != 0 ? [parts componentsJoinedByString:@"|"] :
        [NSString stringWithFormat:@"%p", (__bridge void *)track];
}

static BOOL YTKACECaptionRequestReceiver(id receiver, SEL selector) {
    NSString *className = NSStringFromClass([receiver class]).lowercaseString;
    NSString *name = NSStringFromSelector(selector).lowercaseString;
    return [className containsString:@"request"] ||
        [className containsString:@"params"] ||
        [className containsString:@"config"] ||
        [name containsString:@"requested"] ||
        [name containsString:@"devicecaptions"] ||
        [name containsString:@"persistence"] ||
        [name containsString:@"respectdevice"] ||
        [name containsString:@"hiddenonstart"];
}

static NSString *YTKACEMiscKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%@|%@", NSStringFromClass(cls),
                                      NSStringFromSelector(selector)];
}

static IMP YTKACEMiscOriginal(id receiver, SEL selector) {
    for (Class cls = object_getClass(receiver); cls != Nil; cls = class_getSuperclass(cls)) {
        IMP original = (IMP)[YTKACEMiscOriginals[
            YTKACEMiscKey(cls, selector)] pointerValue];
        if (original != NULL) {
            return original;
        }
    }
    return NULL;
}

static BOOL YTKACEMiniPlayerEnabled(void) {
    return YTKACEFeatureEnabled(@"kEnableMiniPlayerAllVideos") ||
        YTKACEFeatureEnabled(@"kEnableminiPlayerall");
}

static UIUserInterfaceIdiom YTKACEUserInterfaceIdiom(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"kEnableiPadOSMode")) {
        return UIUserInterfaceIdiomPad;
    }
    return OriginalDeviceIdiom != NULL
        ? ((UIUserInterfaceIdiom (*)(id, SEL))OriginalDeviceIdiom)(receiver, selector)
        : UIUserInterfaceIdiomPhone;
}

static void YTKACEAddInteraction(UIView *receiver, SEL selector, id interaction) {
    if (YTKACEFeatureEnabled(@"kEnableDisableDragDrop") &&
        ([interaction isKindOfClass:UIDragInteraction.class] ||
         [interaction isKindOfClass:UIDropInteraction.class])) {
        return;
    }
    if (OriginalAddInteraction != NULL) {
        ((void (*)(id, SEL, id))OriginalAddInteraction)(receiver, selector, interaction);
    }
}

static UISemanticContentAttribute YTKACESemanticContent(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"kEnableDisableRTL")) {
        return UISemanticContentAttributeForceLeftToRight;
    }
    return OriginalSemanticContent != NULL
        ? ((UISemanticContentAttribute (*)(id, SEL))OriginalSemanticContent)(receiver, selector)
        : UISemanticContentAttributeUnspecified;
}

static void YTKACESetSemanticContent(id receiver,
                                     SEL selector,
                                     UISemanticContentAttribute value) {
    if (OriginalSetSemanticContent != NULL) {
        ((void (*)(id, SEL, UISemanticContentAttribute))OriginalSetSemanticContent)(
            receiver,
            selector,
            YTKACEFeatureEnabled(@"kEnableDisableRTL")
                ? UISemanticContentAttributeForceLeftToRight
                : value
        );
    }
}

static BOOL YTKACEMiniPlayerValue(id receiver, SEL selector) {
    if (YTKACEMiniPlayerEnabled()) {
        NSString *name = NSStringFromSelector(selector).lowercaseString;
        return !([name containsString:@"disable"] ||
                 [name containsString:@"unavailable"] ||
                 [name containsString:@"blocked"] ||
                 [name containsString:@"prevent"] ||
                 [name containsString:@"hide"] ||
                 [name containsString:@"onlywhenplaying"]);
    }
    IMP original = YTKACEMiscOriginal(receiver, selector);
    return original != NULL ? ((BOOL (*)(id, SEL))original)(receiver, selector) : NO;
}

static BOOL YTKACEMiniPlayerPauseOnlyValue(id receiver, SEL selector) {
    if (YTKACEMiniPlayerEnabled()) {
        return NO;
    }
    IMP original = YTKACEMiscOriginal(receiver, selector);
    return original != NULL ? ((BOOL (*)(id, SEL))original)(receiver, selector) : NO;
}

static BOOL YTKACEAgeValue(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"kEnableAgeRestriction")) {
        NSString *name = NSStringFromSelector(selector).lowercaseString;
        return [name containsString:@"verified"] ||
            [name containsString:@"allowed"];
    }
    IMP original = YTKACEMiscOriginal(receiver, selector);
    return original != NULL ? ((BOOL (*)(id, SEL))original)(receiver, selector) : NO;
}

static BOOL YTKACECaptionValue(id receiver, SEL selector) {
    NSString *name = NSStringFromSelector(selector).lowercaseString;
    BOOL negative = [name containsString:@"disabled"] ||
        [name containsString:@"hidden"];
    if (YTKACEFeatureEnabled(@"kEnableDisableCaptions")) {
        return negative;
    }
    if (YTKACEFeatureEnabled(@"kEnableKeepCaptionOn")) {
        if (!YTKACECaptionRequestReceiver(receiver, selector)) {
            IMP original = YTKACEMiscOriginal(receiver, selector);
            return original != NULL
                ? ((BOOL (*)(id, SEL))original)(receiver, selector) : NO;
        }
        if ([name containsString:@"respectdevicecaption"] ||
            [name containsString:@"hiddenonstart"]) {
            return NO;
        }
        return !negative;
    }
    IMP original = YTKACEMiscOriginal(receiver, selector);
    return original != NULL ? ((BOOL (*)(id, SEL))original)(receiver, selector) : NO;
}

static void YTKACECaptionSetter(id receiver, SEL selector, BOOL enabled) {
    IMP original = YTKACEMiscOriginal(receiver, selector);
    if (original == NULL) {
        return;
    }
    NSString *name = NSStringFromSelector(selector).lowercaseString;
    BOOL negative = [name containsString:@"disabled"] ||
        [name containsString:@"hidden"];
    BOOL value = enabled;
    if (YTKACEFeatureEnabled(@"kEnableDisableCaptions")) {
        value = negative;
    } else if (YTKACEFeatureEnabled(@"kEnableKeepCaptionOn") &&
               YTKACECaptionRequestReceiver(receiver, selector)) {
        value = !negative;
    }
    ((void (*)(id, SEL, BOOL))original)(receiver, selector, value);
}

static id YTKACEFirstCaptionTrack(id tracks) {
    if ([tracks isKindOfClass:NSArray.class]) {
        return [tracks firstObject];
    }
    if ([tracks respondsToSelector:@selector(allObjects)]) {
        id objects = ((id (*)(id, SEL))objc_msgSend)(tracks,
                                                     @selector(allObjects));
        return [objects isKindOfClass:NSArray.class] ? [objects firstObject] : nil;
    }
    return nil;
}

static void YTKACEScheduleCaptionSelection(id track) {
    if (track == nil || !YTKACEFeatureEnabled(@"kEnableKeepCaptionOn")) {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                  (int64_t)(0.45 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSString *key = YTKACECaptionTrackKey(track);
        NSArray *controllers = nil;
        @synchronized (YTKACECaptionControllers) {
            controllers = YTKACECaptionControllers.allObjects;
        }
        for (id controller in controllers) {
            NSString *applied = objc_getAssociatedObject(
                controller, YTKACEAppliedCaptionAssociation);
            if ([applied isEqualToString:key]) {
                continue;
            }
            SEL selector = NSSelectorFromString(
                @"setSelectedCaptionTrack:selectionReason:");
            if (![controller respondsToSelector:selector]) {
                continue;
            }
            objc_setAssociatedObject(controller,
                YTKACEAppliedCaptionAssociation, key,
                OBJC_ASSOCIATION_COPY_NONATOMIC);
            ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(
                controller, selector, track, 1);
        }
    });
}

static id YTKACECaptionControllerAlloc(id receiver, SEL selector, NSZone *zone) {
    id result = OriginalCaptionControllerAlloc != NULL
        ? ((id (*)(id, SEL, NSZone *))OriginalCaptionControllerAlloc)(
            receiver, selector, zone) : nil;
    if (result != nil) {
        @synchronized (YTKACECaptionControllers) {
            [YTKACECaptionControllers addObject:result];
        }
    }
    return result;
}

static id YTKACECaptionControllerInit(id receiver, SEL selector) {
    IMP original = YTKACEMiscOriginal(receiver, selector);
    id result = original != NULL
        ? ((id (*)(id, SEL))original)(receiver, selector) : receiver;
    if (result != nil) {
        @synchronized (YTKACECaptionControllers) {
            [YTKACECaptionControllers addObject:result];
        }
    }
    return result;
}

static void YTKACECaptionTracksSetter(id receiver, SEL selector, id tracks) {
    IMP original = YTKACEMiscOriginal(receiver, selector);
    if (original != NULL) {
        ((void (*)(id, SEL, id))original)(receiver, selector, tracks);
    }
    id track = YTKACEFirstCaptionTrack(tracks);
    id previousTrack = objc_getAssociatedObject(
        receiver, YTKACELastCaptionTrackAssociation);
    if (previousTrack != track) {
        objc_setAssociatedObject(receiver, YTKACELastCaptionTrackAssociation,
                                 track, OBJC_ASSOCIATION_ASSIGN);
        YTKACEScheduleCaptionSelection(track);
    }
    if (track == nil) {
        return;
    }
    objc_setAssociatedObject(receiver,
                             YTKACECaptionTracksAssociation,
                             tracks,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void YTKACECaptionTrackSetter(id receiver, SEL selector, id track) {
    IMP original = YTKACEMiscOriginal(receiver, selector);
    if (original != NULL) {
        ((void (*)(id, SEL, id))original)(receiver, selector, track);
    }
}

static void YTKACECaptionSelectedTrackSetter(id receiver,
                                             SEL selector,
                                             id track,
                                             NSInteger reason) {
    IMP original = YTKACEMiscOriginal(receiver, selector);
    if (original != NULL) {
        ((void (*)(id, SEL, id, NSInteger))original)(receiver,
                                                      selector,
                                                      track,
                                                      reason);
    }
}

static id YTKACECaptionTracks(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"kEnableDisableCaptions")) {
        return @[];
    }
    id tracks = OriginalCaptionTracks != NULL
        ? ((id (*)(id, SEL))OriginalCaptionTracks)(receiver, selector)
        : nil;
    return tracks;
}

static void YTKACEHUDMessage(id receiver, SEL selector, id message) {
    if (YTKACEFeatureEnabled(@"kEnableHideHudeAlerts")) {
        return;
    }
    NSString *text = nil;
    if ([message isKindOfClass:NSString.class]) {
        text = message;
    } else if ([message isKindOfClass:NSAttributedString.class]) {
        text = [(NSAttributedString *)message string];
    } else {
        for (NSString *name in @[@"text", @"message", @"title"]) {
            SEL valueSelector = NSSelectorFromString(name);
            if (![message respondsToSelector:valueSelector]) {
                continue;
            }
            id value = ((id (*)(id, SEL))objc_msgSend)(message,
                                                       valueSelector);
            if ([value isKindOfClass:NSString.class]) {
                text = value;
                break;
            }
            if ([value isKindOfClass:NSAttributedString.class]) {
                text = [(NSAttributedString *)value string];
                break;
            }
        }
    }
    NSString *lower = text.lowercaseString;
    if (YTKACEMiniPlayerEnabled() &&
        [lower containsString:@"miniplayer"] &&
        [lower containsString:@"kids"]) {
        return;
    }
    IMP original = YTKACEMiscOriginal(receiver, selector);
    if (original != NULL) {
        ((void (*)(id, SEL, id))original)(receiver, selector, message);
    }
}

static void YTKACEStoreMiscOriginal(NSString *className,
                                    NSString *selectorName,
                                    IMP original) {
    Class cls = NSClassFromString(className);
    if (cls != Nil && original != NULL) {
        YTKACEMiscOriginals[YTKACEMiscKey(
            cls,
            NSSelectorFromString(selectorName)
        )] = [NSValue valueWithPointer:(const void *)original];
    }
}

static void YTKACEInstallMiscBool(NSString *className,
                                  NSString *selectorName,
                                  IMP replacement) {
    Class cls = NSClassFromString(className);
    Method method = cls == Nil ? NULL : class_getInstanceMethod(
        cls,
        NSSelectorFromString(selectorName)
    );
    if (method == NULL || method_getNumberOfArguments(method) != 2) {
        return;
    }
    char type[8] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != 'B' && type[0] != 'c') {
        return;
    }
    IMP original = NULL;
    if (YTKACEInstallInstanceHook(className, selectorName, replacement, &original)) {
        YTKACEStoreMiscOriginal(className, selectorName, original);
    }
}

static void YTKACEInstallMiscSetter(NSString *className,
                                    NSString *selectorName,
                                    IMP replacement) {
    Class cls = NSClassFromString(className);
    Method method = cls == Nil ? NULL : class_getInstanceMethod(
        cls,
        NSSelectorFromString(selectorName)
    );
    if (method == NULL || method_getNumberOfArguments(method) != 3) {
        return;
    }
    IMP original = NULL;
    if (YTKACEInstallInstanceHook(className, selectorName, replacement, &original)) {
        YTKACEStoreMiscOriginal(className, selectorName, original);
    }
}

static void YTKACEInstallMiscObjectSetter(NSString *className,
                                          NSString *selectorName,
                                          IMP replacement) {
    Class cls = NSClassFromString(className);
    SEL selector = NSSelectorFromString(selectorName);
    Method method = cls == Nil ? NULL : class_getInstanceMethod(cls, selector);
    if (method == NULL || method_getNumberOfArguments(method) != 3) {
        return;
    }
    char type[8] = {0};
    method_getArgumentType(method, 2, type, sizeof(type));
    if (type[0] != '@') {
        return;
    }
    IMP original = NULL;
    if (YTKACEInstallInstanceHook(className, selectorName,
                                  replacement, &original)) {
        YTKACEStoreMiscOriginal(className, selectorName, original);
    }
}

static void YTKACEInstallCaptionSelectedSetter(NSString *className) {
    NSString *selectorName = @"setSelectedCaptionTrack:selectionReason:";
    Class cls = NSClassFromString(className);
    SEL selector = NSSelectorFromString(selectorName);
    Method method = cls == Nil ? NULL : class_getInstanceMethod(cls, selector);
    if (method == NULL || method_getNumberOfArguments(method) != 4) {
        return;
    }
    char type[8] = {0};
    method_getArgumentType(method, 2, type, sizeof(type));
    if (type[0] != '@') {
        return;
    }
    IMP original = NULL;
    if (YTKACEInstallInstanceHook(className, selectorName,
                                  (IMP)YTKACECaptionSelectedTrackSetter,
                                  &original)) {
        YTKACEStoreMiscOriginal(className, selectorName, original);
    }
}

static BOOL YTKACEClassNameMatches(NSString *className,
                                   NSArray<NSString *> *tokens) {
    NSString *lower = className.lowercaseString;
    for (NSString *token in tokens) {
        if ([lower containsString:token]) {
            return YES;
        }
    }
    return NO;
}

static void YTKACEInstallCurrentMiniPlayerHooks(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            YTKACEInstallCurrentMiniPlayerHooks();
        });
        return;
    }
    NSArray *selectors = @[
        @"isPlayableInMiniPlayer", @"isPlayableInMiniplayer",
        @"miniplayerEnabled", @"isMiniplayerDisabled",
        @"miniPlayerDisabled", @"isMiniplayerUnavailable",
        @"enableIosFloatingMiniplayer", @"enableMiniPlayerOnlyWhenPlaying",
        @"disableMiniPlayerWhenPaused", @"disableIphoneMiniplayerTransitionFix",
        @"enableIosFloatingMiniplayerTransitionBugFix",
        @"enableMiniplayerErrorFix", @"enableMiniplayerChangesPostCairo",
        @"shouldOpenMiniplayerOnStateChange", @"shouldShowMiniPlayer",
        @"hasShouldShowMiniPlayer", @"hasDisplayMiniPlayer",
        @"hasMiniplayer", @"isMiniplayer", @"allowDockingForMiniplayer",
        @"blockedForKidsContent", @"hasBlockedForKidsContent"
    ];
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) {
        return;
    }
    Class *classes = (Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);
    NSArray *classTokens = @[
        @"mini", @"playability", @"playerresponse",
        @"watch", @"playerhotconfig", @"globalconfig"
    ];
    for (int index = 0; index < count; index++) {
        NSString *className = NSStringFromClass(classes[index]);
        if (!YTKACEClassNameMatches(className, classTokens)) {
            continue;
        }
        YTKACEInstallMiscBool(className,
            @"isMiniplayerRendererPlaybackModePauseOnly",
            (IMP)YTKACEMiniPlayerPauseOnlyValue);
        for (NSString *selectorName in selectors) {
            YTKACEInstallMiscBool(className, selectorName,
                                  (IMP)YTKACEMiniPlayerValue);
        }
    }
    free(classes);
}

static void YTKACEInstallCurrentCaptionHooks(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            YTKACEInstallCurrentCaptionHooks();
        });
        return;
    }
    NSArray *getters = @[
        @"captionsEnabled", @"areCaptionsEnabled", @"captionEnabled",
        @"isCaptionEnabled", @"closedCaptionsEnabled",
        @"closedCaptioningEnabled", @"captionsEnabledWhenAvailable",
        @"shouldShowCaptions", @"captionsActive", @"captionVisible",
        @"captionsVisible", @"captionsRequested", @"deviceCaptionsOn",
        @"captionsDisabled", @"captionsHidden",
        @"captionVisibilityPersistenceEnabled",
        @"captionLanguagePersistenceEnabled", @"respectDeviceCaptionSetting",
        @"inlinePlaybackCaptionHiddenOnStartEnabled"
    ];
    NSArray *setters = @[
        @"setCaptionsEnabled:", @"setClosedCaptionsEnabled:",
        @"setCaptionEnabled:", @"setIsCaptionEnabled:",
        @"setCaptionsActive:", @"setCaptionVisible:",
        @"setCaptionsVisible:", @"setCaptionsRequested:",
        @"setDeviceCaptionsOn:", @"setCaptionsDisabled:",
        @"setCaptionsHidden:", @"setPersistentUserCaptionVisibility:",
        @"setUserPreferredCaptionVisibilityAsHidden:"
    ];
    NSArray *trackLists = @[
        @"setAvailableCaptionTracks:", @"setCaptionTrackArray:",
        @"setUserVisibleCaptionTracks:", @"setTracklistCaptionTracks:"
    ];
    NSArray *trackSetters = @[
        @"setActiveCaptionTrack:", @"setCaptionTrack:"
    ];
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) {
        return;
    }
    Class *classes = (Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);
    NSArray *classTokens = @[
        @"caption", @"player", @"playback", @"watch", @"globalconfig"
    ];
    for (int index = 0; index < count; index++) {
        NSString *className = NSStringFromClass(classes[index]);
        if (!YTKACEClassNameMatches(className, classTokens)) {
            continue;
        }
        for (NSString *selectorName in getters) {
            YTKACEInstallMiscBool(className, selectorName,
                                  (IMP)YTKACECaptionValue);
        }
        for (NSString *selectorName in setters) {
            YTKACEInstallMiscSetter(className, selectorName,
                                    (IMP)YTKACECaptionSetter);
        }
        for (NSString *selectorName in trackLists) {
            YTKACEInstallMiscObjectSetter(className, selectorName,
                (IMP)YTKACECaptionTracksSetter);
        }
        for (NSString *selectorName in trackSetters) {
            YTKACEInstallMiscObjectSetter(className, selectorName,
                (IMP)YTKACECaptionTrackSetter);
        }
        YTKACEInstallCaptionSelectedSetter(className);
    }
    NSString *controllerClass = @"MLInnerTubeCaptionController";
    YTKACEInstallClassHook(controllerClass, @"allocWithZone:",
                          (IMP)YTKACECaptionControllerAlloc,
                          &OriginalCaptionControllerAlloc);
    IMP original = NULL;
    if (YTKACEInstallInstanceHook(controllerClass, @"init",
                                  (IMP)YTKACECaptionControllerInit,
                                  &original)) {
        YTKACEStoreMiscOriginal(controllerClass, @"init", original);
    }
    free(classes);
}

void YTKACEInstallMiscellaneousHooks(void) {
    if (YTKACEMiscOriginals == nil) {
        YTKACEMiscOriginals = [NSMutableDictionary dictionary];
        YTKACECaptionControllers = [NSHashTable weakObjectsHashTable];
    }
    YTKACEInstallInstanceHook(@"UIDevice", @"userInterfaceIdiom",
                              (IMP)YTKACEUserInterfaceIdiom,
                              &OriginalDeviceIdiom);
    YTKACEInstallInstanceHook(@"UIView", @"addInteraction:",
                              (IMP)YTKACEAddInteraction,
                              &OriginalAddInteraction);
    YTKACEInstallInstanceHook(@"UIView", @"semanticContentAttribute",
                              (IMP)YTKACESemanticContent,
                              &OriginalSemanticContent);
    YTKACEInstallInstanceHook(@"UIView", @"setSemanticContentAttribute:",
                              (IMP)YTKACESetSemanticContent,
                              &OriginalSetSemanticContent);
    NSArray<NSString *> *miniClasses = @[
        @"YTIPlayabilityStatus",
        @"YTPlayerResponse",
        @"YTIPlayerResponse",
        @"YTMiniplayerController"
    ];
    NSArray<NSString *> *miniSelectors = @[
        @"isPlayableInMiniPlayer",
        @"isPlayableInMiniplayer",
        @"miniplayerEnabled",
        @"isMiniplayerDisabled",
        @"miniPlayerDisabled",
        @"isMiniplayerUnavailable"
    ];
    for (NSString *className in miniClasses) {
        YTKACEInstallMiscBool(className,
            @"isMiniplayerRendererPlaybackModePauseOnly",
            (IMP)YTKACEMiniPlayerPauseOnlyValue);
        for (NSString *selectorName in miniSelectors) {
            YTKACEInstallMiscBool(className, selectorName, (IMP)YTKACEMiniPlayerValue);
        }
    }

    for (NSString *className in @[@"YTIPlayabilityStatus", @"YTPlayerResponse"] ) {
        for (NSString *selectorName in @[
            @"isAgeRestricted",
            @"requiresAgeVerification",
            @"shouldShowAgeGate",
            @"ageGateRequired",
            @"isAgeVerified",
            @"isAgeAllowed"
        ]) {
            YTKACEInstallMiscBool(className, selectorName, (IMP)YTKACEAgeValue);
        }
    }

    NSArray<NSString *> *captionClasses = @[
        @"YTPlayerViewController",
        @"YTLocalPlaybackController",
        @"YTMainAppVideoPlayerOverlayViewController",
        @"YTCaptionController"
    ];
    for (NSString *className in captionClasses) {
        for (NSString *selectorName in @[
            @"captionsEnabled",
            @"areCaptionsEnabled",
            @"isCaptionTrackSelected",
            @"closedCaptionsEnabled",
            @"captionsDisabled"
        ]) {
            YTKACEInstallMiscBool(className, selectorName, (IMP)YTKACECaptionValue);
        }
        for (NSString *selectorName in @[
            @"setCaptionsEnabled:",
            @"setClosedCaptionsEnabled:"
        ]) {
            YTKACEInstallMiscSetter(className, selectorName, (IMP)YTKACECaptionSetter);
        }
    }

    YTKACEInstallInstanceHook(@"YTIPlayerResponse",
                              @"captionTracksArray",
                              (IMP)YTKACECaptionTracks,
                              &OriginalCaptionTracks);
    static dispatch_once_t scanToken;
    dispatch_once(&scanToken, ^{
        for (NSNumber *delay in @[@0.75, @4.0, @10.0]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(delay.doubleValue *
                                                   NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                YTKACEInstallCurrentMiniPlayerHooks();
                YTKACEInstallCurrentCaptionHooks();
            });
        }
    });

    for (NSString *selectorName in @[@"showMessageMainThread:", @"showMessage:"]) {
        IMP original = NULL;
        if (YTKACEInstallInstanceHook(@"GOOHUDManagerInternal",
                                      selectorName,
                                      (IMP)YTKACEHUDMessage,
                                      &original)) {
            YTKACEStoreMiscOriginal(@"GOOHUDManagerInternal", selectorName, original);
        }
    }
}

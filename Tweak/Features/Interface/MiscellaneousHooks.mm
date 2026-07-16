#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static IMP OriginalDeviceIdiom;
static IMP OriginalAddInteraction;
static IMP OriginalSemanticContent;
static IMP OriginalSetSemanticContent;
static IMP OriginalCaptionTracks;
static NSMutableDictionary<NSString *, NSValue *> *YTKACEMiscOriginals;

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
    if (YTKACEFeatureEnabled(@"kEnableMiniPlayerAllVideos")) {
        NSString *name = NSStringFromSelector(selector).lowercaseString;
        return !([name containsString:@"disable"] ||
                 [name containsString:@"unavailable"] ||
                 [name containsString:@"blocked"]);
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
    if (YTKACEFeatureEnabled(@"kEnableDisableCaptions")) {
        NSString *name = NSStringFromSelector(selector).lowercaseString;
        return [name containsString:@"disabled"];
    }
    if (YTKACEFeatureEnabled(@"kEnableKeepCaptionOn")) {
        return YES;
    }
    IMP original = YTKACEMiscOriginal(receiver, selector);
    return original != NULL ? ((BOOL (*)(id, SEL))original)(receiver, selector) : NO;
}

static void YTKACECaptionSetter(id receiver, SEL selector, BOOL enabled) {
    IMP original = YTKACEMiscOriginal(receiver, selector);
    if (original == NULL) {
        return;
    }
    BOOL value = enabled;
    if (YTKACEFeatureEnabled(@"kEnableDisableCaptions")) {
        value = NO;
    } else if (YTKACEFeatureEnabled(@"kEnableKeepCaptionOn")) {
        value = YES;
    }
    ((void (*)(id, SEL, BOOL))original)(receiver, selector, value);
}

static id YTKACECaptionTracks(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"kEnableDisableCaptions")) {
        return @[];
    }
    return OriginalCaptionTracks != NULL
        ? ((id (*)(id, SEL))OriginalCaptionTracks)(receiver, selector)
        : nil;
}

static void YTKACEHUDMessage(id receiver, SEL selector, id message) {
    if (YTKACEFeatureEnabled(@"kEnableHideHudeAlerts")) {
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

void YTKACEInstallMiscellaneousHooks(void) {
    if (YTKACEMiscOriginals == nil) {
        YTKACEMiscOriginals = [NSMutableDictionary dictionary];
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

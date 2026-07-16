#import "NavigationVisibility.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <objc/runtime.h>

static IMP OriginalHeaderLogoLayout;
static IMP OriginalLogoViewLayout;
static const void *YTKACENavigationHiddenAssociation = &YTKACENavigationHiddenAssociation;

static void YTKACESetNavigationHidden(UIView *view, BOOL hidden) {
    if (view == nil ||
        [view.accessibilityLabel hasPrefix:@"YTKACE"] ||
        [view.accessibilityIdentifier hasPrefix:@"YTKACE"]) {
        return;
    }
    NSNumber *baseline = objc_getAssociatedObject(
        view,
        YTKACENavigationHiddenAssociation
    );
    if (hidden) {
        if (baseline == nil) {
            objc_setAssociatedObject(view,
                                     YTKACENavigationHiddenAssociation,
                                     @(view.hidden),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.hidden = YES;
        view.userInteractionEnabled = NO;
    } else if (baseline != nil) {
        view.hidden = baseline.boolValue;
        view.userInteractionEnabled = YES;
        objc_setAssociatedObject(view,
                                 YTKACENavigationHiddenAssociation,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static BOOL YTKACENavigationShouldHide(UIView *view) {
    NSString *token = [[NSString stringWithFormat:@"%@ %@ %@",
                        NSStringFromClass(view.class),
                        view.accessibilityIdentifier ?: @"",
                        view.accessibilityLabel ?: @""] lowercaseString];
    if (YTKACEFeatureEnabled(@"kEnableHideAccount") &&
        ([token containsString:@"account"] ||
         [token containsString:@"avatar"] ||
         [token containsString:@"profile"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideSearch") &&
        [token containsString:@"search"]) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideCastButton") &&
        ([token containsString:@"cast"] ||
         [token containsString:@"airplay"] ||
         [token containsString:@"routebutton"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideNotificationBill") &&
        ([token containsString:@"notification"] ||
         [token containsString:@"bell"])) {
        return YES;
    }
    return NO;
}

static void YTKACEApplyNavigationTree(UIView *view) {
    YTKACESetNavigationHidden(view, YTKACENavigationShouldHide(view));
    for (UIView *subview in view.subviews) {
        YTKACEApplyNavigationTree(subview);
    }
}

void YTKACEApplyRightNavigationVisibility(UIView *view) {
    YTKACEApplyNavigationTree(view);
}

static void YTKACEHeaderLogoLayout(UIView *receiver, SEL selector) {
    if (OriginalHeaderLogoLayout != NULL) {
        ((void (*)(id, SEL))OriginalHeaderLogoLayout)(receiver, selector);
    }
    YTKACESetNavigationHidden(
        receiver,
        YTKACEFeatureEnabled(@"kEnableHideYTLogo")
    );
}

static void YTKACELogoViewLayout(UIView *receiver, SEL selector) {
    if (OriginalLogoViewLayout != NULL) {
        ((void (*)(id, SEL))OriginalLogoViewLayout)(receiver, selector);
    }
    YTKACESetNavigationHidden(
        receiver,
        YTKACEFeatureEnabled(@"kEnableHideYTLogo")
    );
}

void YTKACEInstallNavigationVisibilityHooks(void) {
    YTKACEInstallInstanceHook(@"YTHeaderLogoView",
                              @"layoutSubviews",
                              (IMP)YTKACEHeaderLogoLayout,
                              &OriginalHeaderLogoLayout);
    YTKACEInstallInstanceHook(@"YTLogoView",
                              @"layoutSubviews",
                              (IMP)YTKACELogoViewLayout,
                              &OriginalLogoViewLayout);
}

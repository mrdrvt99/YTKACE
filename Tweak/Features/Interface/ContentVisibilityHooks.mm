#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static IMP OriginalDisplayViewDidMove;
static IMP OriginalDisplayViewSetIdentifier;
static IMP OriginalAddSections;
static IMP OriginalSectionControllers;
static const void *YTKACEContentHiddenAssociation = &YTKACEContentHiddenAssociation;
static BOOL YTKACEContentContains(NSString *token,
                                  NSArray<NSString *> *needles);
static id YTKACEContentValue(id object, NSString *key);
static BOOL YTKACESectionIsShortsShelf(id section);

static id YTKACEContentValue(id object, NSString *key) {
    if (object == nil || key.length == 0) {
        return nil;
    }
    @try {
        SEL selector = NSSelectorFromString(key);
        if ([object respondsToSelector:selector]) {
            return ((id (*)(id, SEL))objc_msgSend)(object, selector);
        }
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL YTKACESectionIsShortsShelf(id section) {
    if (section == nil) {
        return NO;
    }
    NSString *description = [[[section description] lowercaseString]
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    if (YTKACEContentContains(description, @[
        @"shorts_shelf_eml", @"shorts_shelf", @"reel_shelf",
        @"shorts_lockup_shelf", @"shortsshelfrenderer",
        @"reelshelfrenderer", @"shortslockupviewmodel"
    ])) {
        return YES;
    }
    NSString *className = NSStringFromClass([section class]).lowercaseString;
    if (![className containsString:@"shelfrenderer"] &&
        ![className containsString:@"richsectionrenderer"]) {
        return NO;
    }
    id content = YTKACEContentValue(section, @"content");
    id list = YTKACEContentValue(content, @"horizontalListRenderer") ?:
        YTKACEContentValue(content, @"richShelfRenderer") ?:
        content;
    NSArray *items = YTKACEContentValue(list, @"itemsArray") ?:
        YTKACEContentValue(list, @"contentsArray");
    for (id item in items) {
        NSString *itemDescription = [[item description] lowercaseString];
        if (YTKACEContentContains(itemDescription, @[
            @"shorts_video_cell", @"reelitemrenderer", @"shortslockup"
        ])) {
            return YES;
        }
    }
    return NO;
}

static NSArray *YTKACEFilteredFeedSections(NSArray *sections) {
    if (!YTKACEFeatureEnabled(@"kEnableHideYTShorts") ||
        ![sections isKindOfClass:NSArray.class]) {
        return sections;
    }
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:sections.count];
    for (id section in sections) {
        if (!YTKACESectionIsShortsShelf(section)) {
            [filtered addObject:section];
        }
    }
    return filtered;
}

static id YTKACESectionControllers(id receiver, SEL selector,
                                   NSArray *sections, id reloadMap) {
    if (OriginalSectionControllers == NULL) return nil;
    return ((id (*)(id, SEL, id, id))OriginalSectionControllers)(
        receiver, selector, YTKACEFilteredFeedSections(sections), reloadMap);
}

static BOOL YTKACEContentContains(NSString *token,
                                  NSArray<NSString *> *needles) {
    for (NSString *needle in needles) {
        if ([token containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

static BOOL YTKACEContentShouldHide(UIView *view, BOOL *hideSuperview) {
    NSString *identifier = [view.accessibilityIdentifier.lowercaseString
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSString *token = [NSString stringWithFormat:@"%@ %@ %@",
                       identifier ?: @"",
                       view.accessibilityLabel.lowercaseString ?: @"",
                       NSStringFromClass(view.class).lowercaseString];

    if (YTKACEFeatureEnabled(YTKACENoAdsKey) &&
        YTKACEContentContains(token, @[
            @"eml_ad_",
            @"eml_expandable_metadata_vpp",
            @"feed_ad_metadata",
            @"paid_content_overlay",
            @"promoted_video",
            @"companion_ad"
        ])) {
        return YES;
    }

    if (YTKACEFeatureEnabled(@"kEnableHideComments")) {
        if ([identifier isEqualToString:@"id_comment_guidelines_text"]) {
            if (hideSuperview != NULL) {
                *hideSuperview = YES;
            }
            return YES;
        }
        if (YTKACEContentContains(token, @[
            @"id_ui_comments_composite_entry_point_teaser",
            @"id_ui_comments_entry_point_teaser",
            @"id_comment_channel_guidelines_bottom_sheet_container",
            @"id_comment_channel_guidelines_entry_banner_container"
        ])) {
            return YES;
        }
    }
    if (YTKACEFeatureEnabled(@"kEnableHideCommentReview") &&
        [identifier isEqualToString:@"id_ui_comments_entry_point_teaser"]) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideCommentGuidlines") &&
        YTKACEContentContains(token, @[
            @"id_comment_guidelines_text",
            @"id_comment_channel_guidelines_bottom_sheet_container",
            @"id_comment_channel_guidelines_entry_banner_container"
        ])) {
        if ([identifier isEqualToString:@"id_comment_guidelines_text"] &&
            hideSuperview != NULL) {
            *hideSuperview = YES;
        }
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableNoTopics") &&
        YTKACEContentContains(token, @[@"topic_chip", @"feed_filter", @"chip_cloud"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableNoSearchedHistory") &&
        YTKACEContentContains(token, @[@"search_history", @"history_suggestion"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableNoPaidPromotion") &&
        YTKACEContentContains(token, @[@"paid_promotion", @"paidpromotion"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableNoPremiumpopup") &&
        YTKACEContentContains(token, @[@"premium_upsell", @"premium_promo"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableNoYTUpdate") &&
        YTKACEContentContains(token, @[@"update_dialog", @"upgrade_dialog"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideSuggestedVideo") &&
        YTKACEContentContains(token, @[@"suggested_video", @"related_video"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideRelatedVideos") &&
        YTKACEContentContains(token, @[
            @"related_video", @"relatedvideo", @"more_videos", @"watch_next"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableDisableContinueWatching") &&
        YTKACEContentContains(token, @[
            @"continue_watching", @"continuewatching", @"resume_watching"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableBlockShortsOverlays") &&
        YTKACEContentContains(token, @[
            @"shorts_pause", @"reel_pause", @"pause_card", @"pausecard",
            @"paused_state_carousel", @"reelpausedstatecarousel"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideShortsProducts") &&
        YTKACEContentContains(token, @[
            @"shorts_product", @"product_sticker", @"shopping_carousel",
            @"shopping_destination", @"tagged_product", @"creator_product"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"kEnableHideShortsStickerAds") &&
        YTKACEContentContains(token, @[
            @"brand_link_sticker", @"product_sticker", @"promoted_sticker",
            @"sponsored_sticker", @"shorts_ads_shopping"
        ])) {
        return YES;
    }
    return NO;
}

static void YTKACEApplyContentVisibility(UIView *view) {
    BOOL hideSuperview = NO;
    BOOL hidden = YTKACEContentShouldHide(view, &hideSuperview);
    UIView *target = hideSuperview ? view.superview : view;
    if (target == nil) {
        return;
    }

    NSNumber *baseline = objc_getAssociatedObject(
        target,
        YTKACEContentHiddenAssociation
    );
    if (hidden) {
        if (baseline == nil) {
            objc_setAssociatedObject(target,
                                     YTKACEContentHiddenAssociation,
                                     @(target.hidden),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        target.hidden = YES;
        target.userInteractionEnabled = NO;
    } else if (baseline != nil) {
        target.hidden = baseline.boolValue;
        target.userInteractionEnabled = YES;
        objc_setAssociatedObject(target,
                                 YTKACEContentHiddenAssociation,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void YTKACEDisplayViewDidMove(UIView *receiver, SEL selector) {
    if (OriginalDisplayViewDidMove != NULL) {
        ((void (*)(id, SEL))OriginalDisplayViewDidMove)(receiver, selector);
    }
    YTKACEApplyContentVisibility(receiver);
}

static void YTKACEDisplayViewSetIdentifier(UIView *receiver,
                                           SEL selector,
                                           NSString *identifier) {
    if (OriginalDisplayViewSetIdentifier != NULL) {
        ((void (*)(id, SEL, id))OriginalDisplayViewSetIdentifier)(
            receiver,
            selector,
            identifier
        );
    }
    YTKACEApplyContentVisibility(receiver);
}

static void YTKACEAddSections(id receiver, SEL selector, NSArray *sections) {
    if (OriginalAddSections != NULL) {
        ((void (*)(id, SEL, id))OriginalAddSections)(
            receiver, selector, YTKACEFilteredFeedSections(sections));
    }
}

void YTKACEInstallContentVisibilityHooks(void) {
    YTKACEInstallInstanceHook(@"_ASDisplayView",
                              @"didMoveToWindow",
                              (IMP)YTKACEDisplayViewDidMove,
                              &OriginalDisplayViewDidMove);
    YTKACEInstallInstanceHook(@"_ASDisplayView",
                              @"setAccessibilityIdentifier:",
                              (IMP)YTKACEDisplayViewSetIdentifier,
                              &OriginalDisplayViewSetIdentifier);
    YTKACEInstallInstanceHook(@"YTInnerTubeCollectionViewController",
                              @"addSectionsFromArray:",
                              (IMP)YTKACEAddSections,
                              &OriginalAddSections);
    YTKACEInstallInstanceHook(@"YTInnerTubeCollectionViewController",
                              @"sectionControllersForSectionRenderers:reloadingSectionControllerByRenderer:",
                              (IMP)YTKACESectionControllers,
                              &OriginalSectionControllers);
}

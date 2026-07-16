#import "Preferences.h"

NSString * const YTKACEMasterEnabledKey = @"YTKACEEnabled";
NSString * const YTKACEOLEDKey = @"kEnableOldDarkTheme";
NSString * const YTKACENoAdsKey = @"kEnableNoAds";
NSString * const YTKACESponsorBlockKey = @"sponsorBlock";
NSString * const YTKACEDownloadKey = @"kEnableDownloadit";
NSString * const YTKACEBackgroundPlaybackKey = @"kEnablePlayInBackgrounds";
NSString * const YTKACEPiPKey = @"kEnableYTKPiP";
NSString * const YTKACESpeedKey = @"kEnableisSpeed";
NSString * const YTKACELoopKey = @"kEnableYTKLoop";

static NSUserDefaults *YTKACEDefaults(void) {
    return NSUserDefaults.standardUserDefaults;
}

void YTKACERegisterDefaults(void) {
    NSDictionary<NSString *, NSString *> *aliases = @{
        @"kEnableHideOverlayQuickAction": @"kEnableHideQuickActions",
        @"kEnableShowOverlaySmart": @"kEnableAlwaysShowPlayPause",
        @"kEnableShowMediaController": @"kEnableAlwaysShowControls",
        @"kEnableHideDarkOverlayBackground": @"kEnableHideDarkOverlay",
        @"kEnableDisablePreviousNextButton": @"kEnableDisablePreviousNext",
        @"kEnablePreviousNextButtonPadding": @"kEnableCompactPreviousNext"
    };
    NSMutableDictionary *legacy =
        [[YTKACEDefaults() dictionaryForKey:@"YTKPlus"] mutableCopy] ?:
        [NSMutableDictionary dictionary];
    for (NSString *key in aliases) {
        if (legacy[key] != nil || [YTKACEDefaults() objectForKey:key] != nil) {
            continue;
        }
        NSString *alias = aliases[key];
        id value = legacy[alias] ?: [YTKACEDefaults() objectForKey:alias];
        if (value != nil) {
            legacy[key] = value;
            [YTKACEDefaults() setObject:value forKey:key];
        }
    }
    [YTKACEDefaults() setObject:legacy forKey:@"YTKPlus"];
    [YTKACEDefaults() registerDefaults:@{
        YTKACEMasterEnabledKey: @YES,
        YTKACENoAdsKey: @YES,
        YTKACEOLEDKey: @NO,
        YTKACEDownloadKey: @NO,
        YTKACEBackgroundPlaybackKey: @NO,
        YTKACEPiPKey: @NO,
        YTKACESpeedKey: @NO,
        YTKACELoopKey: @NO,
        @"kEnableCustomDoubleTapToSkipDuration": @NO,
        @"kEnableCustomDoubleTapToSkipChnges": @10.0,
        @"kSeekDuration": @10.0,
        @"kVolumeSide": @2,
        @"kBrightnessSide": @2,
        @"kEnabledStartupPage": @0,
        @"wiFiPlaybackIndex": @0,
        @"celluarPlaybackIndex": @0,
        @"sbSkipMode": @0,
        @"clearonstartup": @NO,
        @"kHideCreate": @YES,
        @"kHideMusic": @YES,
        @"kHideLive": @YES,
        @"kHideGaming": @YES,
        @"kHideNews": @YES,
        @"kHideSports": @YES,
        @"kTabOrder": @[@"home", @"shorts", @"subscriptions", @"library", @"ytkace"]
    }];
    [YTKACEDefaults() setBool:YES forKey:YTKACEMasterEnabledKey];
    [YTKACEDefaults() removeObjectForKey:@"YTKACEDebugPivot"];
    if ([YTKACEDefaults() boolForKey:@"clearonstartup"]) {
        NSDate *lastClear = [YTKACEDefaults() objectForKey:@"YTKACELastCacheClearDate"];
        if (![lastClear isKindOfClass:NSDate.class] ||
            -lastClear.timeIntervalSinceNow >= 86400.0) {
            NSURL *cache = [YTKACEApplicationSupportDirectory()
                URLByAppendingPathComponent:@"Cache"
                                isDirectory:YES];
            [NSFileManager.defaultManager removeItemAtURL:cache error:nil];
            [YTKACEDefaults() setObject:NSDate.date
                                 forKey:@"YTKACELastCacheClearDate"];
        }
    }
}

BOOL YTKACEMasterEnabled(void) {
    return YES;
}

BOOL YTKACEFeatureEnabled(NSString *key) {
    if (!YTKACEMasterEnabled() || key.length == 0) {
        return NO;
    }
    NSDictionary *legacy = [YTKACEDefaults() dictionaryForKey:@"YTKPlus"];
    id legacyValue = legacy[key];
    if ([legacyValue respondsToSelector:@selector(boolValue)]) {
        return [legacyValue boolValue];
    }
    return [YTKACEDefaults() boolForKey:key];
}

BOOL YTKACESponsorBlockEnabled(void) {
    if (!YTKACEMasterEnabled()) {
        return NO;
    }

    NSDictionary *legacy = [YTKACEDefaults() dictionaryForKey:@"YTKPlus"];
    NSNumber *nestedValue = [legacy[YTKACESponsorBlockKey] isKindOfClass:NSNumber.class]
        ? legacy[YTKACESponsorBlockKey]
        : nil;
    if (nestedValue != nil) {
        return nestedValue.boolValue;
    }
    return [YTKACEDefaults() boolForKey:YTKACESponsorBlockKey];
}

void YTKACESetPreference(NSString *key, BOOL enabled) {
    if (key.length == 0) {
        return;
    }

    if ([key isEqualToString:YTKACEMasterEnabledKey]) {
        [YTKACEDefaults() setBool:YES forKey:key];
        return;
    }
    if (![key isEqualToString:YTKACEMasterEnabledKey]) {
        NSMutableDictionary *legacy =
            [[YTKACEDefaults() dictionaryForKey:@"YTKPlus"] mutableCopy] ?: [NSMutableDictionary dictionary];
        legacy[key] = @(enabled);
        [YTKACEDefaults() setObject:legacy forKey:@"YTKPlus"];
    }
    [YTKACEDefaults() setBool:enabled forKey:key];
}

id YTKACEPreferenceObject(NSString *key) {
    if (key.length == 0) {
        return nil;
    }
    id legacyValue = [YTKACEDefaults() dictionaryForKey:@"YTKPlus"][key];
    return legacyValue ?: [YTKACEDefaults() objectForKey:key];
}

void YTKACESetPreferenceObject(NSString *key, id value) {
    if (key.length == 0) {
        return;
    }
    NSMutableDictionary *legacy =
        [[YTKACEDefaults() dictionaryForKey:@"YTKPlus"] mutableCopy] ?:
        [NSMutableDictionary dictionary];
    if (value == nil) {
        [legacy removeObjectForKey:key];
        [YTKACEDefaults() removeObjectForKey:key];
    } else {
        legacy[key] = value;
        [YTKACEDefaults() setObject:value forKey:key];
    }
    [YTKACEDefaults() setObject:legacy forKey:@"YTKPlus"];
}

NSURL *YTKACEApplicationSupportDirectory(void) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *base = [manager URLsForDirectory:NSApplicationSupportDirectory
                                  inDomains:NSUserDomainMask].firstObject;
    NSURL *directory = [base URLByAppendingPathComponent:@"YTKACE" isDirectory:YES];
    [manager createDirectoryAtURL:directory
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];
    return directory;
}

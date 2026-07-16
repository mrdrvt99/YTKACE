#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/message.h>

static NSString * const YTKACEYouTubeIdentifier = @"com.google.ios.youtube";
static NSString * const YTKACEYouTubeName = @"YouTube";

static IMP OriginalBundleWithIdentifier;
static IMP OriginalBundleIdentifier;
static IMP OriginalInfoDictionary;
static IMP OriginalInfoValue;
static IMP OriginalSSOSetTemporary;
static IMP OriginalSSOConfigurationInit;
static IMP OriginalGroupContainerURL;

static BOOL YTKACEIsSideloaded(void) {
    NSURL *receiptURL = NSBundle.mainBundle.appStoreReceiptURL;
    NSString *path = receiptURL.path;
    return path.length == 0 ||
        ![NSFileManager.defaultManager fileExistsAtPath:path];
}

static NSString *YTKACECurrentAccessGroup(void) {
    static NSString *accessGroup;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *query = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrAccount: @"YTKACEDummyItem",
            (__bridge id)kSecAttrService: @"YTKACEDummyService",
            (__bridge id)kSecReturnAttributes: @YES
        };
        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching(
            (__bridge CFDictionaryRef)query,
            &result
        );
        if (status == errSecItemNotFound) {
            status = SecItemAdd((__bridge CFDictionaryRef)query, &result);
        }
        if (status == errSecDuplicateItem) {
            status = SecItemCopyMatching(
                (__bridge CFDictionaryRef)query,
                &result
            );
        }
        if (status == errSecSuccess && result != NULL) {
            NSDictionary *attributes = CFBridgingRelease(result);
            id value = attributes[(__bridge id)kSecAttrAccessGroup];
            if ([value isKindOfClass:NSString.class]) {
                accessGroup = [value copy];
            }
        } else if (result != NULL) {
            CFRelease(result);
        }
    });
    return accessGroup;
}

static NSString *YTKACEAccessGroup(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return YTKACECurrentAccessGroup();
}

static NSBundle *YTKACEBundleWithIdentifier(id receiver,
                                            SEL selector,
                                            NSString *identifier) {
    if ([identifier isEqualToString:YTKACEYouTubeIdentifier]) {
        return NSBundle.mainBundle;
    }
    return OriginalBundleWithIdentifier == NULL
        ? nil
        : ((id (*)(id, SEL, id))OriginalBundleWithIdentifier)(
            receiver, selector, identifier
        );
}

static NSString *YTKACEBundleIdentifier(NSBundle *receiver, SEL selector) {
    if (receiver == NSBundle.mainBundle) {
        return YTKACEYouTubeIdentifier;
    }
    return OriginalBundleIdentifier == NULL
        ? nil
        : ((id (*)(id, SEL))OriginalBundleIdentifier)(receiver, selector);
}

static NSDictionary *YTKACEInfoDictionary(NSBundle *receiver, SEL selector) {
    NSDictionary *info = OriginalInfoDictionary == NULL
        ? nil
        : ((id (*)(id, SEL))OriginalInfoDictionary)(receiver, selector);
    if (receiver != NSBundle.mainBundle || info == nil) {
        return info;
    }
    NSMutableDictionary *updated = [info mutableCopy];
    updated[@"CFBundleIdentifier"] = YTKACEYouTubeIdentifier;
    updated[@"CFBundleDisplayName"] = YTKACEYouTubeName;
    updated[@"CFBundleName"] = YTKACEYouTubeName;
    return [updated copy];
}

static id YTKACEInfoValue(NSBundle *receiver,
                          SEL selector,
                          NSString *key) {
    if (receiver == NSBundle.mainBundle) {
        if ([key isEqualToString:@"CFBundleIdentifier"]) {
            return YTKACEYouTubeIdentifier;
        }
        if ([key isEqualToString:@"CFBundleDisplayName"] ||
            [key isEqualToString:@"CFBundleName"]) {
            return YTKACEYouTubeName;
        }
    }
    return OriginalInfoValue == NULL
        ? nil
        : ((id (*)(id, SEL, id))OriginalInfoValue)(receiver, selector, key);
}

static BOOL YTKACETrue(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return YES;
}

static BOOL YTKACEFalse(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return NO;
}

static NSString *YTKACEAppName(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return YTKACEYouTubeName;
}

static NSString *YTKACEAppIdentifier(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return YTKACEYouTubeIdentifier;
}

static void YTKACESetTemporaryDisabled(id receiver,
                                       SEL selector,
                                       BOOL disabled) {
    (void)disabled;
    if (OriginalSSOSetTemporary != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalSSOSetTemporary)(
            receiver, selector, NO
        );
    }
}

static id YTKACEConfigurationInit(id receiver,
                                  SEL selector,
                                  id clientID,
                                  id services) {
    id value = OriginalSSOConfigurationInit == NULL
        ? receiver
        : ((id (*)(id, SEL, id, id))OriginalSSOConfigurationInit)(
            receiver, selector, clientID, services
        );
    if (value != nil) {
        @try {
            [value setValue:YTKACEYouTubeName forKey:@"_shortAppName"];
            [value setValue:YTKACEYouTubeIdentifier
                     forKey:@"_applicationIdentifier"];
        } @catch (__unused NSException *exception) {
        }
    }
    return value;
}

static NSURL *YTKACEGroupContainerURL(NSFileManager *receiver,
                                      SEL selector,
                                      NSString *identifier) {
    NSURL *original = OriginalGroupContainerURL == NULL
        ? nil
        : ((id (*)(id, SEL, id))OriginalGroupContainerURL)(
            receiver, selector, identifier
        );
    if (original != nil || ![identifier containsString:@"group."]) {
        return original;
    }
    NSURL *support = [[receiver URLsForDirectory:NSApplicationSupportDirectory
                                        inDomains:NSUserDomainMask] lastObject];
    if (support == nil) {
        return nil;
    }
    NSURL *fallback = [support URLByAppendingPathComponent:@"AppGroup"
                                               isDirectory:YES];
    [receiver createDirectoryAtURL:fallback
       withIntermediateDirectories:YES
                        attributes:nil
                             error:nil];
    return fallback;
}

void YTKACEInstallSideloadCompatibilityHooks(void) {
    if (!YTKACEIsSideloaded()) {
        return;
    }
    YTKACECurrentAccessGroup();

    YTKACEInstallClassHook(@"NSBundle", @"bundleWithIdentifier:",
                           (IMP)YTKACEBundleWithIdentifier,
                           &OriginalBundleWithIdentifier);
    YTKACEInstallInstanceHook(@"NSBundle", @"bundleIdentifier",
                              (IMP)YTKACEBundleIdentifier,
                              &OriginalBundleIdentifier);
    YTKACEInstallInstanceHook(@"NSBundle", @"infoDictionary",
                              (IMP)YTKACEInfoDictionary,
                              &OriginalInfoDictionary);
    YTKACEInstallInstanceHook(@"NSBundle", @"objectForInfoDictionaryKey:",
                              (IMP)YTKACEInfoValue,
                              &OriginalInfoValue);

    YTKACEInstallClassHook(@"YTVersionUtils", @"appName",
                           (IMP)YTKACEAppName, NULL);
    YTKACEInstallClassHook(@"YTVersionUtils", @"appID",
                           (IMP)YTKACEAppIdentifier, NULL);
    YTKACEInstallInstanceHook(@"SSOConfiguration", @"shouldEnableSafariSignIn",
                              (IMP)YTKACETrue, NULL);
    YTKACEInstallInstanceHook(@"SSOConfiguration", @"temporarilyDisableSafariSignIn",
                              (IMP)YTKACEFalse, NULL);
    YTKACEInstallInstanceHook(@"SSOConfiguration", @"setTemporarilyDisableSafariSignIn:",
                              (IMP)YTKACESetTemporaryDisabled,
                              &OriginalSSOSetTemporary);
    YTKACEInstallInstanceHook(@"SSOConfiguration",
                              @"initWithClientID:supportedAccountServices:",
                              (IMP)YTKACEConfigurationInit,
                              &OriginalSSOConfigurationInit);

    YTKACEInstallClassHook(@"SSOKeychainHelper", @"accessGroup",
                           (IMP)YTKACEAccessGroup, NULL);
    YTKACEInstallClassHook(@"SSOKeychainHelper", @"sharedAccessGroup",
                           (IMP)YTKACEAccessGroup, NULL);
    YTKACEInstallClassHook(@"SSOKeychainCore", @"accessGroup",
                           (IMP)YTKACEAccessGroup, NULL);
    YTKACEInstallClassHook(@"SSOKeychainCore", @"sharedAccessGroup",
                           (IMP)YTKACEAccessGroup, NULL);
    YTKACEInstallInstanceHook(@"UICKeyChainStore", @"accessGroup",
                              (IMP)YTKACEAccessGroup, NULL);

    YTKACEInstallInstanceHook(@"NSFileManager",
                              @"containerURLForSecurityApplicationGroupIdentifier:",
                              (IMP)YTKACEGroupContainerURL,
                              &OriginalGroupContainerURL);
    YTKACEInstallClassHook(@"GULAppEnvironmentUtil", @"isFromAppStore",
                           (IMP)YTKACETrue, NULL);
    YTKACEInstallClassHook(@"APMAEU", @"isFAS",
                           (IMP)YTKACETrue, NULL);
    YTKACEInstallClassHook(@"SSOClientLogin", @"defaultSourceString",
                           (IMP)YTKACEAppIdentifier, NULL);
}

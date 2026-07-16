#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../Downloads/DownloadLog.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdlib.h>

static BOOL YTKACECastYes(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return YES;
}

static BOOL YTKACECastNo(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return NO;
}

static NSInteger YTKACECastAllowedStatus(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    return 1;
}

static void YTKACESkipLocalNetworkPage(id receiver,
                                       SEL selector,
                                       id completion) {
    (void)receiver;
    (void)selector;
    YTKACEDownloadLog(@"cast", @"permission page bypassed");
    YTKACEStartCastDiscovery();
    if (completion == nil) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            ((void (^)(BOOL))completion)(YES);
        } @catch (__unused NSException *exception) {
            YTKACEDownloadLog(@"cast", @"permission completion failed");
        }
    });
}

static BOOL YTKACECastClass(Class cls) {
    NSString *name = NSStringFromClass(cls);
    return [name hasPrefix:@"MDX"] || [name hasPrefix:@"YT"] ||
        [name hasPrefix:@"CADP"] || [name hasPrefix:@"GCK"];
}

static void YTKACEInstallDirectCastHooks(void) {
    int classCapacity = objc_getClassList(NULL, 0);
    if (classCapacity <= 0) return;
    Class *classes = (__unsafe_unretained Class *)calloc(
        (size_t)classCapacity,
        sizeof(Class)
    );
    if (classes == NULL) return;
    int classCount = objc_getClassList(classes, classCapacity);
    if (classCount > classCapacity) classCount = classCapacity;
    SEL yesSelectors[] = {
        NSSelectorFromString(@"hasSufficientLocalNetworkPermissions"),
        NSSelectorFromString(@"isLocalNetworkPermissionAllowed"),
        NSSelectorFromString(@"wasLocalNetworkPermissionAllowed")
    };
    SEL noSelectors[] = {
        NSSelectorFromString(@"shouldShowLocalNetworkPermissionPrompt"),
        NSSelectorFromString(@"shouldPresentLocalNetworkAccessPermissionDialog")
    };
    SEL statusSelectors[] = {
        NSSelectorFromString(@"lastKnownPermissionsStatus"),
        NSSelectorFromString(@"localNetworkPermissionsStatus")
    };
    for (int classIndex = 0; classIndex < classCount; classIndex++) {
        Class cls = classes[classIndex];
        if (cls == Nil || !YTKACECastClass(cls)) continue;
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
            Method method = methods[methodIndex];
            SEL selector = method_getName(method);
            for (size_t index = 0;
                 index < sizeof(yesSelectors) / sizeof(yesSelectors[0]);
                 index++) {
                if (selector == yesSelectors[index]) {
                    method_setImplementation(method, (IMP)YTKACECastYes);
                }
            }
            for (size_t index = 0;
                 index < sizeof(noSelectors) / sizeof(noSelectors[0]);
                 index++) {
                if (selector == noSelectors[index]) {
                    method_setImplementation(method, (IMP)YTKACECastNo);
                }
            }
            for (size_t index = 0;
                 index < sizeof(statusSelectors) / sizeof(statusSelectors[0]);
                 index++) {
                if (selector == statusSelectors[index]) {
                    method_setImplementation(method, (IMP)YTKACECastAllowedStatus);
                }
            }
        }
        free(methods);
    }
    free(classes);
}

static void YTKACERefreshCastHooks(void) {
    YTKACEInstallDirectCastHooks();
    YTKACEInstallInstanceHook(@"MDXRoutePresentationController",
                              @"hasSufficientLocalNetworkPermissions",
                              (IMP)YTKACECastYes,
                              NULL);
    YTKACEInstallInstanceHook(@"MDXLocalNetworkPermissions",
                              @"lastKnownPermissionsStatus",
                              (IMP)YTKACECastAllowedStatus,
                              NULL);
    YTKACEInstallInstanceHook(@"MDXLocalNetworkPermissions",
                              @"isAuthorized",
                              (IMP)YTKACECastYes,
                              NULL);
    YTKACEInstallInstanceHook(@"MDXLocalStorage",
                              @"localNetworkPermissionsStatus",
                              (IMP)YTKACECastAllowedStatus,
                              NULL);
    YTKACEInstallInstanceHook(
        @"MDXPermissionsController",
        @"showLocalNetworkPermissionsRequiredPageWithCompletion:",
        (IMP)YTKACESkipLocalNetworkPage,
        NULL
    );
    YTKACEInstallInstanceHook(@"CADPLocalNetworkPermissionInfo",
                              @"isLocalNetworkPermissionAllowed",
                              (IMP)YTKACECastYes,
                              NULL);
    YTKACEInstallInstanceHook(@"CADPLocalNetworkPermissionInfo",
                              @"wasLocalNetworkPermissionAllowed",
                              (IMP)YTKACECastYes,
                              NULL);
    YTKACEInstallInstanceHook(
        @"CADPLocalNetworkPermissionInfo",
        @"shouldPresentLocalNetworkAccessPermissionDialog",
        (IMP)YTKACECastNo,
        NULL
    );
    YTKACEInstallInstanceHook(
        @"YTBAMediaHubUiDeviceItemsResult",
        @"shouldShowLocalNetworkPermissionPrompt",
        (IMP)YTKACECastNo,
        NULL
    );
}

void YTKACEStartCastDiscovery(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class contextClass = NSClassFromString(@"GCKCastContext");
            SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
            if (contextClass == Nil ||
                ![contextClass respondsToSelector:sharedSelector]) {
                YTKACEDownloadLog(@"cast", @"context unavailable");
                return;
            }
            id context = ((id (*)(id, SEL))objc_msgSend)(contextClass,
                                                         sharedSelector);
            SEL managerSelector = NSSelectorFromString(@"discoveryManager");
            if (context == nil || ![context respondsToSelector:managerSelector]) {
                YTKACEDownloadLog(@"cast", @"manager unavailable");
                return;
            }
            id manager = ((id (*)(id, SEL))objc_msgSend)(context,
                                                         managerSelector);
            SEL startSelector = NSSelectorFromString(@"startDiscovery");
            if (manager != nil && [manager respondsToSelector:startSelector]) {
                ((void (*)(id, SEL))objc_msgSend)(manager, startSelector);
                YTKACEDownloadLog(@"cast", @"discovery started");
                dispatch_after(
                    dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                    dispatch_get_main_queue(), ^{
                        SEL countSelector = NSSelectorFromString(@"deviceCount");
                        if ([manager respondsToSelector:countSelector]) {
                            NSUInteger count = ((NSUInteger (*)(id, SEL))objc_msgSend)(
                                manager,
                                countSelector
                            );
                            YTKACEDownloadLog(@"cast", @"devices=%lu",
                                             (unsigned long)count);
                        }
                    }
                );
            }
        } @catch (__unused NSException *exception) {
            YTKACEDownloadLog(@"cast", @"discovery exception");
        }
    });
}

void YTKACEInstallCastCompatibilityHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        YTKACERefreshCastHooks();

        [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *notification) {
                        YTKACERefreshCastHooks();
                        dispatch_after(
                            dispatch_time(DISPATCH_TIME_NOW,
                                          500 * NSEC_PER_MSEC),
                            dispatch_get_main_queue(), ^{
                                YTKACEStartCastDiscovery();
                            }
                        );
                    }];
        for (NSNumber *delay in @[@0.5, @2.0, @4.0]) {
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                              (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    YTKACERefreshCastHooks();
                    YTKACEStartCastDiscovery();
                }
            );
        }
    });
}

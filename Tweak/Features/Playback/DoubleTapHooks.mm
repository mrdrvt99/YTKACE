#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <math.h>
#import <objc/runtime.h>
#import <string.h>

static NSMutableDictionary<NSString *, NSValue *> *YTKACEDoubleTapOriginals;

static NSValue *YTKACEDoubleTapValueForIMP(IMP implementation) {
    return [NSValue value:&implementation withObjCType:@encode(IMP)];
}

static IMP YTKACEDoubleTapIMPFromValue(NSValue *value) {
    IMP implementation = NULL;
    [value getValue:&implementation];
    return implementation;
}

static double YTKACEDoubleTapValue(void) {
    double value = [NSUserDefaults.standardUserDefaults
        doubleForKey:@"kEnableCustomDoubleTapToSkipChnges"];
    return MIN(60.0, MAX(5.0, value > 0.0 ? value : 10.0));
}

static NSString *YTKACEDoubleTapKey(Class cls,
                                    BOOL classMethod,
                                    SEL selector) {
    return [NSString stringWithFormat:@"%@|%@|%@",
            NSStringFromClass(cls),
            classMethod ? @"+" : @"-",
            NSStringFromSelector(selector)];
}

static IMP YTKACEDoubleTapOriginal(id receiver, SEL selector) {
    BOOL classMethod = object_isClass(receiver);
    Class cls = classMethod ? (Class)receiver : [receiver class];
    while (cls != Nil) {
        NSValue *value =
            YTKACEDoubleTapOriginals[YTKACEDoubleTapKey(cls, classMethod, selector)];
        if (value != nil) {
            return YTKACEDoubleTapIMPFromValue(value);
        }
        cls = class_getSuperclass(cls);
    }
    return NULL;
}

static double YTKACEDoubleTapDoubleNoArg(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"kEnableCustomDoubleTapToSkipDuration")) {
        return YTKACEDoubleTapValue();
    }
    IMP original = YTKACEDoubleTapOriginal(receiver, selector);
    return original == NULL
        ? 10.0
        : ((double (*)(id, SEL))original)(receiver, selector);
}

static float YTKACEDoubleTapFloatNoArg(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"kEnableCustomDoubleTapToSkipDuration")) {
        return (float)YTKACEDoubleTapValue();
    }
    IMP original = YTKACEDoubleTapOriginal(receiver, selector);
    return original == NULL
        ? 10.0f
        : ((float (*)(id, SEL))original)(receiver, selector);
}

static NSInteger YTKACEDoubleTapIntegerNoArg(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"kEnableCustomDoubleTapToSkipDuration")) {
        return (NSInteger)llround(YTKACEDoubleTapValue());
    }
    IMP original = YTKACEDoubleTapOriginal(receiver, selector);
    return original == NULL
        ? 10
        : ((NSInteger (*)(id, SEL))original)(receiver, selector);
}

static double YTKACEDoubleTapDouble(id receiver,
                                    SEL selector,
                                    id __unsafe_unretained config) {
    if (YTKACEFeatureEnabled(@"kEnableCustomDoubleTapToSkipDuration")) {
        return YTKACEDoubleTapValue();
    }
    IMP original = YTKACEDoubleTapOriginal(receiver, selector);
    return original == NULL
        ? 10.0
        : ((double (*)(id, SEL, id))original)(receiver, selector, config);
}

static float YTKACEDoubleTapFloat(id receiver,
                                  SEL selector,
                                  id __unsafe_unretained config) {
    if (YTKACEFeatureEnabled(@"kEnableCustomDoubleTapToSkipDuration")) {
        return (float)YTKACEDoubleTapValue();
    }
    IMP original = YTKACEDoubleTapOriginal(receiver, selector);
    return original == NULL
        ? 10.0f
        : ((float (*)(id, SEL, id))original)(receiver, selector, config);
}

static NSInteger YTKACEDoubleTapInteger(id receiver,
                                        SEL selector,
                                        id __unsafe_unretained config) {
    if (YTKACEFeatureEnabled(@"kEnableCustomDoubleTapToSkipDuration")) {
        return (NSInteger)llround(YTKACEDoubleTapValue());
    }
    IMP original = YTKACEDoubleTapOriginal(receiver, selector);
    return original == NULL
        ? 10
        : ((NSInteger (*)(id, SEL, id))original)(receiver, selector, config);
}

static void YTKACEInstallDoubleTapHook(NSString *className,
                                      NSString *selectorName,
                                      BOOL classMethod) {
    Class cls = NSClassFromString(className);
    Class target = classMethod ? object_getClass(cls) : cls;
    Method method = class_getInstanceMethod(
        target,
        NSSelectorFromString(selectorName)
    );
    if (method == NULL) {
        return;
    }

    char returnType[16] = {};
    method_getReturnType(method, returnType, sizeof(returnType));
    BOOL takesArgument = [selectorName containsString:@":"];
    IMP replacement = NULL;
    if (strcmp(returnType, @encode(double)) == 0) {
        replacement = takesArgument
            ? (IMP)YTKACEDoubleTapDouble
            : (IMP)YTKACEDoubleTapDoubleNoArg;
    } else if (strcmp(returnType, @encode(float)) == 0) {
        replacement = takesArgument
            ? (IMP)YTKACEDoubleTapFloat
            : (IMP)YTKACEDoubleTapFloatNoArg;
    } else if (strcmp(returnType, @encode(NSInteger)) == 0 ||
               strcmp(returnType, @encode(NSUInteger)) == 0 ||
               strcmp(returnType, @encode(int)) == 0) {
        replacement = takesArgument
            ? (IMP)YTKACEDoubleTapInteger
            : (IMP)YTKACEDoubleTapIntegerNoArg;
    }
    if (replacement == NULL) {
        return;
    }

    IMP original = NULL;
    BOOL installed = classMethod
        ? YTKACEInstallClassHook(className, selectorName, replacement, &original)
        : YTKACEInstallInstanceHook(className, selectorName, replacement, &original);
    if (installed && original != NULL) {
        NSString *key =
            YTKACEDoubleTapKey(cls, classMethod, NSSelectorFromString(selectorName));
        if (YTKACEDoubleTapOriginals[key] == nil) {
            YTKACEDoubleTapOriginals[key] =
                YTKACEDoubleTapValueForIMP(original);
        }
    }
}

void YTKACEInstallDoubleTapHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        YTKACEDoubleTapOriginals = [NSMutableDictionary dictionary];
    });

    YTKACEInstallDoubleTapHook(@"YTSettings", @"doubleTapSeekDuration", NO);
    YTKACEInstallDoubleTapHook(@"YTUserDefaults", @"doubleTapSeekDuration", NO);
    for (NSString *selector in @[
        @"doubleTapSeekDurationForVideoPlayerOverlayConfig:",
        @"doubleTapSeekIntervalForVideoPlayerOverlayConfig:"
    ]) {
        YTKACEInstallDoubleTapHook(
            @"YTVideoPlayerOverlayConfigTransformer",
            selector,
            NO
        );
        YTKACEInstallDoubleTapHook(
            @"YTVideoPlayerOverlayConfigTransformer",
            selector,
            YES
        );
    }
}

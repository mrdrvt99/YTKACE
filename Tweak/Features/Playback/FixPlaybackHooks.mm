#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <Foundation/Foundation.h>
#import <objc/message.h>

static NSString * const YTKACEFixPlaybackKey = @"kEnablefixvideoplayback";

static IMP OriginalIosguardEnable;
static IMP OriginalHasIosguardEnable;
static IMP OriginalHeartbeatNonFatal;
static IMP OriginalHasHeartbeatNonFatal;
static IMP OriginalRequestIosguardAfter;
static IMP OriginalHasRequestIosguardAfter;
static IMP OriginalRequiresAttestation;
static IMP OriginalHasRequiresAttestation;
static IMP OriginalStopHeartbeat;
static IMP OriginalHasStopHeartbeat;
static IMP OriginalAuthenticationMismatch;
static IMP OriginalHasAuthenticationMismatch;
static IMP OriginalHasPlayabilityStatus;
static IMP OriginalPlayabilityStatus;
static IMP OriginalHaltIfNeeded;
static IMP OriginalTransitionIfNeeded;
static IMP OriginalHandleHeartbeatResponse;
static IMP OriginalHaltPlaybackWithError;
static IMP OriginalSkipOnPlayabilityError;
static IMP OriginalHasSkipOnPlayabilityError;
static IMP OriginalCannotPlay;
static IMP OriginalCannotPlayWithError;
static IMP OriginalCannotPlayWithStatus;
static IMP OriginalShowErrorLong;
static IMP OriginalShowErrorMessage;
static IMP OriginalUpdateErrorState;

static BOOL FixEnabled(void) {
    return YTKACEFeatureEnabled(YTKACEFixPlaybackKey);
}

static BOOL YTKACECallBool(IMP fn, id r, SEL s) {
    return fn != NULL && ((BOOL (*)(id, SEL))fn)(r, s);
}

static id YTKACECallObject(IMP fn, id r, SEL s) {
    return fn == NULL ? nil : ((id (*)(id, SEL))fn)(r, s);
}

static BOOL YTKACEIosguardEnable(id r, SEL s) {
    return FixEnabled() ? NO : YTKACECallBool(OriginalIosguardEnable, r, s);
}
static BOOL YTKACEHasIosguardEnable(id r, SEL s) {
    return FixEnabled() ? NO : YTKACECallBool(OriginalHasIosguardEnable, r, s);
}
static BOOL YTKACERequestIosguardAfter(id r, SEL s) {
    return FixEnabled() ? NO : YTKACECallBool(OriginalRequestIosguardAfter, r, s);
}
static BOOL YTKACEHasRequestIosguardAfter(id r, SEL s) {
    return FixEnabled() ? NO : YTKACECallBool(OriginalHasRequestIosguardAfter, r, s);
}
static BOOL YTKACERequiresAttestation(id r, SEL s) {
    return FixEnabled() ? NO : YTKACECallBool(OriginalRequiresAttestation, r, s);
}
static BOOL YTKACEHasRequiresAttestation(id r, SEL s) {
    return FixEnabled() ? NO : YTKACECallBool(OriginalHasRequiresAttestation, r, s);
}

static BOOL YTKACEHeartbeatNonFatal(id r, SEL s) {
    return FixEnabled() ? YES : YTKACECallBool(OriginalHeartbeatNonFatal, r, s);
}
static BOOL YTKACEHasHeartbeatNonFatal(id r, SEL s) {
    return FixEnabled() ? YES : YTKACECallBool(OriginalHasHeartbeatNonFatal, r, s);
}
static BOOL YTKACEStopHeartbeat(id r, SEL s) {
    return FixEnabled() ? NO : YTKACECallBool(OriginalStopHeartbeat, r, s);
}
static BOOL YTKACEHasStopHeartbeat(id r, SEL s) {
    return FixEnabled() ? NO : YTKACECallBool(OriginalHasStopHeartbeat, r, s);
}
static BOOL YTKACEAuthenticationMismatch(id r, SEL s) {
    return FixEnabled() ? NO : YTKACECallBool(OriginalAuthenticationMismatch, r, s);
}
static BOOL YTKACEHasAuthenticationMismatch(id r, SEL s) {
    return FixEnabled() ? NO : YTKACECallBool(OriginalHasAuthenticationMismatch, r, s);
}
static BOOL YTKACEHasPlayabilityStatus(id r, SEL s) {
    return FixEnabled() ? NO : YTKACECallBool(OriginalHasPlayabilityStatus, r, s);
}
static id YTKACEPlayabilityStatus(id r, SEL s) {
    return FixEnabled() ? nil : YTKACECallObject(OriginalPlayabilityStatus, r, s);
}

static void YTKACEHaltIfNeeded(id r, SEL s) {
    if (FixEnabled()) return;
    if (OriginalHaltIfNeeded) ((void (*)(id, SEL))OriginalHaltIfNeeded)(r, s);
}
static void YTKACETransitionIfNeeded(id r, SEL s) {
    if (FixEnabled()) return;
    if (OriginalTransitionIfNeeded) ((void (*)(id, SEL))OriginalTransitionIfNeeded)(r, s);
}
static void YTKACEHandleHeartbeatResponse(id r, SEL s, id resp, id req) {
    if (FixEnabled()) return;
    if (OriginalHandleHeartbeatResponse) {
        ((void (*)(id, SEL, id, id))OriginalHandleHeartbeatResponse)(r, s, resp, req);
    }
}
static void YTKACEHaltPlaybackWithError(id r, SEL s, id err, id ctl) {
    if (FixEnabled()) return;
    if (OriginalHaltPlaybackWithError) {
        ((void (*)(id, SEL, id, id))OriginalHaltPlaybackWithError)(r, s, err, ctl);
    }
}

static BOOL YTKACESkipOnPlayabilityError(id r, SEL s) {
    return FixEnabled() ? YES : YTKACECallBool(OriginalSkipOnPlayabilityError, r, s);
}
static BOOL YTKACEHasSkipOnPlayabilityError(id r, SEL s) {
    return FixEnabled() ? YES : YTKACECallBool(OriginalHasSkipOnPlayabilityError, r, s);
}

static void YTKACECannotPlay(id r, SEL s) {
    if (FixEnabled()) return;
    if (OriginalCannotPlay) ((void (*)(id, SEL))OriginalCannotPlay)(r, s);
}
static void YTKACECannotPlayWithError(id r, SEL s, id err) {
    if (FixEnabled()) return;
    if (OriginalCannotPlayWithError) {
        ((void (*)(id, SEL, id))OriginalCannotPlayWithError)(r, s, err);
    }
}
static void YTKACECannotPlayWithStatus(id r, SEL s, id status) {
    if (FixEnabled()) return;
    if (OriginalCannotPlayWithStatus) {
        ((void (*)(id, SEL, id))OriginalCannotPlayWithStatus)(r, s, status);
    }
}

static void YTKACEShowErrorLong(id r, SEL s,
                                id reason, id sub, id learn,
                                BOOL retry, BOOL retryMsg, BOOL bg) {
    if (FixEnabled()) return;
    if (OriginalShowErrorLong) {
        ((void (*)(id, SEL, id, id, id, BOOL, BOOL, BOOL))OriginalShowErrorLong)(
            r, s, reason, sub, learn, retry, retryMsg, bg);
    }
}
static void YTKACEShowErrorMessage(id r, SEL s,
                                   id message,
                                   BOOL retry, BOOL retryMsg, BOOL bg) {
    if (FixEnabled()) return;
    if (OriginalShowErrorMessage) {
        ((void (*)(id, SEL, id, BOOL, BOOL, BOOL))OriginalShowErrorMessage)(
            r, s, message, retry, retryMsg, bg);
    }
}
static void YTKACEUpdateErrorState(id r, SEL s,
                                   BOOL retry, BOOL retryMsg, BOOL bg) {
    if (FixEnabled()) return;
    if (OriginalUpdateErrorState) {
        ((void (*)(id, SEL, BOOL, BOOL, BOOL))OriginalUpdateErrorState)(
            r, s, retry, retryMsg, bg);
    }
}

static void InstallBool(NSString *cls, NSString *sel, IMP repl, IMP *orig) {
    if (!YTKACEInstallInstanceHook(cls, sel, repl, orig)) {
        YTKACEAddInstanceMethod(cls, sel, repl, "B@:");
    }
}
static void InstallObj(NSString *cls, NSString *sel, IMP repl, IMP *orig) {
    if (!YTKACEInstallInstanceHook(cls, sel, repl, orig)) {
        YTKACEAddInstanceMethod(cls, sel, repl, "@@:");
    }
}

void YTKACEInstallFixPlaybackHooks(void) {
    InstallBool(@"YTIIosPlayerAttestationConfig", @"iosguardEnable",
                (IMP)YTKACEIosguardEnable, &OriginalIosguardEnable);
    InstallBool(@"YTIIosPlayerAttestationConfig", @"hasIosguardEnable",
                (IMP)YTKACEHasIosguardEnable, &OriginalHasIosguardEnable);

    InstallBool(@"YTIIosPlayerConfig", @"heartbeatPolicyErrorIsNonFatal",
                (IMP)YTKACEHeartbeatNonFatal, &OriginalHeartbeatNonFatal);
    InstallBool(@"YTIIosPlayerConfig", @"hasHeartbeatPolicyErrorIsNonFatal",
                (IMP)YTKACEHasHeartbeatNonFatal, &OriginalHasHeartbeatNonFatal);
    InstallBool(@"YTIIosPlayerConfig", @"requestIosguardDataAfterPlaybackStarts",
                (IMP)YTKACERequestIosguardAfter, &OriginalRequestIosguardAfter);
    InstallBool(@"YTIIosPlayerConfig", @"hasRequestIosguardDataAfterPlaybackStarts",
                (IMP)YTKACEHasRequestIosguardAfter, &OriginalHasRequestIosguardAfter);

    InstallBool(@"YTIHeartbeatAttestationConfig", @"requiresAttestation",
                (IMP)YTKACERequiresAttestation, &OriginalRequiresAttestation);
    InstallBool(@"YTIHeartbeatAttestationConfig", @"hasRequiresAttestation",
                (IMP)YTKACEHasRequiresAttestation, &OriginalHasRequiresAttestation);

    InstallBool(@"YTIHeartbeatResponse", @"stopHeartbeat",
                (IMP)YTKACEStopHeartbeat, &OriginalStopHeartbeat);
    InstallBool(@"YTIHeartbeatResponse", @"hasStopHeartbeat",
                (IMP)YTKACEHasStopHeartbeat, &OriginalHasStopHeartbeat);
    InstallBool(@"YTIHeartbeatResponse", @"authenticationMismatch",
                (IMP)YTKACEAuthenticationMismatch, &OriginalAuthenticationMismatch);
    InstallBool(@"YTIHeartbeatResponse", @"hasAuthenticationMismatch",
                (IMP)YTKACEHasAuthenticationMismatch, &OriginalHasAuthenticationMismatch);
    InstallBool(@"YTIHeartbeatResponse", @"hasPlayabilityStatus",
                (IMP)YTKACEHasPlayabilityStatus, &OriginalHasPlayabilityStatus);
    InstallObj(@"YTIHeartbeatResponse", @"playabilityStatus",
               (IMP)YTKACEPlayabilityStatus, &OriginalPlayabilityStatus);

    YTKACEInstallInstanceHook(@"YTSingleVideoHeartbeatController", @"haltIfNeeded",
                              (IMP)YTKACEHaltIfNeeded, &OriginalHaltIfNeeded);
    YTKACEInstallInstanceHook(@"YTSingleVideoHeartbeatController", @"transitionIfNeeded",
                              (IMP)YTKACETransitionIfNeeded, &OriginalTransitionIfNeeded);
    YTKACEInstallInstanceHook(@"YTSingleVideoHeartbeatController",
                              @"handleResponse:forRequest:",
                              (IMP)YTKACEHandleHeartbeatResponse,
                              &OriginalHandleHeartbeatResponse);
    YTKACEInstallInstanceHook(@"YTPlaybackHeartbeatController",
                              @"haltPlaybackWithError:forHeartbeatController:",
                              (IMP)YTKACEHaltPlaybackWithError,
                              &OriginalHaltPlaybackWithError);

    InstallBool(@"YTIPlayabilityErrorSkipConfig", @"skipOnPlayabilityError",
                (IMP)YTKACESkipOnPlayabilityError, &OriginalSkipOnPlayabilityError);
    InstallBool(@"YTIPlayabilityErrorSkipConfig", @"hasSkipOnPlayabilityError",
                (IMP)YTKACEHasSkipOnPlayabilityError, &OriginalHasSkipOnPlayabilityError);

    YTKACEInstallInstanceHook(@"MDXPlaybackController", @"playerCannotPlayThisVideo",
                              (IMP)YTKACECannotPlay, &OriginalCannotPlay);
    YTKACEInstallInstanceHook(@"MDXPlaybackController",
                              @"playerCannotPlayThisVideoWithError:",
                              (IMP)YTKACECannotPlayWithError,
                              &OriginalCannotPlayWithError);
    YTKACEInstallInstanceHook(@"MDXPlaybackController",
                              @"playerCannotPlayThisVideoWithPlayabilityStatus:",
                              (IMP)YTKACECannotPlayWithStatus,
                              &OriginalCannotPlayWithStatus);

    YTKACEInstallInstanceHook(@"YTErrorPlayerOverlayView",
        @"showErrorWithReason:subreason:learnMore:allowTapToRetry:showTapToRetryMessage:showErrorBackground:",
        (IMP)YTKACEShowErrorLong, &OriginalShowErrorLong);
    YTKACEInstallInstanceHook(@"YTErrorPlayerOverlayView",
        @"showErrorWithMessage:allowTapToRetry:showTapToRetryMessage:showErrorBackground:",
        (IMP)YTKACEShowErrorMessage, &OriginalShowErrorMessage);
    YTKACEInstallInstanceHook(@"YTErrorPlayerOverlayView",
        @"updateStateForNewErrorWithAllowTapToRetry:showTapToRetryMessage:showErrorBackground:",
        (IMP)YTKACEUpdateErrorState, &OriginalUpdateErrorState);
}

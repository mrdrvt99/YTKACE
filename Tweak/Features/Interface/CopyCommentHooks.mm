#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static IMP OriginalCommentNodeDidLoad;
static IMP OriginalCommentViewSetNode;
static IMP OriginalCommentUIViewDidMove;
static const void *YTKACECommentTextAssociation = &YTKACECommentTextAssociation;
static const void *YTKACECommentNodeAssociation = &YTKACECommentNodeAssociation;
static const void *YTKACECommentGestureAssociation = &YTKACECommentGestureAssociation;

static id YTKACEObjectMessage(id receiver, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return receiver != nil && [receiver respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector) : nil;
}

static NSString *YTKACECleanCommentText(NSString *text) {
    if (![text isKindOfClass:NSString.class]) {
        return nil;
    }
    NSString *cleaned = [text stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return cleaned.length == 0 ? nil : cleaned;
}

static BOOL YTKACEIsCommentToken(NSString *token) {
    NSString *lower = token.lowercaseString;
    return [lower containsString:@"comment"] ||
           [lower containsString:@"id_ui_comment_cell"];
}

static BOOL YTKACEIsCommentTextToken(NSString *token) {
    NSString *lower = token.lowercaseString;
    return [lower containsString:@"comment_content"] ||
           [lower containsString:@"comment_text"] ||
           [lower containsString:@"comment_body"];
}

static NSString *YTKACECommentTextInNode(id node, NSUInteger depth) {
    if (node == nil || depth > 16) {
        return nil;
    }
    NSString *stored = YTKACECleanCommentText(
        objc_getAssociatedObject(node, YTKACECommentTextAssociation)
    );
    if (stored.length != 0) {
        return stored;
    }
    NSString *identifier = YTKACEObjectMessage(node, @"accessibilityIdentifier");
    NSString *description = [node description];
    id attributedText = YTKACEObjectMessage(node, @"attributedText");
    NSString *text = YTKACECleanCommentText(
        YTKACEObjectMessage(attributedText, @"string")
    );
    if (text.length != 0 && YTKACEIsCommentTextToken(
        [NSString stringWithFormat:@"%@ %@", identifier ?: @"", description ?: @""])) {
        return text;
    }
    NSArray *children = YTKACEObjectMessage(node, @"subnodes");
    if (![children isKindOfClass:NSArray.class]) {
        children = YTKACEObjectMessage(node, @"children");
    }
    for (id child in children) {
        NSString *candidate = YTKACECommentTextInNode(child, depth + 1);
        if (candidate.length != 0) {
            return candidate;
        }
    }
    return nil;
}

static NSString *YTKACETextFromView(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) {
        return YTKACECleanCommentText(((UILabel *)view).text);
    }
    if ([view isKindOfClass:UITextView.class]) {
        return YTKACECleanCommentText(((UITextView *)view).text);
    }
    NSString *label = YTKACECleanCommentText(view.accessibilityLabel);
    return [view isKindOfClass:UIControl.class] ? nil : label;
}

static NSString *YTKACECommentTextInView(UIView *view, BOOL exact,
                                         NSUInteger depth) {
    if (view == nil || depth > 16) {
        return nil;
    }
    NSString *stored = YTKACECleanCommentText(
        objc_getAssociatedObject(view, YTKACECommentTextAssociation)
    );
    if (stored.length != 0) {
        return stored;
    }
    NSString *token = [NSString stringWithFormat:@"%@ %@ %@",
        view.accessibilityIdentifier ?: @"",
        NSStringFromClass(view.class) ?: @"",
        [view description] ?: @""];
    NSString *ownText = YTKACETextFromView(view);
    if (ownText.length != 0 && (!exact || YTKACEIsCommentTextToken(token))) {
        return ownText;
    }
    id node = objc_getAssociatedObject(view, YTKACECommentNodeAssociation);
    if (node == nil) {
        node = YTKACEObjectMessage(view, @"keepalive_node");
    }
    NSString *nodeText = YTKACECommentTextInNode(node, 0);
    if (nodeText.length != 0) {
        return nodeText;
    }
    NSString *best = nil;
    for (UIView *subview in view.subviews) {
        NSString *candidate = YTKACECommentTextInView(subview, exact, depth + 1);
        if (candidate.length > best.length) {
            best = candidate;
        }
    }
    NSArray *elements = view.accessibilityElements;
    for (id element in elements) {
        NSString *identifier = YTKACEObjectMessage(element, @"accessibilityIdentifier");
        NSString *label = YTKACECleanCommentText(
            YTKACEObjectMessage(element, @"accessibilityLabel")
        );
        if (label.length != 0 &&
            (!exact || YTKACEIsCommentTextToken(identifier ?: @"")) &&
            label.length > best.length) {
            best = label;
        }
    }
    return best;
}

static UIViewController *YTKACEControllerForView(UIView *view) {
    UIResponder *responder = view;
    while (responder != nil) {
        if ([responder isKindOfClass:UIViewController.class]) {
            return (UIViewController *)responder;
        }
        responder = responder.nextResponder;
    }
    UIViewController *controller = view.window.rootViewController;
    while (controller.presentedViewController != nil) {
        controller = controller.presentedViewController;
    }
    return controller;
}

static NSString *YTKACECommentTextForView(UIView *view) {
    UIView *candidate = view;
    for (NSUInteger depth = 0; candidate != nil && depth < 8; depth++) {
        NSString *text = YTKACECommentTextInView(candidate, YES, 0);
        if (text.length != 0) {
            return text;
        }
        candidate = candidate.superview;
    }
    candidate = view;
    for (NSUInteger depth = 0; candidate != nil && depth < 6; depth++) {
        NSString *token = [NSString stringWithFormat:@"%@ %@ %@",
            NSStringFromClass(candidate.class) ?: @"",
            candidate.accessibilityIdentifier ?: @"",
            [candidate description] ?: @""];
        if (YTKACEIsCommentToken(token)) {
            NSString *text = YTKACECommentTextInView(candidate, NO, 0);
            if (text.length != 0) {
                return text;
            }
        }
        candidate = candidate.superview;
    }
    return nil;
}

@interface YTKACECopyCommentTarget : NSObject
+ (instancetype)sharedTarget;
- (void)handleCopyComment:(UILongPressGestureRecognizer *)gesture;
@end

@implementation YTKACECopyCommentTarget
+ (instancetype)sharedTarget {
    static YTKACECopyCommentTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ target = [YTKACECopyCommentTarget new]; });
    return target;
}

- (void)handleCopyComment:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || !YTKACEMasterEnabled()) {
        return;
    }
    UIView *view = gesture.view;
    NSString *text = YTKACECommentTextForView(view);
    if (text.length == 0) {
        return;
    }
    UIImpactFeedbackGenerator *feedback =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:nil
        message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"Copy Comment"
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            UIPasteboard.generalPasteboard.string = text;
            UINotificationFeedbackGenerator *confirmation =
                [UINotificationFeedbackGenerator new];
            [confirmation notificationOccurred:UINotificationFeedbackTypeSuccess];
        }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = view;
    menu.popoverPresentationController.sourceRect = view.bounds;
    UIViewController *controller = YTKACEControllerForView(view);
    if (controller.presentedViewController == nil) {
        [controller presentViewController:menu animated:YES completion:nil];
    }
}
@end

static void YTKACEAttachCommentGesture(UIView *view, id node) {
    if (view == nil) {
        return;
    }
    if (node != nil) {
        objc_setAssociatedObject(view, YTKACECommentNodeAssociation,
                                 node, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (objc_getAssociatedObject(view, YTKACECommentGestureAssociation) != nil) {
        return;
    }
    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc]
        initWithTarget:YTKACECopyCommentTarget.sharedTarget
                action:@selector(handleCopyComment:)];
    gesture.minimumPressDuration = 0.25;
    gesture.cancelsTouchesInView = NO;
    [view addGestureRecognizer:gesture];
    view.userInteractionEnabled = YES;
    objc_setAssociatedObject(view, YTKACECommentGestureAssociation,
                             gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void YTKACECommentNodeDidLoad(id receiver, SEL selector) {
    if (OriginalCommentNodeDidLoad != NULL) {
        ((void (*)(id, SEL))OriginalCommentNodeDidLoad)(receiver, selector);
    }
    NSString *identifier = YTKACEObjectMessage(receiver, @"accessibilityIdentifier");
    NSString *token = [NSString stringWithFormat:@"%@ %@",
        identifier ?: @"", [receiver description] ?: @""];
    if (!YTKACEIsCommentTextToken(token)) {
        return;
    }
    id attributedText = YTKACEObjectMessage(receiver, @"attributedText");
    NSString *text = YTKACECleanCommentText(
        YTKACEObjectMessage(attributedText, @"string")
    );
    if (text.length == 0) {
        return;
    }
    objc_setAssociatedObject(receiver, YTKACECommentTextAssociation,
                             text, OBJC_ASSOCIATION_COPY_NONATOMIC);
    UIView *renderedView = YTKACEObjectMessage(receiver, @"view");
    if ([renderedView isKindOfClass:UIView.class]) {
        objc_setAssociatedObject(renderedView, YTKACECommentTextAssociation,
                                 text, OBJC_ASSOCIATION_COPY_NONATOMIC);
        YTKACEAttachCommentGesture(renderedView, receiver);
    }
    id parent = YTKACEObjectMessage(receiver, @"yogaParent");
    for (NSUInteger depth = 0; parent != nil && depth < 16; depth++) {
        if (YTKACEIsCommentToken([parent description])) {
            objc_setAssociatedObject(parent, YTKACECommentTextAssociation,
                                     text, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
        parent = YTKACEObjectMessage(parent, @"yogaParent");
    }
}

static void YTKACECommentViewSetNode(UIView *receiver, SEL selector, id node) {
    if (OriginalCommentViewSetNode != NULL) {
        ((void (*)(id, SEL, id))OriginalCommentViewSetNode)(receiver, selector, node);
    }
    NSString *token = [NSString stringWithFormat:@"%@ %@ %@",
        NSStringFromClass(receiver.class) ?: @"",
        [receiver description] ?: @"", [node description] ?: @""];
    NSString *text = YTKACECommentTextInNode(node, 0);
    if (YTKACEIsCommentToken(token) || text.length != 0) {
        YTKACEAttachCommentGesture(receiver, node);
    }
}

static void YTKACECommentUIViewDidMove(UIView *receiver, SEL selector) {
    if (OriginalCommentUIViewDidMove != NULL) {
        ((void (*)(id, SEL))OriginalCommentUIViewDidMove)(receiver, selector);
    }
    NSString *token = [NSString stringWithFormat:@"%@ %@ %@",
        NSStringFromClass(receiver.class) ?: @"",
        receiver.accessibilityIdentifier ?: @"",
        [receiver description] ?: @""];
    if (YTKACEIsCommentToken(token)) {
        YTKACEAttachCommentGesture(receiver,
            YTKACEObjectMessage(receiver, @"keepalive_node"));
    }
}

void YTKACEInstallCopyCommentHooks(void) {
    YTKACEInstallInstanceHook(@"ASDisplayNode", @"didLoad",
        (IMP)YTKACECommentNodeDidLoad, &OriginalCommentNodeDidLoad);
    YTKACEInstallInstanceHook(@"_ASDisplayView", @"setKeepalive_node:",
        (IMP)YTKACECommentViewSetNode, &OriginalCommentViewSetNode);
    YTKACEInstallInstanceHook(@"UIView", @"didMoveToWindow",
        (IMP)YTKACECommentUIViewDidMove, &OriginalCommentUIViewDidMove);
}

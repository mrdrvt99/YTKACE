#import "../../YTKACE.h"
#import "../../Runtime/Preferences.h"
#import "../../UI/Notice.h"

#import <Photos/Photos.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const void *YTKACEAvatarGestureAssociation = &YTKACEAvatarGestureAssociation;

static UIViewController *YTKACEAvatarPresenter(UIView *view) {
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

static BOOL YTKACEAvatarToken(UIView *view) {
    UIView *candidate = view;
    for (NSUInteger depth = 0; candidate != nil && depth < 7; depth++) {
        NSString *token = [NSString stringWithFormat:@"%@ %@ %@",
            NSStringFromClass(candidate.class) ?: @"",
            candidate.accessibilityIdentifier ?: @"",
            candidate.accessibilityLabel ?: @""].lowercaseString;
        if ([token containsString:@"ytkace"]) return NO;
        if ([token containsString:@"avatar"] ||
            [token containsString:@"profile"] ||
            [token containsString:@"account"] ||
            [token containsString:@"channelreel"] ||
            [token containsString:@"reelround"]) {
            return YES;
        }
        candidate = candidate.superview;
    }
    return NO;
}

static UIImage *YTKACEAvatarImage(UIView *view) {
    if ([view isKindOfClass:UIImageView.class] &&
        ((UIImageView *)view).image != nil) {
        return ((UIImageView *)view).image;
    }
    SEL imageSelector = NSSelectorFromString(@"image");
    if ([view respondsToSelector:imageSelector]) {
        id image = ((id (*)(id, SEL))objc_msgSend)(view, imageSelector);
        if ([image isKindOfClass:UIImage.class]) return image;
    }
    UIImage *best = nil;
    CGFloat bestArea = 0.0;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithArray:view.subviews];
    while (stack.count != 0) {
        UIView *candidate = stack.lastObject;
        [stack removeLastObject];
        if ([candidate isKindOfClass:UIImageView.class]) {
            UIImage *image = ((UIImageView *)candidate).image;
            CGFloat area = image.size.width * image.size.height;
            if (image != nil && area >= bestArea) {
                best = image;
                bestArea = area;
            }
        }
        [stack addObjectsFromArray:candidate.subviews];
    }
    return best;
}

static BOOL YTKACEAvatarImageShape(UIImageView *view) {
    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat height = CGRectGetHeight(view.bounds);
    if (width < 18.0 || height < 18.0 || width > 240.0 || height > 240.0) {
        return NO;
    }
    CGFloat ratio = width / MAX(height, 1.0);
    if (ratio < 0.82 || ratio > 1.18) return NO;
    return view.layer.cornerRadius >= MIN(width, height) * 0.28 ||
        view.layer.mask != nil || YTKACEAvatarToken(view);
}

static UIView *YTKACEAvatarViewAtPoint(UIWindow *window,
                                       CGPoint point,
                                       UIImage **imageOutput) {
    UIView *hit = [window hitTest:point withEvent:nil];
    for (UIView *candidate = hit; candidate != nil; candidate = candidate.superview) {
        if (!YTKACEAvatarToken(candidate)) continue;
        UIImage *image = YTKACEAvatarImage(candidate);
        if (image != nil) {
            if (imageOutput != NULL) *imageOutput = image;
            return candidate;
        }
    }

    if ([hit isKindOfClass:UICollectionView.class]) {
        UICollectionView *collection = (UICollectionView *)hit;
        CGPoint local = [window convertPoint:point toView:collection];
        NSIndexPath *indexPath = [collection indexPathForItemAtPoint:local];
        UICollectionViewCell *cell = indexPath == nil
            ? nil : [collection cellForItemAtIndexPath:indexPath];
        UIImage *image = YTKACEAvatarImage(cell);
        if (image != nil) {
            if (imageOutput != NULL) *imageOutput = image;
            return cell;
        }
    }

    UIImageView *bestView = nil;
    CGFloat bestArea = CGFLOAT_MAX;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window];
    while (stack.count != 0) {
        UIView *candidate = stack.lastObject;
        [stack removeLastObject];
        if (candidate.hidden || candidate.alpha < 0.05) {
            continue;
        }
        if ([candidate isKindOfClass:UIImageView.class]) {
            UIImageView *imageView = (UIImageView *)candidate;
            CGPoint local = [window convertPoint:point toView:imageView];
            CGFloat area = CGRectGetWidth(imageView.bounds) *
                CGRectGetHeight(imageView.bounds);
            if (imageView.image != nil &&
                [imageView pointInside:local withEvent:nil] &&
                YTKACEAvatarImageShape(imageView) && area < bestArea) {
                bestView = imageView;
                bestArea = area;
            }
        }
        [stack addObjectsFromArray:candidate.subviews];
    }
    if (bestView != nil && imageOutput != NULL) *imageOutput = bestView.image;
    if (bestView != nil) return bestView;

    CALayer *layer = [window.layer hitTest:point];
    for (CALayer *candidate = layer; candidate != nil; candidate = candidate.superlayer) {
        id contents = candidate.contents;
        CGFloat width = CGRectGetWidth(candidate.bounds);
        CGFloat height = CGRectGetHeight(candidate.bounds);
        CGFloat ratio = width / MAX(height, 1.0);
        BOOL avatarSize = width >= 18.0 && height >= 18.0 &&
            width <= 240.0 && height <= 240.0 && ratio >= 0.82 && ratio <= 1.18;
        if (!avatarSize || contents == nil) continue;
        CFTypeRef value = (__bridge CFTypeRef)contents;
        if (CFGetTypeID(value) != CGImageGetTypeID()) continue;
        UIImage *image = [UIImage imageWithCGImage:(CGImageRef)value
            scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp];
        if (image != nil) {
            if (imageOutput != NULL) *imageOutput = image;
            return hit;
        }
    }
    return nil;
}

@interface YTKACEAvatarViewerController : UIViewController
    <UIScrollViewDelegate>
- (instancetype)initWithImage:(UIImage *)image;
@end

@implementation YTKACEAvatarViewerController {
    UIImage *_image;
    UIScrollView *_scrollView;
    UIImageView *_imageView;
}

- (instancetype)initWithImage:(UIImage *)image {
    self = [super initWithNibName:nil bundle:nil];
    if (self != nil) {
        _image = image;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    _scrollView = [UIScrollView new];
    _scrollView.delegate = self;
    _scrollView.minimumZoomScale = 1.0;
    _scrollView.maximumZoomScale = 8.0;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scrollView];

    _imageView = [[UIImageView alloc] initWithImage:_image];
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:_imageView];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = UIColor.whiteColor;
    close.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.82];
    close.layer.cornerRadius = 19.0;
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(closeTapped)
      forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
    [save setImage:[UIImage systemImageNamed:@"square.and.arrow.down"]
          forState:UIControlStateNormal];
    save.tintColor = UIColor.whiteColor;
    save.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.82];
    save.layer.cornerRadius = 19.0;
    save.translatesAutoresizingMaskIntoConstraints = NO;
    [save addTarget:self action:@selector(saveTapped)
     forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:save];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(doubleTapped:)];
    doubleTap.numberOfTapsRequired = 2;
    [_scrollView addGestureRecognizer:doubleTap];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_imageView.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor],
        [_imageView.leadingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.leadingAnchor],
        [_imageView.trailingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.trailingAnchor],
        [_imageView.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor],
        [_imageView.widthAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.widthAnchor],
        [_imageView.heightAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.heightAnchor],
        [close.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16.0],
        [close.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12.0],
        [close.widthAnchor constraintEqualToConstant:38.0],
        [close.heightAnchor constraintEqualToConstant:38.0],
        [save.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0],
        [save.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12.0],
        [save.widthAnchor constraintEqualToConstant:38.0],
        [save.heightAnchor constraintEqualToConstant:38.0]
    ]];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    (void)scrollView;
    return _imageView;
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)doubleTapped:(UITapGestureRecognizer *)gesture {
    if (_scrollView.zoomScale > 1.05) {
        [_scrollView setZoomScale:1.0 animated:YES];
        return;
    }
    CGPoint point = [gesture locationInView:_imageView];
    CGFloat scale = MIN(3.0, _scrollView.maximumZoomScale);
    CGSize size = CGSizeMake(CGRectGetWidth(_scrollView.bounds) / scale,
                             CGRectGetHeight(_scrollView.bounds) / scale);
    [_scrollView zoomToRect:CGRectMake(point.x - size.width * 0.5,
                                       point.y - size.height * 0.5,
                                       size.width, size.height)
                   animated:YES];
}

- (void)saveTapped {
    UIImage *image = _image;
    if (image == nil) return;
    [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
        [PHAssetChangeRequest creationRequestForAssetFromImage:image];
    } completionHandler:^(BOOL success, __unused NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            YTKACEShowNotice(success ? @"Profile picture saved" :
                @"Profile picture could not be saved");
        });
    }];
}

@end

@interface YTKACEAvatarTarget : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)sharedTarget;
- (void)avatarHeld:(UILongPressGestureRecognizer *)gesture;
@end

@implementation YTKACEAvatarTarget

+ (instancetype)sharedTarget {
    static YTKACEAvatarTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ target = [YTKACEAvatarTarget new]; });
    return target;
}

- (void)avatarHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan ||
        !YTKACEFeatureEnabled(@"kEnableProfilePictureViewer")) {
        return;
    }
    UIWindow *window = [gesture.view isKindOfClass:UIWindow.class]
        ? (UIWindow *)gesture.view : gesture.view.window;
    CGPoint point = [gesture locationInView:window];
    UIImage *image = nil;
    UIView *view = YTKACEAvatarViewAtPoint(window, point, &image);
    if (image == nil) return;
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    UIViewController *presenter = YTKACEAvatarPresenter(view);
    while (presenter.presentedViewController != nil) {
        presenter = presenter.presentedViewController;
    }
    if ([presenter isKindOfClass:YTKACEAvatarViewerController.class]) return;
    [presenter presentViewController:
        [[YTKACEAvatarViewerController alloc] initWithImage:image]
                           animated:YES completion:nil];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:
            (UIGestureRecognizer *)otherGestureRecognizer {
    (void)gestureRecognizer;
    (void)otherGestureRecognizer;
    return YES;
}

@end

static void YTKACEAttachAvatarGesture(UIWindow *window) {
    if (window == nil ||
        objc_getAssociatedObject(window, YTKACEAvatarGestureAssociation) != nil) {
        return;
    }
    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc]
        initWithTarget:YTKACEAvatarTarget.sharedTarget
                action:@selector(avatarHeld:)];
    gesture.minimumPressDuration = 1.0;
    gesture.cancelsTouchesInView = NO;
    gesture.delegate = YTKACEAvatarTarget.sharedTarget;
    [window addGestureRecognizer:gesture];
    objc_setAssociatedObject(window, YTKACEAvatarGestureAssociation, gesture,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void YTKACEAttachAvatarWindows(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            NSString *name = NSStringFromClass(window.class).lowercaseString;
            if ([name containsString:@"texteffects"] ||
                [name containsString:@"keyboard"]) {
                continue;
            }
            YTKACEAttachAvatarGesture(window);
        }
    }
}

void YTKACEInstallProfilePictureHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:
            UIWindowDidBecomeKeyNotification object:nil
            queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *notification) {
                YTKACEAttachAvatarWindows();
            }];
    });
    dispatch_async(dispatch_get_main_queue(), ^{ YTKACEAttachAvatarWindows(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ YTKACEAttachAvatarWindows(); });
}

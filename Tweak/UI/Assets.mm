#import "Assets.h"

NSBundle *YTKACEAssetsBundle(void) {
    static NSBundle *bundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [NSBundle.mainBundle pathForResource:@"YTKACE"
                                                       ofType:@"bundle"];
        if (path.length != 0) {
            bundle = [NSBundle bundleWithPath:path];
        }
    });
    return bundle;
}

UIImage *YTKACEAssetImage(NSString *name, NSString *fallbackSymbol) {
    UIImage *image = nil;
    NSBundle *bundle = YTKACEAssetsBundle();
    if (bundle != nil && name.length != 0) {
        image = [UIImage imageNamed:name
                           inBundle:bundle
      compatibleWithTraitCollection:nil];
    }
    if (image == nil && fallbackSymbol.length != 0) {
        if (@available(iOS 13.0, *)) {
            image = [UIImage systemImageNamed:fallbackSymbol];
        }
    }
    return image;
}

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSBundle * _Nullable YTKACEAssetsBundle(void);
FOUNDATION_EXPORT UIImage * _Nullable YTKACEAssetImage(
    NSString *name,
    NSString * _Nullable fallbackSymbol
);

NS_ASSUME_NONNULL_END

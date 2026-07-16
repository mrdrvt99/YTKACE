#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^YTKACEFFmpegCompletion)(NSError * _Nullable error);

@interface YTKACEFFmpegMuxer : NSObject
+ (void)remuxVideoURL:(NSURL *)videoURL
             audioURL:(NSURL *)audioURL
            outputURL:(NSURL *)outputURL
           completion:(YTKACEFFmpegCompletion)completion;
@end

NS_ASSUME_NONNULL_END

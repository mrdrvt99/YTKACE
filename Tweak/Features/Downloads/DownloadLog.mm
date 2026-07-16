#import "DownloadLog.h"

static const NSUInteger YTKACEDownloadLogLimit = 512 * 1024;

static NSURL *YTKACEDownloadLogURL(void) {
    NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
        inDomains:NSUserDomainMask].firstObject;
    NSURL *directory = [[base URLByAppendingPathComponent:@"YTKACE" isDirectory:YES]
        URLByAppendingPathComponent:@"Logs" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory
        withIntermediateDirectories:YES attributes:nil error:nil];
    return [directory URLByAppendingPathComponent:@"downloads.log"];
}

static dispatch_queue_t YTKACEDownloadLogQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.ytkace.download-log", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

void YTKACEDownloadLog(NSString *identifier, NSString *format, ...) {
    if (format.length == 0) return;
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    if (message.length > 4096) message = [message substringToIndex:4096];
    NSString *line = [NSString stringWithFormat:@"%@ [%@] %@\n",
        NSDate.date, identifier.length == 0 ? @"download" : identifier, message];
    dispatch_async(YTKACEDownloadLogQueue(), ^{
        NSURL *URL = YTKACEDownloadLogURL();
        NSData *existing = [NSData dataWithContentsOfURL:URL] ?: NSData.data;
        NSMutableData *data = [existing mutableCopy];
        [data appendData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        if (data.length > YTKACEDownloadLogLimit) {
            NSUInteger keep = YTKACEDownloadLogLimit * 3 / 4;
            NSData *tail = [data subdataWithRange:NSMakeRange(data.length - keep, keep)];
            data = [tail mutableCopy];
        }
        [data writeToURL:URL atomically:YES];
    });
}

NSString *YTKACEDownloadLogContents(void) {
    __block NSString *contents = @"No download activity yet.";
    dispatch_sync(YTKACEDownloadLogQueue(), ^{
        NSString *value = [NSString stringWithContentsOfURL:YTKACEDownloadLogURL()
            encoding:NSUTF8StringEncoding error:nil];
        if (value.length != 0) contents = value;
    });
    return contents;
}

void YTKACEClearDownloadLog(void) {
    dispatch_sync(YTKACEDownloadLogQueue(), ^{
        [NSFileManager.defaultManager removeItemAtURL:YTKACEDownloadLogURL() error:nil];
    });
}

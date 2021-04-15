/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDownloaderOperation.h"
#import "SDWebImageError.h"
#import "SDInternalMacros.h"
#import "SDWebImageDownloaderResponseModifier.h"
#import "SDWebImageDownloaderDecryptor.h"

// iOS 8 Foundation.framework extern these symbol but the define is in CFNetwork.framework. We just fix this without import CFNetwork.framework
#if ((__IPHONE_OS_VERSION_MIN_REQUIRED && __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_9_0) || (__MAC_OS_X_VERSION_MIN_REQUIRED && __MAC_OS_X_VERSION_MIN_REQUIRED < __MAC_10_11))
const float NSURLSessionTaskPriorityHigh = 0.75;
const float NSURLSessionTaskPriorityDefault = 0.5;
const float NSURLSessionTaskPriorityLow = 0.25;
#endif

static NSString *const kProgressCallbackKey = @"progress";
static NSString *const kCompletedCallbackKey = @"completed";

typedef NSMutableDictionary<NSString *, id> SDCallbacksDictionary;

@interface SDWebImageDownloaderOperation ()

@property (strong, nonatomic, nonnull) NSMutableArray<SDCallbacksDictionary *> *callbackBlocks;

@property (assign, nonatomic, readwrite) SDWebImageDownloaderOptions options;
@property (copy, nonatomic, readwrite, nullable) SDWebImageContext *context;

@property (assign, nonatomic, getter = isExecuting) BOOL executing;
@property (assign, nonatomic, getter = isFinished) BOOL finished;
@property (strong, nonatomic, nullable) NSMutableData *imageData;
@property (copy, nonatomic, nullable) NSData *cachedData; // for `SDWebImageDownloaderIgnoreCachedResponse`
@property (assign, nonatomic) NSUInteger expectedSize; // may be 0
@property (assign, nonatomic) NSUInteger receivedSize;
@property (strong, nonatomic, nullable, readwrite) NSURLResponse *response;
@property (strong, nonatomic, nullable) NSError *responseError;
@property (assign, nonatomic) double previousProgress; // previous progress percent

@property (strong, nonatomic, nullable) id<SDWebImageDownloaderResponseModifier> responseModifier; // modify original URLResponse
@property (strong, nonatomic, nullable) id<SDWebImageDownloaderDecryptor> decryptor; // decrypt image data

// This is weak because it is injected by whoever manages this session. If this gets nil-ed out, we won't be able to run
// the task associated with this operation
@property (weak, nonatomic, nullable) NSURLSession *unownedSession;
// This is set if we're using not using an injected NSURLSession. We're responsible of invalidating this one
@property (strong, nonatomic, nullable) NSURLSession *ownedSession;

@property (strong, nonatomic, readwrite, nullable) NSURLSessionTask *dataTask;

@property (strong, nonatomic, readwrite, nullable) NSURLSessionTaskMetrics *metrics API_AVAILABLE(macosx(10.12), ios(10.0), watchos(3.0), tvos(10.0));

@property (strong, nonatomic, nonnull) NSOperationQueue *coderQueue; // the serial operation queue to do image decoding
#if SD_UIKIT
@property (assign, nonatomic) UIBackgroundTaskIdentifier backgroundTaskId;
#endif

@end

@implementation SDWebImageDownloaderOperation

@synthesize executing = _executing;
@synthesize finished = _finished;

- (nonnull instancetype)init {
    return [self initWithRequest:nil inSession:nil options:0];
}

- (instancetype)initWithRequest:(NSURLRequest *)request inSession:(NSURLSession *)session options:(SDWebImageDownloaderOptions)options {
    return [self initWithRequest:request inSession:session options:options context:nil];
}

- (nonnull instancetype)initWithRequest:(nullable NSURLRequest *)request
                              inSession:(nullable NSURLSession *)session
                                options:(SDWebImageDownloaderOptions)options
                                context:(nullable SDWebImageContext *)context {
    if ((self = [super init])) {
        _request = [request copy];
        _options = options;
        _context = [context copy];
        _callbackBlocks = [NSMutableArray new];
        _responseModifier = context[SDWebImageContextDownloadResponseModifier];
        _decryptor = context[SDWebImageContextDownloadDecryptor];
        _executing = NO;
        _finished = NO;
        _expectedSize = 0;
        _unownedSession = session;
        _coderQueue = [NSOperationQueue new];
        _coderQueue.maxConcurrentOperationCount = 1;
#if SD_UIKIT
        _backgroundTaskId = UIBackgroundTaskInvalid;
#endif
    }
    return self;
}

- (nullable id)addHandlersForProgress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                            completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock {
    SDCallbacksDictionary *callbacks = [NSMutableDictionary new];
    if (progressBlock) callbacks[kProgressCallbackKey] = [progressBlock copy];
    if (completedBlock) callbacks[kCompletedCallbackKey] = [completedBlock copy];
    @synchronized (self) {
        [self.callbackBlocks addObject:callbacks];
    }
    return callbacks;
}

- (nullable NSArray<id> *)callbacksForKey:(NSString *)key {
    NSMutableArray<id> *callbacks;
    @synchronized (self) {
        callbacks = [[self.callbackBlocks valueForKey:key] mutableCopy];
    }
    // We need to remove [NSNull null] because there might not always be a progress block for each callback
    [callbacks removeObjectIdenticalTo:[NSNull null]];
    return [callbacks copy]; // strip mutability here
}

- (BOOL)cancel:(nullable id)token {
    if (!token) return NO;
    
    BOOL shouldCancel = NO;
    @synchronized (self) {
        NSMutableArray *tempCallbackBlocks = [self.callbackBlocks mutableCopy];
        [tempCallbackBlocks removeObjectIdenticalTo:token];
        if (tempCallbackBlocks.count == 0) {
            shouldCancel = YES;
        }
    }
    if (shouldCancel) {
        // Cancel operation running and callback last token's completion block
        [self cancel];
    } else {
        // Only callback this token's completion block
        @synchronized (self) {
            [self.callbackBlocks removeObjectIdenticalTo:token];
        }
        SDWebImageDownloaderCompletedBlock completedBlock = [token valueForKey:kCompletedCallbackKey];
        dispatch_main_async_safe(^{
            if (completedBlock) {
                completedBlock(nil, nil, [NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorCancelled userInfo:@{NSLocalizedDescriptionKey : @"Operation cancelled by user during sending the request"}], YES);
            }
        });
    }
    return shouldCancel;
}
//并行处理的Operation需要重写这个方法，在这个方法里具体的处理
- (void)start {
    @synchronized (self) {
        if (self.isCancelled) {
            self.finished = YES;
            // Operation cancelled by user before sending the request
            [self callCompletionBlocksWithError:[NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorCancelled userInfo:@{NSLocalizedDescriptionKey : @"Operation cancelled by user before sending the request"}]];
            [self reset];
            return;
        }

#if SD_UIKIT
        Class UIApplicationClass = NSClassFromString(@"UIApplication");
        //如果进入后台,
        BOOL hasApplication = UIApplicationClass && [UIApplicationClass respondsToSelector:@selector(sharedApplication)];
        if (hasApplication && [self shouldContinueWhenAppEntersBackground]) {
            __weak typeof(self) wself = self;
            UIApplication * app = [UIApplicationClass performSelector:@selector(sharedApplication)];
            self.backgroundTaskId = [app beginBackgroundTaskWithExpirationHandler:^{
                //后台执行结束之后，做取消
                [wself cancel];
            }];
        }
#endif
        //如果在downloader中的session被设置为nil，需要我们生成一个ownSession
        NSURLSession *session = self.unownedSession;
        if (!session) {
            NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
            sessionConfig.timeoutIntervalForRequest = 15;
            
            /**
             *  Create the session for this task
             *  We send nil as delegate queue so that the session creates a serial operation queue for performing all delegate
             *  method calls and completion handler calls.
             */
            session = [NSURLSession sessionWithConfiguration:sessionConfig
                                                    delegate:self
                                               delegateQueue:nil];
            self.ownedSession = session;
        }
        //获得当前的图片缓存，为以后的数据核验是否需要缓存更新作准备
        if (self.options & SDWebImageDownloaderIgnoreCachedResponse) {
            // Grab the cached data for later check
            NSURLCache *URLCache = session.configuration.URLCache;
            if (!URLCache) {
                URLCache = [NSURLCache sharedURLCache];
            }
            NSCachedURLResponse *cachedResponse;
            // NSURLCache's `cachedResponseForRequest:` is not thread-safe, see https://developer.apple.com/documentation/foundation/nsurlcache#2317483
            @synchronized (URLCache) {
                cachedResponse = [URLCache cachedResponseForRequest:self.request];
            }
            if (cachedResponse) {
                self.cachedData = cachedResponse.data;
            }
        }
        
        self.dataTask = [session dataTaskWithRequest:self.request];
        self.executing = YES;
    }
    //设置当前的任务优先级
    if (self.dataTask) {
        if (self.options & SDWebImageDownloaderHighPriority) {
            self.dataTask.priority = NSURLSessionTaskPriorityHigh;
            self.coderQueue.qualityOfService = NSQualityOfServiceUserInteractive;
        } else if (self.options & SDWebImageDownloaderLowPriority) {
            self.dataTask.priority = NSURLSessionTaskPriorityLow;
            self.coderQueue.qualityOfService = NSQualityOfServiceBackground;
        } else {
            self.dataTask.priority = NSURLSessionTaskPriorityDefault;
            self.coderQueue.qualityOfService = NSQualityOfServiceDefault;
        }
        //执行当前的任务
        [self.dataTask resume];
        for (SDWebImageDownloaderProgressBlock progressBlock in [self callbacksForKey:kProgressCallbackKey]) {
            progressBlock(0, NSURLResponseUnknownLength, self.request.URL);
        }
        __block typeof(self) strongSelf = self;
        //开始下载
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStartNotification object:strongSelf];
        });
    } else {
        [self callCompletionBlocksWithError:[NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorInvalidDownloadOperation userInfo:@{NSLocalizedDescriptionKey : @"Task can't be initialized"}]];
        [self done];
    }
}
//取消任务
- (void)cancel {
    @synchronized (self) {
        [self cancelInternal];
    }
}

- (void)cancelInternal {
    if (self.isFinished) return;
    [super cancel];

    if (self.dataTask) {
        [self.dataTask cancel];
        __block typeof(self) strongSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:strongSelf];
        });

        // As we cancelled the task, its callback won't be called and thus won't
        // maintain the isFinished and isExecuting flags.
        if (self.isExecuting) self.executing = NO;
        if (!self.isFinished) self.finished = YES;
    } else {
        // Operation cancelled by user during sending the request
        [self callCompletionBlocksWithError:[NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorCancelled userInfo:@{NSLocalizedDescriptionKey : @"Operation cancelled by user during sending the request"}]];
    }

    [self reset];
}

- (void)done {
    self.finished = YES;
    self.executing = NO;
    [self reset];
}

- (void)reset {
    @synchronized (self) {
        [self.callbackBlocks removeAllObjects];
        self.dataTask = nil;
        
        if (self.ownedSession) {
            [self.ownedSession invalidateAndCancel];
            self.ownedSession = nil;
        }
        
#if SD_UIKIT
        if (self.backgroundTaskId != UIBackgroundTaskInvalid) {
            // If backgroundTaskId != UIBackgroundTaskInvalid, sharedApplication is always exist
            //结束app的后台任务
            UIApplication * app = [UIApplication performSelector:@selector(sharedApplication)];
            [app endBackgroundTask:self.backgroundTaskId];
            self.backgroundTaskId = UIBackgroundTaskInvalid;
        }
#endif
    }
}

- (void)setFinished:(BOOL)finished {
    [self willChangeValueForKey:@"isFinished"];
    _finished = finished;
    [self didChangeValueForKey:@"isFinished"];
}

- (void)setExecuting:(BOOL)executing {
    [self willChangeValueForKey:@"isExecuting"];
    _executing = executing;
    [self didChangeValueForKey:@"isExecuting"];
}

- (BOOL)isConcurrent {
    return YES;
}

#pragma mark NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    NSURLSessionResponseDisposition disposition = NSURLSessionResponseAllow;
    
    // Check response modifier, if return nil, will marked as cancelled.
    BOOL valid = YES;
    if (self.responseModifier && response) {
        response = [self.responseModifier modifiedResponseWithResponse:response];
        if (!response) {
            valid = NO;
            self.responseError = [NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorInvalidDownloadResponse userInfo:@{NSLocalizedDescriptionKey : @"Download marked as failed because response is nil"}];
        }
    }
    //总长度
    NSInteger expected = (NSInteger)response.expectedContentLength;
    expected = expected > 0 ? expected : 0;
    self.expectedSize = expected;
    self.response = response;
    
    NSInteger statusCode = [response respondsToSelector:@selector(statusCode)] ? ((NSHTTPURLResponse *)response).statusCode : 200;
    // Status code should between [200,400)
    //状态码
    BOOL statusCodeValid = statusCode >= 200 && statusCode < 400;
    if (!statusCodeValid) {
        valid = NO;
        self.responseError = [NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorInvalidDownloadStatusCode userInfo:@{NSLocalizedDescriptionKey : @"Download marked as failed because response status code is not in 200-400", SDWebImageErrorDownloadStatusCodeKey : @(statusCode)}];
    }
    //'304 Not Modified' is an exceptional one
    //URLSession current behavior will return 200 status code when the server respond 304 and URLCache hit. But this is not a standard behavior and we just add a check
    //如果返回304，但是没有缓存数据，返回错误
    if (statusCode == 304 && !self.cachedData) {
        valid = NO;
        self.responseError = [NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorCacheNotModified userInfo:@{NSLocalizedDescriptionKey : @"Download response status code is 304 not modified and ignored"}];
    }
    
    if (valid) {
        //如果是有效的数据，那么返回当前进度
        for (SDWebImageDownloaderProgressBlock progressBlock in [self callbacksForKey:kProgressCallbackKey]) {
            progressBlock(0, expected, self.request.URL);
        }
    } else {
        // Status code invalid and marked as cancelled. Do not call `[self.dataTask cancel]` which may mass up URLSession life cycle
        disposition = NSURLSessionResponseCancel;
    }
    //接收到数据的通知
    __block typeof(self) strongSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadReceiveResponseNotification object:strongSelf];
    });
    //允许接收数据
    if (completionHandler) {
        completionHandler(disposition);
    }
}
//接收到下载的网络数据之后的处理
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    if (!self.imageData) {
        self.imageData = [[NSMutableData alloc] initWithCapacity:self.expectedSize];
    }
    //收集图片nsdata
    [self.imageData appendData:data];
    
    self.receivedSize = self.imageData.length;
    if (self.expectedSize == 0) {
        // Unknown expectedSize, immediately call progressBlock and return
        //假如不知道期望图片的size，立刻返回
        for (SDWebImageDownloaderProgressBlock progressBlock in [self callbacksForKey:kProgressCallbackKey]) {
            progressBlock(self.receivedSize, self.expectedSize, self.request.URL);
        }
        return;
    }
    
    // Get the finish status
    //接收的数据大于等于期望的大小，说明获取图片成功
    BOOL finished = (self.receivedSize >= self.expectedSize);
    // Get the current progress
    //获取当前的进度
    double currentProgress = (double)self.receivedSize / (double)self.expectedSize;
    double previousProgress = self.previousProgress;
    double progressInterval = currentProgress - previousProgress;
    // Check if we need callback progress
    //假如没有下载完成&&下载进度小于最小进度
    if (!finished && (progressInterval < self.minimumProgressInterval)) {
        return;
    }
    //以前的进度就等于当前进度
    self.previousProgress = currentProgress;
    
    // Using data decryptor will disable the progressive decoding, since there are no support for progressive decrypt
    //并且当前是按照SDWebImageDownloaderProgressiveLoad来展示图片
    BOOL supportProgressive = (self.options & SDWebImageDownloaderProgressiveLoad) && !self.decryptor;
    if (supportProgressive) {
        // Get the image data
        NSData *imageData = [self.imageData copy];
        
        // keep maximum one progressive decode process during download
        if (self.coderQueue.operationCount == 0) {
            // NSOperation have autoreleasepool, don't need to create extra one
            [self.coderQueue addOperationWithBlock:^{
                UIImage *image = SDImageLoaderDecodeProgressiveImageData(imageData, self.request.URL, finished, self, [[self class] imageOptionsFromDownloaderOptions:self.options], self.context);
                if (image) {
                    // We do not keep the progressive decoding image even when `finished`=YES. Because they are for view rendering but not take full function from downloader options. And some coders implementation may not keep consistent between progressive decoding and normal decoding.
                    
                    [self callCompletionBlocksWithImage:image imageData:nil error:nil finished:NO];
                }
            }];
        }
    }
    
    for (SDWebImageDownloaderProgressBlock progressBlock in [self callbacksForKey:kProgressCallbackKey]) {
        progressBlock(self.receivedSize, self.expectedSize, self.request.URL);
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler {
    
    NSCachedURLResponse *cachedResponse = proposedResponse;

    if (!(self.options & SDWebImageDownloaderUseNSURLCache)) {
        // Prevents caching of responses
        cachedResponse = nil;
    }
    if (completionHandler) {
        completionHandler(cachedResponse);
    }
}

#pragma mark NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    // If we already cancel the operation or anything mark the operation finished, don't callback twice
    if (self.isFinished) return;
    
    @synchronized(self) {
        self.dataTask = nil;
        __block typeof(self) strongSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadStopNotification object:strongSelf];
            if (!error) {
                [[NSNotificationCenter defaultCenter] postNotificationName:SDWebImageDownloadFinishNotification object:strongSelf];
            }
        });
    }
    
    // make sure to call `[self done]` to mark operation as finished
    //标记完成了
    if (error) {
        // custom error instead of URLSession error
        if (self.responseError) {
            error = self.responseError;
        }
        [self callCompletionBlocksWithError:error];
        [self done];
    } else {
        if ([self callbacksForKey:kCompletedCallbackKey].count > 0) {
            //下载完成，将本地的imageData置为nil，防止下次进入数据出错
            NSData *imageData = [self.imageData copy];
            self.imageData = nil;
            // data decryptor
            if (imageData && self.decryptor) {
                imageData = [self.decryptor decryptedDataWithData:imageData response:self.response];
            }
            if (imageData) {
                /**  if you specified to only use cached data via `SDWebImageDownloaderIgnoreCachedResponse`,
                 *  then we should check if the cached data is equal to image data
                 */
                //判断是否更新了，包括SDWebImageDownloaderIgnoreCachedResponse/本地缓存对比
                if (self.options & SDWebImageDownloaderIgnoreCachedResponse && [self.cachedData isEqualToData:imageData]) {
                    //如果和本地缓存相同，那么返回SDWebImageErrorCacheNotModified
                    self.responseError = [NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorCacheNotModified userInfo:@{NSLocalizedDescriptionKey : @"Downloaded image is not modified and ignored"}];
                    // call completion block with not modified error
                    [self callCompletionBlocksWithError:self.responseError];
                    [self done];
                    //如果没有更新，那么在子线程进图片处理
                } else {
                    // decode the image in coder queue, cancel all previous decoding process
                    [self.coderQueue cancelAllOperations];
                    [self.coderQueue addOperationWithBlock:^{
                        UIImage *image = SDImageLoaderDecodeImageData(imageData, self.request.URL, [[self class] imageOptionsFromDownloaderOptions:self.options], self.context);
                        CGSize imageSize = image.size;
                        if (imageSize.width == 0 || imageSize.height == 0) {
                            NSString *description = image == nil ? @"Downloaded image decode failed" : @"Downloaded image has 0 pixels";
                            [self callCompletionBlocksWithError:[NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorBadImageData userInfo:@{NSLocalizedDescriptionKey : description}]];
                        } else {
                            [self callCompletionBlocksWithImage:image imageData:imageData error:nil finished:YES];
                        }
                        [self done];
                    }];
                }
            } else {
                [self callCompletionBlocksWithError:[NSError errorWithDomain:SDWebImageErrorDomain code:SDWebImageErrorBadImageData userInfo:@{NSLocalizedDescriptionKey : @"Image data is nil"}]];
                [self done];
            }
        } else {
            [self done];
        }
    }
}
//验证https证书
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    __block NSURLCredential *credential = nil;
    //使用可以信任证书颁发机构的证书
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        //如果设置了SDWebImageDownloaderAllowInvalidSSLCertificates，则信任任何证书，不需要验证
        if (!(self.options & SDWebImageDownloaderAllowInvalidSSLCertificates)) {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        } else {
            credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            disposition = NSURLSessionAuthChallengeUseCredential;
        }
    } else {
        //自己生成的证书
        if (challenge.previousFailureCount == 0) {
            if (self.credential) {
                credential = self.credential;
                disposition = NSURLSessionAuthChallengeUseCredential;
            } else {
                disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        } else {
            disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
        }
    }
    
    if (completionHandler) {
        completionHandler(disposition, credential);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics API_AVAILABLE(macosx(10.12), ios(10.0), watchos(3.0), tvos(10.0)) {
    self.metrics = metrics;
}

#pragma mark Helper methods
+ (SDWebImageOptions)imageOptionsFromDownloaderOptions:(SDWebImageDownloaderOptions)downloadOptions {
    SDWebImageOptions options = 0;
    if (downloadOptions & SDWebImageDownloaderScaleDownLargeImages) options |= SDWebImageScaleDownLargeImages;
    if (downloadOptions & SDWebImageDownloaderDecodeFirstFrameOnly) options |= SDWebImageDecodeFirstFrameOnly;
    if (downloadOptions & SDWebImageDownloaderPreloadAllFrames) options |= SDWebImagePreloadAllFrames;
    if (downloadOptions & SDWebImageDownloaderAvoidDecodeImage) options |= SDWebImageAvoidDecodeImage;
    if (downloadOptions & SDWebImageDownloaderMatchAnimatedImageClass) options |= SDWebImageMatchAnimatedImageClass;
    
    return options;
}

- (BOOL)shouldContinueWhenAppEntersBackground {
    return SD_OPTIONS_CONTAINS(self.options, SDWebImageDownloaderContinueInBackground);
}

- (void)callCompletionBlocksWithError:(nullable NSError *)error {
    [self callCompletionBlocksWithImage:nil imageData:nil error:error finished:YES];
}

- (void)callCompletionBlocksWithImage:(nullable UIImage *)image
                            imageData:(nullable NSData *)imageData
                                error:(nullable NSError *)error
                             finished:(BOOL)finished {
    NSArray<id> *completionBlocks = [self callbacksForKey:kCompletedCallbackKey];
    dispatch_main_async_safe(^{
        for (SDWebImageDownloaderCompletedBlock completedBlock in completionBlocks) {
            completedBlock(image, imageData, error, finished);
        }
    });
}

@end

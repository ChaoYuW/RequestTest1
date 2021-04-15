/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageCompat.h"
#import "SDWebImageDefine.h"
#import "SDWebImageOperation.h"
#import "SDWebImageDownloaderConfig.h"
#import "SDWebImageDownloaderRequestModifier.h"
#import "SDWebImageDownloaderResponseModifier.h"
#import "SDWebImageDownloaderDecryptor.h"
#import "SDImageLoader.h"

/// Downloader options
typedef NS_OPTIONS(NSUInteger, SDWebImageDownloaderOptions) {
    /**
     * Put the download in the low queue priority and task priority.
     */
    SDWebImageDownloaderLowPriority = 1 << 0,
    
    /**
     * This flag enables progressive download, the image is displayed progressively during download as a browser would do.
     */
    /**
         //浏览器样式的图片下载
         */
    SDWebImageDownloaderProgressiveLoad = 1 << 1,

    /**
     * By default, request prevent the use of NSURLCache. With this flag, NSURLCache
     * is used with default policies.
     */
    /**
        *默认情况下，http请求阻止使用NSURLCache对象。如果设置了这个标记，则NSURLCache会被http请求使用。
        */
    SDWebImageDownloaderUseNSURLCache = 1 << 2,

    /**
     * Call completion block with nil image/imageData if the image was read from NSURLCache
     * And the error code is `SDWebImageErrorCacheNotModified`
     * This flag should be combined with `SDWebImageDownloaderUseNSURLCache`.
     */
    /**
         *如果image/imageData是从NSURLCache返回的。则completion这个回调会返回nil
         */
    SDWebImageDownloaderIgnoreCachedResponse = 1 << 3,
    
    /**
     * In iOS 4+, continue the download of the image if the app goes to background. This is achieved by asking the system for
     * extra time in background to let the request finish. If the background task expires the operation will be cancelled.
     */
    /**
         *如果app进入后台模式，是否继续下载。这个是通过在后台申请时间来完成这个操作。如果指定的时间范围内没有完成，则直接取消下载。
         */
    SDWebImageDownloaderContinueInBackground = 1 << 4,

    /**
     * Handles cookies stored in NSHTTPCookieStore by setting 
     * NSMutableURLRequest.HTTPShouldHandleCookies = YES;
     */
    /**
         * 处理缓存在`NSHTTPCookieStore`对象里面的cookie。通过设置`NSMutableURLRequest.HTTPShouldHandleCookies = YES`来实现的。
         */
    SDWebImageDownloaderHandleCookies = 1 << 5,

    /**
     * Enable to allow untrusted SSL certificates.
     * Useful for testing purposes. Use with caution in production.
     */
    /**
        * 允许非信任的SSL证书请求。
        * 在测试的时候很有用。但是正式环境要小心使用。
        */
    SDWebImageDownloaderAllowInvalidSSLCertificates = 1 << 6,

    /**
     * Put the download in the high queue priority and task priority.
     */
    /**
         * 默认情况下，图片加载的顺序是根据加入队列的顺序加载的。但是这个标记会把任务加入队列的最前面。
         */
    SDWebImageDownloaderHighPriority = 1 << 7,
    
    /**
     * By default, images are decoded respecting their original size. On iOS, this flag will scale down the
     * images to a size compatible with the constrained memory of devices.
     * This flag take no effect if `SDWebImageDownloaderAvoidDecodeImage` is set. And it will be ignored if `SDWebImageDownloaderProgressiveLoad` is set.
     */
    /**
         * 默认情况下，图片会按照他的原始大小来解码显示。这个属性会调整图片的尺寸到合适的大小根据设备的内存限制。
         * 如果`SDWebImageProgressiveDownload`标记被设置了，则这个flag不起作用。
         */
    SDWebImageDownloaderScaleDownLargeImages = 1 << 8,
    
    /**
     * By default, we will decode the image in the background during cache query and download from the network. This can help to improve performance because when rendering image on the screen, it need to be firstly decoded. But this happen on the main queue by Core Animation.
     * However, this process may increase the memory usage as well. If you are experiencing a issue due to excessive memory consumption, This flag can prevent decode the image.
     */
    /**
        * 加载图片时，图片的解压缩操作再子线程处理转化成bitmap再进行绘制
        */
    SDWebImageDownloaderAvoidDecodeImage = 1 << 9,
    
    /**
     * By default, we decode the animated image. This flag can force decode the first frame only and produce the static image.
     */
    /**
        * 只截取第一帧
        */
    SDWebImageDownloaderDecodeFirstFrameOnly = 1 << 10,
    
    /**
     * By default, for `SDAnimatedImage`, we decode the animated image frame during rendering to reduce memory usage. This flag actually trigger `preloadAllAnimatedImageFrames = YES` after image load from network
     */
    /**
        * 默认情况下，对于“SDAnimatedImage”，我们在渲染时解码动画图像帧，以减少内存使用。但是，当大量imageViews共享动画图像时，可以指定将所有帧预加载到内存中，以减少CPU使用。这将在后台队列中触发“preloadAllAnimatedImageFrames”(仅限磁盘缓存和下载)
        */
    SDWebImageDownloaderPreloadAllFrames = 1 << 11,
    
    /**
     * By default, when you use `SDWebImageContextAnimatedImageClass` context option (like using `SDAnimatedImageView` which designed to use `SDAnimatedImage`), we may still use `UIImage` when the memory cache hit, or image decoder is not available, to behave as a fallback solution.
     * Using this option, can ensure we always produce image with your provided class. If failed, a error with code `SDWebImageErrorBadImageData` will been used.
     * Note this options is not compatible with `SDWebImageDownloaderDecodeFirstFrameOnly`, which always produce a UIImage/NSImage.
     */
    SDWebImageDownloaderMatchAnimatedImageClass = 1 << 12,
};

FOUNDATION_EXPORT NSNotificationName _Nonnull const SDWebImageDownloadStartNotification;
FOUNDATION_EXPORT NSNotificationName _Nonnull const SDWebImageDownloadReceiveResponseNotification;
FOUNDATION_EXPORT NSNotificationName _Nonnull const SDWebImageDownloadStopNotification;
FOUNDATION_EXPORT NSNotificationName _Nonnull const SDWebImageDownloadFinishNotification;

typedef SDImageLoaderProgressBlock SDWebImageDownloaderProgressBlock;
typedef SDImageLoaderCompletedBlock SDWebImageDownloaderCompletedBlock;

/**
 *  A token associated with each download. Can be used to cancel a download
 */
@interface SDWebImageDownloadToken : NSObject <SDWebImageOperation>

/**
 Cancel the current download.
 */
- (void)cancel;

/**
 The download's URL.
 */
@property (nonatomic, strong, nullable, readonly) NSURL *url;

/**
 The download's request.
 */
@property (nonatomic, strong, nullable, readonly) NSURLRequest *request;

/**
 The download's response.
 */
@property (nonatomic, strong, nullable, readonly) NSURLResponse *response;

/**
 The download's metrics. This will be nil if download operation does not support metrics.
 */
@property (nonatomic, strong, nullable, readonly) NSURLSessionTaskMetrics *metrics API_AVAILABLE(macosx(10.12), ios(10.0), watchos(3.0), tvos(10.0));

@end


/**
 * Asynchronous downloader dedicated and optimized for image loading.
 */
@interface SDWebImageDownloader : NSObject

/**
 * Downloader Config object - storing all kind of settings.
 * Most config properties support dynamic changes during download, except something like `sessionConfiguration`, see `SDWebImageDownloaderConfig` for more detail.
 */
/**
 * 下载的配置，包括最大并发、超时时间等
 */
@property (nonatomic, copy, readonly, nonnull) SDWebImageDownloaderConfig *config;

/**
 * Set the request modifier to modify the original download request before image load.
 * This request modifier method will be called for each downloading image request. Return the original request means no modification. Return nil will cancel the download request.
 * Defaults to nil, means does not modify the original download request.
 * @note If you want to modify single request, consider using `SDWebImageContextDownloadRequestModifier` context option.
 */
/**
* `SDWebImageContextDownloadRequestModifier` context修改原始的下载request
 */
@property (nonatomic, strong, nullable) id<SDWebImageDownloaderRequestModifier> requestModifier;

/**
 * Set the response modifier to modify the original download response during image load.
 * This request modifier method will be called for each downloading image response. Return the original response means no modification. Return nil will mark current download as cancelled.
 * Defaults to nil, means does not modify the original download response.
 * @note If you want to modify single response, consider using `SDWebImageContextDownloadResponseModifier` context option.
 */

@property (nonatomic, strong, nullable) id<SDWebImageDownloaderResponseModifier> responseModifier;

/**
 * Set the decryptor to decrypt the original download data before image decoding. This can be used for encrypted image data, like Base64.
 * This decryptor method will be called for each downloading image data. Return the original data means no modification. Return nil will mark this download failed.
 * Defaults to nil, means does not modify the original download data.
 * @note When using decryptor, progressive decoding will be disabled, to avoid data corrupt issue.
 * @note If you want to decrypt single download data, consider using `SDWebImageContextDownloadDecryptor` context option.
 */
@property (nonatomic, strong, nullable) id<SDWebImageDownloaderDecryptor> decryptor;

/**
 * The configuration in use by the internal NSURLSession. If you want to provide a custom sessionConfiguration, use `SDWebImageDownloaderConfig.sessionConfiguration` and create a new downloader instance.
 @note This is immutable according to NSURLSession's documentation. Mutating this object directly has no effect.
 */
/**
 * 定义NSURLSession的configuration
 */
@property (nonatomic, readonly, nonnull) NSURLSessionConfiguration *sessionConfiguration;

/**
 * Gets/Sets the download queue suspension state.
 */
/**
 *下载队列的suspension状态
 */
@property (nonatomic, assign, getter=isSuspended) BOOL suspended;

/**
 * Shows the current amount of downloads that still need to be downloaded
 */
/**
 * 当前的下载任务数量
 */
@property (nonatomic, assign, readonly) NSUInteger currentDownloadCount;

/**
 *  Returns the global shared downloader instance. Which use the `SDWebImageDownloaderConfig.defaultDownloaderConfig` config.
 */
/**
 *  初始化当前的下载
 */
@property (nonatomic, class, readonly, nonnull) SDWebImageDownloader *sharedDownloader;

/**
 Creates an instance of a downloader with specified downloader config.
 You can specify session configuration, timeout or operation class through downloader config.

 @param config The downloader config. If you specify nil, the `defaultDownloaderConfig` will be used.
 @return new instance of downloader class
 */
/**
* 依据SDWebImageDownloaderConfig初始化
 */
- (nonnull instancetype)initWithConfig:(nullable SDWebImageDownloaderConfig *)config NS_DESIGNATED_INITIALIZER;

/**
 * Set a value for a HTTP header to be appended to each download HTTP request.
 *
 * @param value The value for the header field. Use `nil` value to remove the header field.
 * @param field The name of the header field to set.
 */
/**
* 添加一个HTTP header
 */
- (void)setValue:(nullable NSString *)value forHTTPHeaderField:(nullable NSString *)field;

/**
 * Returns the value of the specified HTTP header field.
 *
 * @return The value associated with the header field field, or `nil` if there is no corresponding header field.
 */
/**
 * 返回一个 HTTP 头部信息
 */
- (nullable NSString *)valueForHTTPHeaderField:(nullable NSString *)field;

/**
 * Creates a SDWebImageDownloader async downloader instance with a given URL
 *
 * The delegate will be informed when the image is finish downloaded or an error has happen.
 *
 * @see SDWebImageDownloaderDelegate
 *
 * @param url            The URL to the image to download
 * @param completedBlock A block called once the download is completed.
 *                       If the download succeeded, the image parameter is set, in case of error,
 *                       error parameter is set with the error. The last parameter is always YES
 *                       if SDWebImageDownloaderProgressiveDownload isn't use. With the
 *                       SDWebImageDownloaderProgressiveDownload option, this block is called
 *                       repeatedly with the partial image object and the finished argument set to NO
 *                       before to be called a last time with the full image and finished argument
 *                       set to YES. In case of error, the finished argument is always YES.
 *
 * @return A token (SDWebImageDownloadToken) that can be used to cancel this operation
 */
/**
 *创建一个异步下载任务
 *在代理方法中会暴露给外界图片下载完成或者报错
 *
 *
 * @param url            url
 * @param options        下载的options
 * @param context        之前讲过的context字典，key可以有很多种业务场景，value是我们之前规定好的几种类型
 * @param progressBlock 当下载过程中会根据progress的刷新间隔来设置progressBlock回调间隔
 *                       @并不是在主队列，需要放到主队列刷新
 * @param completedBlock 下载完成的回调block
 *
 * @return  token (SDWebImageDownloadToken) 可以取消当前的下载operation任务
 */

- (nullable SDWebImageDownloadToken *)downloadImageWithURL:(nullable NSURL *)url
                                                 completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock;

/**
 * Creates a SDWebImageDownloader async downloader instance with a given URL
 *
 * The delegate will be informed when the image is finish downloaded or an error has happen.
 *
 * @see SDWebImageDownloaderDelegate
 *
 * @param url            The URL to the image to download
 * @param options        The options to be used for this download
 * @param progressBlock  A block called repeatedly while the image is downloading
 *                       @note the progress block is executed on a background queue
 * @param completedBlock A block called once the download is completed.
 *                       If the download succeeded, the image parameter is set, in case of error,
 *                       error parameter is set with the error. The last parameter is always YES
 *                       if SDWebImageDownloaderProgressiveLoad isn't use. With the
 *                       SDWebImageDownloaderProgressiveLoad option, this block is called
 *                       repeatedly with the partial image object and the finished argument set to NO
 *                       before to be called a last time with the full image and finished argument
 *                       set to YES. In case of error, the finished argument is always YES.
 *
 * @return A token (SDWebImageDownloadToken) that can be used to cancel this operation
 */
- (nullable SDWebImageDownloadToken *)downloadImageWithURL:(nullable NSURL *)url
                                                   options:(SDWebImageDownloaderOptions)options
                                                  progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                                 completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock;

/**
 * Creates a SDWebImageDownloader async downloader instance with a given URL
 *
 * The delegate will be informed when the image is finish downloaded or an error has happen.
 *
 * @see SDWebImageDownloaderDelegate
 *
 * @param url            The URL to the image to download
 * @param options        The options to be used for this download
 * @param context        A context contains different options to perform specify changes or processes, see `SDWebImageContextOption`. This hold the extra objects which `options` enum can not hold.
 * @param progressBlock  A block called repeatedly while the image is downloading
 *                       @note the progress block is executed on a background queue
 * @param completedBlock A block called once the download is completed.
 *
 * @return A token (SDWebImageDownloadToken) that can be used to cancel this operation
 */
- (nullable SDWebImageDownloadToken *)downloadImageWithURL:(nullable NSURL *)url
                                                   options:(SDWebImageDownloaderOptions)options
                                                   context:(nullable SDWebImageContext *)context
                                                  progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                                 completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock;

/**
 * Cancels all download operations in the queue
 */
- (void)cancelAllDownloads;

/**
 * Invalidates the managed session, optionally canceling pending operations.
 * @note If you use custom downloader instead of the shared downloader, you need call this method when you do not use it to avoid memory leak
 * @param cancelPendingOperations Whether or not to cancel pending operations.
 * @note Calling this method on the shared downloader has no effect.
 */
- (void)invalidateSessionAndCancel:(BOOL)cancelPendingOperations;

@end


/**
 SDWebImageDownloader is the built-in image loader conform to `SDImageLoader`. Which provide the HTTP/HTTPS/FTP download, or local file URL using NSURLSession.
 However, this downloader class itself also support customization for advanced users. You can specify `operationClass` in download config to custom download operation, See `SDWebImageDownloaderOperation`.
 If you want to provide some image loader which beyond network or local file, consider to create your own custom class conform to `SDImageLoader`.
 */
@interface SDWebImageDownloader (SDImageLoader) <SDImageLoader>

@end

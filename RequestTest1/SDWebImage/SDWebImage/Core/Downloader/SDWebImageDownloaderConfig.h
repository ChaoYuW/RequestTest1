/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <Foundation/Foundation.h>
#import "SDWebImageCompat.h"

/// Operation execution order
typedef NS_ENUM(NSInteger, SDWebImageDownloaderExecutionOrder) {
    /**
     * Default value. All download operations will execute in queue style (first-in-first-out).
     */
    SDWebImageDownloaderFIFOExecutionOrder,
    
    /**
     * All download operations will execute in stack style (last-in-first-out).
     */
    SDWebImageDownloaderLIFOExecutionOrder
};

/**
 The class contains all the config for image downloader
 @note This class conform to NSCopying, make sure to add the property in `copyWithZone:` as well.
 */
@interface SDWebImageDownloaderConfig : NSObject <NSCopying>

/**
 Gets the default downloader config used for shared instance or initialization when it does not provide any downloader config. Such as `SDWebImageDownloader.sharedDownloader`.
 @note You can modify the property on default downloader config, which can be used for later created downloader instance. The already created downloader instance does not get affected.
 */
/**
 //单例，默认下载配置最多6个并发，15s超时
 */
@property (nonatomic, class, readonly, nonnull) SDWebImageDownloaderConfig *defaultDownloaderConfig;

/**
 * The maximum number of concurrent downloads.
 * Defaults to 6.
 */
/**
 //下载的最大并发数6个
 */
@property (nonatomic, assign) NSInteger maxConcurrentDownloads;

/**
 * The timeout value (in seconds) for each download operation.
 * Defaults to 15.0.
 */
/**
 //下载的超时时间 默认15s
 */
@property (nonatomic, assign) NSTimeInterval downloadTimeout;

/**
 * The minimum interval about progress percent during network downloading. Which means the next progress callback and current progress callback's progress percent difference should be larger or equal to this value. However, the final finish download progress callback does not get effected.
 * The value should be 0.0-1.0.
 * @note If you're using progressive decoding feature, this will also effect the image refresh rate.
 * @note This value may enhance the performance if you don't want progress callback too frequently.
 * Defaults to 0, which means each time we receive the new data from URLSession, we callback the progressBlock immediately.
 */
/**
 //最小界面progress的刷新间隔
 //当设置progressive decoding feature，我们需要展示进度，该属性表示刷新间隔
 */
@property (nonatomic, assign) double minimumProgressInterval;

/**
 * The custom session configuration in use by NSURLSession. If you don't provide one, we will use `defaultSessionConfiguration` instead.
 * Defatuls to nil.
 * @note This property does not support dynamic changes, means it's immutable after the downloader instance initialized.
 */
/**
 //NSURLSession的默认配置，当下载开始之后不支持动态修改
 */
@property (nonatomic, strong, nullable) NSURLSessionConfiguration *sessionConfiguration;

/**
 * Gets/Sets a subclass of `SDWebImageDownloaderOperation` as the default
 * `NSOperation` to be used each time SDWebImage constructs a request
 * operation to download an image.
 * Defaults to nil.
 * @note Passing `NSOperation<SDWebImageDownloaderOperation>` to set as default. Passing `nil` will revert to `SDWebImageDownloaderOperation`.
 */
/**
 //SDWebImageDownloaderOperation下载类
 */
@property (nonatomic, assign, nullable) Class operationClass;

/**
 * Changes download operations execution order.
 * Defaults to `SDWebImageDownloaderFIFOExecutionOrder`.
 */
/**
 //图片的下载执行顺序，默认是先进先出，SDWebImageDownloaderFIFOExecutionOrder
 */
@property (nonatomic, assign) SDWebImageDownloaderExecutionOrder executionOrder;

/**
 * Set the default URL credential to be set for request operations.
 * Defaults to nil.
 */
/**
 //默认是nil，为图片加载request设置一个ssl证书对象
 */
@property (nonatomic, copy, nullable) NSURLCredential *urlCredential;

/**
 * Set username using for HTTP Basic authentication.
 * Defaults to nil.
 */
/**
 //默认是nil，为http的Basic 认证设置用户名
 */
@property (nonatomic, copy, nullable) NSString *username;

/**
 * Set password using for HTTP Basic authentication.
 * Defaults to nil.
 */
/**
 //默认是nil，为http的Basic 认证设置密码
 */
@property (nonatomic, copy, nullable) NSString *password;

@end

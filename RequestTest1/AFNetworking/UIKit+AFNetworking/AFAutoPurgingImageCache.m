// AFAutoPurgingImageCache.m
// Copyright (c) 2011–2016 Alamofire Software Foundation ( http://alamofire.org/ )
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <TargetConditionals.h>

#if TARGET_OS_IOS || TARGET_OS_TV 

#import "AFAutoPurgingImageCache.h"

@interface AFCachedImage : NSObject

@property (nonatomic, strong) UIImage *image;//持有image
@property (nonatomic, copy) NSString *identifier;//唯一标识
@property (nonatomic, assign) UInt64 totalBytes;//图片占用的总字节数
@property (nonatomic, strong) NSDate *lastAccessDate;//上次获取的时间
@property (nonatomic, assign) UInt64 currentMemoryUsage;//当前使用的内存

@end

@implementation AFCachedImage
//生成一个image 计算占用空间的大小和最后的访问日期
- (instancetype)initWithImage:(UIImage *)image identifier:(NSString *)identifier {
    if (self = [self init]) {
        self.image = image;
        self.identifier = identifier;

        CGSize imageSize = CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
        //每一个像素是rgba 所以空间大小 = 像素个数*4
        //为什么一个像素占4bytes呢？因为rgba(255,255,2552,1);
        //一个255需要8位，3个需要3个8位，最后一个最大值是1，根据内存对齐，占用为4*8/8=4byte
        CGFloat bytesPerPixel = 4.0;
        CGFloat bytesPerSize = imageSize.width * imageSize.height;
        self.totalBytes = (UInt64)bytesPerPixel * (UInt64)bytesPerSize;
        self.lastAccessDate = [NSDate date];
    }
    return self;
}

- (UIImage *)accessImage {
    self.lastAccessDate = [NSDate date];
    return self.image;
}

- (NSString *)description {
    NSString *descriptionString = [NSString stringWithFormat:@"Idenfitier: %@  lastAccessDate: %@ ", self.identifier, self.lastAccessDate];
    return descriptionString;

}

@end

@interface AFAutoPurgingImageCache ()
// 用来管理缓存图片的字典
@property (nonatomic, strong) NSMutableDictionary <NSString* , AFCachedImage*> *cachedImages;
// 当前使用的内存
@property (nonatomic, assign) UInt64 currentMemoryUsage;
// 保证安全性的队列
@property (nonatomic, strong) dispatch_queue_t synchronizationQueue;
@end

@implementation AFAutoPurgingImageCache

- (instancetype)init {
    // 默认最大容量100M，首选容量60M
    return [self initWithMemoryCapacity:100 * 1024 * 1024 preferredMemoryCapacity:60 * 1024 * 1024];
}

- (instancetype)initWithMemoryCapacity:(UInt64)memoryCapacity preferredMemoryCapacity:(UInt64)preferredMemoryCapacity {
    if (self = [super init]) {
        self.memoryCapacity = memoryCapacity;
        self.preferredMemoryUsageAfterPurge = preferredMemoryCapacity;
        // 缓存集合 内存缓存 : 可变字典 Image id(url)
        self.cachedImages = [[NSMutableDictionary alloc] init];

        NSString *queueName = [NSString stringWithFormat:@"com.alamofire.autopurgingimagecache-%@", [[NSUUID UUID] UUIDString]];
        // 从它的命名我们知道它是同步的,现在把他初始化为并发的,哈哈为什么这么设计呢?---并发的,为了保证顺序,是不是有一个栅栏函数呢?哈哈
        self.synchronizationQueue = dispatch_queue_create([queueName cStringUsingEncoding:NSASCIIStringEncoding], DISPATCH_QUEUE_CONCURRENT);

        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(removeAllImages)
         name:UIApplicationDidReceiveMemoryWarningNotification
         object:nil];

    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
//队列中同步执行 返回当前内存使用大小 为什么同步呢?
//因为没有计算，只是读取值大小，只需在队列中同步执行即可。
//同步不会锁死？不是mainqueue，不会锁死。
// 多读单写
- (UInt64)memoryUsage {
    __block UInt64 result = 0;
    dispatch_sync(self.synchronizationQueue, ^{
        result = self.currentMemoryUsage;
    });
    return result;
}
/**添加图片，这里使用的是栅栏函数，主要就是多读单写，这里添加图片，相当于写，单写的，每次添加图片额时候,根据ID判断缓存中是否有缓存，如果有，那么就先将当前总共占用额缓存减去已经存在的ID对应额那个图片额缓
存，然后将新的ID图片添加到缓存，然后当前总缓存加上新的图片额缓存，接下来，判断当前的总缓存，是不是超过我们
预定号的总额memoryCapacity缓存，如果超过，就遍历所有图片，根据访问时间进行淘汰，直到剩余preferredMem
oryUsageAfterPurge这么大为止，可以比这个值小，那么就符合要求了
 */
// 缓存 : 下载 --> 图片 + id
- (void)addImage:(UIImage *)image withIdentifier:(NSString *)identifier {
    // 来了老弟,栅栏函数来了
    dispatch_barrier_async(self.synchronizationQueue, ^{
        AFCachedImage *cacheImage = [[AFCachedImage alloc] initWithImage:image identifier:identifier];
        // 字典 KVC ---> AFCachedImage -->跟新内存
        AFCachedImage *previousCachedImage = self.cachedImages[identifier];
        if (previousCachedImage != nil) {
            self.currentMemoryUsage -= previousCachedImage.totalBytes;
        }

        self.cachedImages[identifier] = cacheImage;
        self.currentMemoryUsage += cacheImage.totalBytes;
    });
    //通过栅栏函数异步执行 刷新内存image
    // 每次添加图片之后都会判定是否超出规定的最大内存空间
    dispatch_barrier_async(self.synchronizationQueue, ^{
        if (self.currentMemoryUsage > self.memoryCapacity) {
            // 需要清理的内存大小
            UInt64 bytesToPurge = self.currentMemoryUsage - self.preferredMemoryUsageAfterPurge;
            NSMutableArray <AFCachedImage*> *sortedImages = [NSMutableArray arrayWithArray:self.cachedImages.allValues];
            // 按照时间lastAccessDate属性进行排序
            NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"lastAccessDate"
                                                                           ascending:YES];
            [sortedImages sortUsingDescriptors:@[sortDescriptor]];

            UInt64 bytesPurged = 0;

            for (AFCachedImage *cachedImage in sortedImages) {
                // 移除使用时间距今最久的图片
                [self.cachedImages removeObjectForKey:cachedImage.identifier];
                bytesPurged += cachedImage.totalBytes;
                // 当前内存图片大小达到preferredMemoryCapacity 60M时,退出循环
                if (bytesPurged >= bytesToPurge) {
                    break;
                }
            }
            self.currentMemoryUsage -= bytesPurged;
        }
    });
}

- (BOOL)removeImageWithIdentifier:(NSString *)identifier {
    __block BOOL removed = NO;
    //栅栏函数 同步执行删除操作 占用内存大小更新
    dispatch_barrier_sync(self.synchronizationQueue, ^{
        AFCachedImage *cachedImage = self.cachedImages[identifier];
        if (cachedImage != nil) {
            [self.cachedImages removeObjectForKey:identifier];
            self.currentMemoryUsage -= cachedImage.totalBytes;
            removed = YES;
        }
    });
    return removed;
}
//栅栏函数同步删除all image 当前使用内存大小设置为0
- (BOOL)removeAllImages {
    __block BOOL removed = NO;
    dispatch_barrier_sync(self.synchronizationQueue, ^{
        if (self.cachedImages.count > 0) {
            [self.cachedImages removeAllObjects];
            self.currentMemoryUsage = 0;
            removed = YES;
        }
    });
    return removed;
}

- (nullable UIImage *)imageWithIdentifier:(NSString *)identifier {
    __block UIImage *image = nil;
    dispatch_sync(self.synchronizationQueue, ^{
        AFCachedImage *cachedImage = self.cachedImages[identifier];
        image = [cachedImage accessImage];
    });
    return image;
}

- (void)addImage:(UIImage *)image forRequest:(NSURLRequest *)request withAdditionalIdentifier:(NSString *)identifier {
    [self addImage:image withIdentifier:[self imageCacheKeyFromURLRequest:request withAdditionalIdentifier:identifier]];
}

- (BOOL)removeImageforRequest:(NSURLRequest *)request withAdditionalIdentifier:(NSString *)identifier {
    return [self removeImageWithIdentifier:[self imageCacheKeyFromURLRequest:request withAdditionalIdentifier:identifier]];
}

- (nullable UIImage *)imageforRequest:(NSURLRequest *)request withAdditionalIdentifier:(NSString *)identifier {
    return [self imageWithIdentifier:[self imageCacheKeyFromURLRequest:request withAdditionalIdentifier:identifier]];
}

- (NSString *)imageCacheKeyFromURLRequest:(NSURLRequest *)request withAdditionalIdentifier:(NSString *)additionalIdentifier {
    NSString *key = request.URL.absoluteString;
    if (additionalIdentifier != nil) {
        key = [key stringByAppendingString:additionalIdentifier];
    }
    return key;
}

- (BOOL)shouldCacheImage:(UIImage *)image forRequest:(NSURLRequest *)request withAdditionalIdentifier:(nullable NSString *)identifier {
    return YES;
}

@end

#endif

//
//  AppDelegate.m
//  RequestTest1
//
//  Created by CHAO on 14-9-2.
//  Copyright (c) 2014年 CHAO. All rights reserved.
//

#import "AppDelegate.h"
#import "MainViewController.h"
#import "AFNetworking.h"
#import "AFNetworkActivityIndicatorManager.h"
#import <CoreTelephony/CTCellularData.h>
#import "SDWebImage.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    
    
    NSURLCache *URLCache = [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024 diskCapacity:20 * 1024 * 1024 diskPath:nil];
    [NSURLCache setSharedURLCache:URLCache];
    
    //监听内存警告
     [[NSNotificationCenter defaultCenter]addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
            NSLog(@"内存暴涨");
            // 1.取消正在下载的操作
            [[SDWebImageManager sharedManager] cancelAll];
            // 2.清除内存缓存
            [[SDWebImageManager sharedManager].imageCache clearWithCacheType:SDImageCacheTypeAll completion:nil];
      }];
    
    [[AFNetworkActivityIndicatorManager sharedManager] setEnabled:YES];
    
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // Override point for customization after application launch.
    self.window.backgroundColor = [UIColor whiteColor];
    
    
    
    UINavigationController *rootNav = [[UINavigationController alloc] initWithRootViewController:[MainViewController new]];
    self.window.rootViewController = rootNav;
    
    [self.window makeKeyAndVisible];
    
    if (__IPHONE_10_0) {
        [self cellularData];
    }else{
        [self startMonitoringNetwork];
    }
    return YES;
}
#pragma mark - 网络权限监控
- (void)cellularData{
    
    CTCellularData *cellularData = [[CTCellularData alloc] init];
    
    cellularData.cellularDataRestrictionDidUpdateNotifier = ^(CTCellularDataRestrictedState state) {
        
        switch (state) {
            case kCTCellularDataRestrictedStateUnknown:
                NSLog(@"不明错误.....");
                break;
            case kCTCellularDataRestricted:
                NSLog(@"没有授权....");
                [self testBD]; // 默认没有授权 ... 发起短小网络 弹框
                break;
            case kCTCellularDataNotRestricted:
                NSLog(@"授权了////");
                [self startMonitoringNetwork];
                break;
            default:
                break;
        }
    };
}
#pragma mark - startMonitoringNetwork

- (void)startMonitoringNetwork{
    AFNetworkReachabilityManager *manager = [AFNetworkReachabilityManager sharedManager];
    
    [manager setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        switch (status) {
            case AFNetworkReachabilityStatusUnknown:
                NSLog(@"未知网络,请检查互联网");
                break;
            case AFNetworkReachabilityStatusNotReachable:
                NSLog(@"无网络,请检查互联网");
                break;
            case AFNetworkReachabilityStatusReachableViaWWAN:
                NSLog(@"连接蜂窝网络");
                [self testBD];
                break;
            case AFNetworkReachabilityStatusReachableViaWiFi:
                NSLog(@"WiFi网络");
                [self testBD];
                break;
            default:
                break;
        }
    }];
    [manager startMonitoring];

}

#pragma mark - 网络测试接口
- (void)testBD{
    NSString *urlString = @"http://api.douban.com/v2/movie/top250";
    NSDictionary *dic = @{@"start":@(1),
                          @"count":@(5)
                          };
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    [manager GET:urlString parameters:dic headers:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSLog(@"请求成功:%@---%@",task,responseObject);
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSLog(@"错误提示:%@---%@",task,error);
    }];
}

@end

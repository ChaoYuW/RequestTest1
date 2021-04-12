//
//  MainViewController.m
//  RequestTest1
//
//  Created by chao on 2021/3/24.
//  Copyright © 2021 CHAO. All rights reserved.
//

#import "MainViewController.h"
#import "AFNetworking.h"
#import "SDWebImage.h"
#import "UIImageView+WebCache.h"

@interface MainViewController ()

@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    
    UIImageView *imagView = [[UIImageView alloc] init];
    
    [imagView sd_setImageWithURL:[NSURL URLWithString:@""] placeholderImage:[UIImage imageNamed:@""] completed:^(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL) {
        
    }];
    
}
- (IBAction)testClick:(UIButton *)sender {
    [self get];
}
//url-request-session-task-resume
/*
 初始化：1.初始化session；2.设置很多默认值
 get:
 1.在生成request的时候处理了监听request的属性变化；
 2.参数转查询字符串；
 3.生成任务安全；
 4.通过AFURLSessionManagerTaskDelegate使得我们的进度可以通过block回调；
 5.通过AFURLSessionManagerTaskDelegate拼接我们的服务器返回数据
 */
- (void)get{
    NSString *urlStr = @"https://api.douban.com/v2/movie/top250";
    NSDictionary *dic = @{@"start":@(1),
                          @"count":@(5)
                        };
    // manager 设计模式?
    // 线程 -- 2.0 AF 常住 --- 3.0开始 NSOperationQueue
    // self.queue --- 必须要的东西 : 封装
    // request : 请求行+请求头+请求体
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.requestSerializer.timeoutInterval = 5;
//    manager.securityPolicy = [self securityPolicy];
    [manager GET:urlStr parameters:dic headers:nil progress:^(NSProgress * _Nonnull downloadProgress) {
        
    } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSLog(@"success");
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        
    }];
}
/*
 所有的分隔符以及文件内容以及参数都是要变成data拼接在一起，作为整个请求体发送给服务器
 每一行末尾有一个空行
 普通的post和multipart的post区别：
 1.content-type:
 2.httpbody/httpbodystrean
 requestserialization:1.动态监听我们的属性；2.设置请求头；3.生成查询字符串;4.分片上传
 
 总结：
 1.request序列化
    httprequest是根类，multipartformdata是重点
 2.response序列化
 
 */
- (void)multipart{
    // 1. 使用AFHTTPSessionManager的接口
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    NSDictionary *dic = @{@"businessType":@"CC_USER_CENTER",
                          @"fileType":@"image",
                          @"file":@"img.jpeg"
                          };
    //http://127.0.0.1:8080/uploadfile/
    // http://114.215.186.169:9002/api/demo/test/file
    [manager POST:@"http://114.215.186.169:9002/api/demo/test/file" parameters:dic headers:nil constructingBodyWithBlock:^(id<AFMultipartFormData>  _Nonnull formData) {
        // 在这个block中设置需要上传的文件
        NSString *path = [[NSBundle mainBundle] pathForResource:@"1" ofType:@"png"];
        // 将本地图片数据拼接到formData中 指定name
        [formData appendPartWithFileURL:[NSURL fileURLWithPath:path] name:@"file" error:nil];
        
        //或者使用这个接口拼接 指定name和filename
        NSData *picdata  =[NSData dataWithContentsOfFile:path];
        [formData appendPartWithFileData:picdata name:@"image" fileName:@"image.jpg" mimeType:@"image/jpeg"];
    } progress:^(NSProgress * _Nonnull uploadProgress) {
        NSLog(@"progress --- %@",uploadProgress.localizedDescription);
    } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSLog(@"responseObject-------%@", responseObject);
        dispatch_async(dispatch_get_main_queue(), ^{
            
        });
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSLog(@"Error-------%@", error);
    }];
    
}

- (AFSecurityPolicy *)securityPolicy{
    
    // .crt --->.cer
    NSString *cerPath = [[NSBundle mainBundle] pathForResource:@"https" ofType:@"cer"];
    NSData   *data    = [NSData dataWithContentsOfFile:cerPath];
    NSLog(@"%@",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    NSSet    *cerSet  = [NSSet setWithObject:data];
    
    AFSecurityPolicy *security = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeCertificate withPinnedCertificates:cerSet];
    [AFSecurityPolicy defaultPolicy];
    
    security.allowInvalidCertificates = YES;
    security.validatesDomainName      = NO;
    return security;
}


@end

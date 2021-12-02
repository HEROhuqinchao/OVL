//
//  PhotoManager.h
//  APAASTools
//
//  Created by 胡勤超 on 2021/11/29.
//

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#if __has_include(<ADYLiveSDK/ADYLiveSDK.h>)
#import <ADYLiveSDK/CMHFileManager.h>
#import <ADYLiveSDK/ADYLiveSession.h>
#else
#import "CMHFileManager.h"
#import "ADYLiveSession.h"
#endif

//#define AppName [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"]
//#define AppProject [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"]
//#define AppLocalMediaAddr [NSTemporaryDirectory() stringByAppendingPathComponent:AppProject]//App媒体保存地址
NS_ASSUME_NONNULL_BEGIN

@interface PhotoManager : NSObject

/** 创建文件路径 根据文件后缀*/
+(NSString*) tempFilePath:(NSString*)extension;
/**  删除文件 根据文件后缀*/
+(BOOL)deleteLiveRecording:(NSString*)extension;
/** 创建自定义相册 */
+ (void)isExistFolder:(NSString * _Nonnull)folderName
        andBackaction:(void(^ _Nullable)(PHAssetCollection * _Nullable assetCollection))backAction;
+(void)createFolder:(NSString *_Nonnull)folderName
      andBackaction:(void(^ _Nullable)(PHAssetCollection *_Nullable assetCollection))backAction;
//path为视频下载到本地之后的本地路径
+ (void)saveVideoToAlbum:(NSString * _Nullable)path videoToAlbum:(NSString  * _Nullable)videoToAlbum callBack:(void(^ _Nullable)(BOOL  success))backAction;
@end

NS_ASSUME_NONNULL_END

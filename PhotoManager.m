//
//  PhotoManager.m
//  APAASTools
//
//  Created by 胡勤超 on 2021/11/29.
//

#import "PhotoManager.h"



@implementation PhotoManager

+(NSString*) tempFilePath:(NSString*)extension {
    NSString *absolutePath = live_recording(extension);
    if (![CMHFileManager isFileAtPath:absolutePath]) {
        [CMHFileManager createFileAtPath:absolutePath overwrite:NO];
    }
    return absolutePath;
}

+(BOOL)deleteLiveRecording:(NSString*)extension
{
    NSString *absolutePath = live_recording(extension);
    return [CMHFileManager removeItemAtPath:absolutePath];
}

/** 创建自定义相册 */
+ (void)isExistFolder:(NSString * _Nonnull)folderName
        andBackaction:(void(^ _Nullable)(PHAssetCollection * _Nullable assetCollection))backAction{
    
    __block BOOL isExists = NO;
    
    //首先获取用户手动创建相册的集合
    PHFetchResult *collectonResuts = [PHCollectionList fetchTopLevelUserCollectionsWithOptions:nil];
    
    //对获取到集合进行遍历
    [collectonResuts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        PHAssetCollection *assetCollection = obj;
        //folderName是我们写入照片的相册
        if ([assetCollection.localizedTitle isEqualToString:folderName])  {
            isExists = YES;
            
            if (backAction) backAction(assetCollection);
        }
    }];
    
    if (!isExists) {
        if (backAction) backAction(nil);
    }
}

+(void)createFolder:(NSString *_Nonnull)folderName
      andBackaction:(void(^ _Nullable)(PHAssetCollection *_Nullable assetCollection))backAction {
    
    [PhotoManager isExistFolder:folderName
                  andBackaction:^(PHAssetCollection * _Nullable assetCollection) {
        //存在
        if (assetCollection) {
            if (backAction) backAction(assetCollection);
        }
        //不存在
        else{
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                //添加HUD文件夹
                [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:folderName];
            } completionHandler:^(BOOL success, NSError * _Nullable error) {
                if (success) {
                    NSLog(@"创建相册文件夹成功!");
                    [PhotoManager isExistFolder:folderName
                                  andBackaction:^(PHAssetCollection * _Nullable assetCollection) {
                        if (backAction) backAction(assetCollection);
                    }];
                } else {
                    NSLog(@"创建相册文件夹失败:%@", error);
                    if (backAction) backAction(nil);
                }
            }];
        }
    }];
}

//videoPath为视频下载到本地之后的本地路径
+ (void)saveVideoToAlbum:(NSString * _Nullable)path videoToAlbum:(NSString  * _Nullable)videoToAlbum callBack:(void(^ _Nullable)(BOOL  success))backAction{
    
    NSURL *videoPath = [NSURL URLWithString:path];
    [PhotoManager createFolder:videoToAlbum
                 andBackaction:^(PHAssetCollection *assetCollection) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                //请求创建一个Asset
                PHAssetChangeRequest *assetRequest = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:videoPath];
                //请求编辑相册
                PHAssetCollectionChangeRequest *collectonRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:assetCollection];
                //为Asset创建一个占位符，放到相册编辑请求中
                PHObjectPlaceholder *placeHolder = [assetRequest placeholderForCreatedAsset];
                //相册中添加视频
                [collectonRequest addAssets:@[placeHolder]];
            } completionHandler:^(BOOL success, NSError *error) {
                NSString *extension = [path lastPathComponent]; /// live_recording.mov
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSLog(@"保存视频%@!", success ? @"成功" : @"失败");
                    //保存成功，删除原文件
                    if ([PhotoManager deleteLiveRecording:extension]) {
                        NSLog(@"删除源文件成功");
                    }else{
                        NSLog(@"删除失败");
                    }
                    backAction(success);
                });
            }];
        });
    }];
}

@end

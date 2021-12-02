//
//  Module:   ADYSystemVideoCapture   @ ADYLiveSDK
//
//  Function: 奥点云直播推流用 RTMP SDK
//
//  Copyright © 2021 杭州奥点科技股份有限公司. All rights reserved.
//
//  Version: 1.1.0  Creation(版本信息)

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <GLKit/GLKit.h>
#if __has_include(<ADYLiveSDK/ADYLiveSDK.h>)
#import <ADYLiveSDK/ADYLiveVideoConfiguration.h>
#import <ADYLiveSDK/ADYLiveSession.h>
#else
#import "ADYLiveVideoConfiguration.h"
#import "ADYLiveSession.h"
#endif





@class GLKViewManager;
/** ADYSystemVideoCapture callback videoData - 视频数据处理回调 */
@protocol GLKViewManagerDelegate <NSObject>
- (void)captureSYSOutput:(nullable GLKViewManager *)capture pixelBuffer:(nullable CVPixelBufferRef)pixelBuffer timeStamp:(uint64_t)timeStamp;
@end


@class OVLScript;
@interface GLKViewManager : UIView
<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>
-(void) loadScript:(OVLScript*_Nonnull)script;
-(void) switchScript:(OVLScript*_Nonnull)script;
@property (nullable, nonatomic, weak) id<GLKViewManagerDelegate> delegate;
-(void) snapshot:(BOOL)sound callback:(void (^_Nonnull)(UIImage* _Nonnull image))callback;

-(IBAction) resetShader;
@property (nonatomic) BOOL fHD;
@property (nonatomic) BOOL fPhotoRatio; // 4x3 instead of 16x9
@property (nonatomic) BOOL fRecording;
@property (nonatomic, readonly) NSInteger duration;
@property (nonatomic) GLuint renderbufferEx; // for external monitor
@property (nonatomic, readonly) EAGLContext* _Nonnull  context;
@property (nonatomic) BOOL fProcessAudio;
@property (nonatomic) float speed;
@property (nonatomic) CMTime maxDuration;
@property (nonatomic) UIImage* _Nullable imageTexture;
@property (nonatomic) CMTime timeRecorded;
@property (nonatomic) BOOL fNoAudio;
@property (nonatomic, retain) AVAsset* _Nullable assetSrc;

/**
 * The running control start capture or stop capture
 * 正在运行的控件启动捕获或停止捕获
 */
@property (nonatomic, assign) BOOL running;

/**
 * The captureDevicePosition control camraPosition ,default front
 * 摄像头翻转 - 默认为前置
 */
@property (nonatomic, assign) AVCaptureDevicePosition captureDevicePosition;

/**
 * The torch control capture flash is on or off
 * 闪光灯打开或关闭
 */
@property (nonatomic, assign) BOOL torch;

/**
 * The mirror control mirror of front camera is on or off
 * 前摄像头的镜像打开或关闭
 */
@property (nonatomic, assign) BOOL mirror;


/**
 * The torch control camera zoom scale default 1.0, between 1.0 ~ 3.0
 * 控制摄像头缩放比例默认为1.0，介于1.0~3.0之间
 */
@property (nonatomic, assign, readonly) CGFloat zoomScale;

/**
 * The videoFrameRate control videoCapture output data count
 * videoFrameRate控制videoCapture 视频帧率
 */
@property (nonatomic, assign) NSInteger videoFrameRate;

/**
 * The beautyFace control capture shader filter empty or beautiy
 * 是否开启 美颜滤镜
 */
@property (nonatomic, assign) BOOL beautyFace;

/**
 * 控制美颜程度 -- 磨皮，默认为0，介于0~10之间
 */
@property (nonatomic, assign) CGFloat beautyLevel;

/**
 * 控制亮度 -- 美白级别，默认为5，介于0~10之间
 */
@property (nonatomic, assign) CGFloat brightLevel;

/**
 * 控制红润 -- 红润级别，默认为5，介于0~10之间
 */
@property (nonatomic, assign) CGFloat toneLevel;
/**
 滤镜数组 方便切换使用
 */
@property (nonatomic, strong) NSArray< FilterModel *>* _Nullable filterNames;

@property (nonatomic, assign) NSInteger filterIndex;
/**
 * 控制滤镜  传递颜色查找表数据
 * 0 无滤镜 正常
 * 1 清新
 * 2 白亮
 * 3 暖色
 * 4 唯美
 */
@property (nonatomic, readonly) NSString * _Nullable filterLookupName;
/**
 设置滤镜文件和强度
 */
- (void)setFilterLookupName:(NSString *_Nullable)filterLookupName intensity:(CGFloat)intensity index:(NSInteger) index;
/**
 * The warterMarkView control whether the watermark is displayed or not ,if set ni,will remove watermark,otherwise add
 * warterMarkView 控制是否显示水印，如果设置为ni，则删除水印，否则添加水印
 *.*/
@property (nonatomic, strong, nullable) UIView *warterMarkView;

/**
 * The currentImage is videoCapture shot
 * 当前图像为视频捕获快照
 */
@property (nonatomic, strong, nullable) UIImage *currentImage;
/**
 * The saveLocalVideo is save the local video
 * 是否保存本地视频
 */
@property (nonatomic, assign) BOOL saveLocalVideo;

/**
 * The saveLocalVideoPath is save the local video  path
 * saveLocalVideoPath 是保存本地视频路径
 */
@property (nonatomic, strong, nullable) NSURL *saveLocalVideoPath;

/**
 *   The designated initializer. Multiple instances with the same configuration will make the
   capture unstable.
 *   指定的初始值设定项。具有相同配置的多个实例将使
 捕获不稳定。
 
 */
- (instancetype _Nullable )initWithFrame:(CGRect)frame configuration:(ADYLiveVideoConfiguration *_Nullable)configuration;

/** 采集过程中动态修改视频分辨率 */
- (void)changeSessionPreset:(AVCaptureSessionPreset _Nonnull )sessionPreset;

/** 手动缩放画面 */
-(void)setZoomScale:(CGFloat )zoomScale;

/** 点击聚焦*/
-(void) setFocusPoint:(CGPoint)point;
/**
 * 录制
 * 开始录制：
 * @param localFileURL 录制路径
 */
- (void)startRecordingToLocalFileURL:(NSURL *_Nullable)localFileURL;

/**
 * 停止录制
 */
- (void)stopRecording;



@end

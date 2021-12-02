//
//  CameraManager.h
//  APAASTools
//
//  Created by 胡勤超 on 2021/11/25.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>

#if __has_include(<ADYLiveSDK/ADYLiveSDK.h>)
#import <ADYLiveSDK/ADYLiveVideoConfiguration.h>

#else
#import "ADYLiveVideoConfiguration.h"

#endif


NS_ASSUME_NONNULL_BEGIN

@interface CameraManager : NSObject
/** 采集会话 负责输入和输出设备之间的数据传递 */
@property (strong,nonatomic) AVCaptureSession* captureSession;
/** 采集输入设备 也就是摄像头或者麦克风  负责从AVCaptureDevice获得输入数据 */
/** 视频设备 */
@property (strong,nonatomic) AVCaptureDeviceInput    *videoCaptureDeviceInput;
/** 音频设备 */
@property (strong,nonatomic) AVCaptureDeviceInput    *audioCaptureDeviceInput;
/** 采集输出 */
@property (nonatomic, strong) AVCaptureVideoDataOutput *captureVideoDataOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput *captureAudioDataOutput;
/** 输出连接 */
@property (strong, nonatomic) AVCaptureConnection        *audioConnection; //音频录制连接
@property (strong, nonatomic) AVCaptureConnection        *videoConnection; //视频录制连接
/** 录制方向 */
@property(nonatomic) AVCaptureVideoOrientation videoOrientation;
/** 相机位置 */
@property(nonatomic) AVCaptureDevicePosition captureDevicePosition;
/** 队列 */
@property (copy  , nonatomic) dispatch_queue_t             captureQueue; //录制的队列
/** 写入 */
@property (strong, nonatomic) AVAssetWriter* videoWriter;
@property (strong, nonatomic) AVAssetWriterInput* videoInput;
@property (strong, nonatomic) AVAssetWriterInputPixelBufferAdaptor* adaptor;
@property (strong, nonatomic) AVAssetWriterInput* audioInput;
/** 是否静音 控制录制模式是否录入声音 */
@property (nonatomic, assign) BOOL muted;
/// 单利
+ (instancetype)sharedSingletonWithConfiguration:(ADYLiveVideoConfiguration *)configuration;
/**
 * 代理设置
 */
- (void)setAudioDelegate:(nullable id<AVCaptureAudioDataOutputSampleBufferDelegate>)sampleBufferDelegate;
- (void)setVideoDelegate:(nullable id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate;
/**
 *  初始化AVCapture会话
 */
- (void)initAVCaptureSession;
/**
 *  开启摄像头采集
 */
- (void)sessionLayerRunning;
/**
 * 结束摄像头采集
 */
- (void)sessionLayerStop;
/**
 * 开启录制
 */
- (void)startRecording:(NSURL *_Nullable)localFileURL;
/**
 * 停止录制回调
 */
- (void)stopRecordingWithCompletionHandler:(void(^_Nullable)(BOOL  success))completionHandler;
/**
 * 切换摄像头
 */
- (void)setCaptureDevicePosition:(AVCaptureDevicePosition)captureDevicePosition;
/**
 * 设置闪光灯
 */
- (void)setTorch:(BOOL)torch;
/**
 * 设置帧率
 */
- (NSError *)adjustFrameRate:(float)frameRate;
/**
 * 采集过程中动态修改视频分辨率
 */
- (void)changeSessionPreset:(AVCaptureSessionPreset)sessionPreset;
/**
 * 设置镜像
 */
- (void)reloadMirror:(BOOL)mirror;
/**
 * 添加用户操作手势
 */
-(void)initTapGesture:(UIView *)view;
/**
 * 设置聚焦点 -- 相机坐标
 * @param focusPoint 聚焦点
 */
-(void)autoFocusAtPoint:(CGPoint )focusPoint;
/**
 * 设置聚焦点 -- 屏幕坐标坐标
 * @param point 聚焦点
 */
-(void) setFocusPoint:(CGPoint)point view:(UIView * _Nullable)view;
/**
 * 设置缩放
 */
- (void)setZoomScale:(CGFloat)zoomScale;
@end

NS_ASSUME_NONNULL_END

//
//  CameraManager.m
//  APAASTools
//
//  Created by 胡勤超 on 2021/11/25.
//

#import "CameraManager.h"
/// 相机属性改变统一配置方法
typedef void(^PropertyChangeBlock)(AVCaptureDevice *captureDevice);

@interface CameraManager ()
<
UIGestureRecognizerDelegate
>
@property (nonatomic, strong) ADYLiveVideoConfiguration *configuration;

/// 捏合缩放摄像头 默认最大3.0倍放大
@property (nonatomic,assign) CGFloat zoomScale;                                  /// 记录开始的缩放比例
@property (nonatomic,assign) CGFloat currentPinchZoomFactor;                                        /// 最后的缩放比例
/// 镜像控制 -- 默认前置生效
@property (nonatomic, assign) BOOL mirror;

@property (nonatomic, assign) OSType videoFormat;
@end


@implementation CameraManager

/// 单利
//+ (instancetype)sharedSingleton {
//    static CameraManager *_sharedSingleton = nil;
//    static dispatch_once_t onceToken;
//    dispatch_once(&onceToken, ^{
//        //不能再使用alloc方法
//        //因为已经重写了allocWithZone方法，所以这里要调用父类的分配空间的方法
//        _sharedSingleton = [[super allocWithZone:NULL] init];
//    });
//    return _sharedSingleton;
//}

+ (instancetype)sharedSingletonWithConfiguration:(ADYLiveVideoConfiguration *)configuration{
    CameraManager *cameraManager = [[CameraManager alloc]init];
    cameraManager.configuration = configuration;
    cameraManager.videoFormat = kCVPixelFormatType_32BGRA;
    cameraManager.zoomScale = 1.0;
    cameraManager.currentPinchZoomFactor = 1.0;
    cameraManager.mirror = YES;
    // 将要改变状态栏的方向-- 通知
    [[NSNotificationCenter defaultCenter] addObserver:cameraManager selector:@selector(statusBarChanged:) name:UIApplicationWillChangeStatusBarOrientationNotification object:nil];
    
    // 相机检测变化通知
    [[NSNotificationCenter defaultCenter] addObserver:cameraManager selector:@selector(setFocusPointAuto) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:nil];
    return cameraManager;
}

//// 防止外部调用alloc 或者 new
//+ (instancetype)allocWithZone:(struct _NSZone *)zone {
//    return [CameraManager sharedSingleton];
//}
//// 防止外部调用mutableCopy
//- (id)mutableCopyWithZone:(nullable NSZone *)zone {
//    return [CameraManager sharedSingleton];
//}
//// 防止外部调用copy
//- (id)copyWithZone:(nullable NSZone *)zone {
//    return [CameraManager sharedSingleton];
//}

/// 初始化
//- (instancetype)init {
//    if (self = [super init]) {
//        videoFormat = kCVPixelFormatType_32BGRA;
//        self.zoomScale = 1.0;
//        self.currentPinchZoomFactor = 1.0;
//        self.mirror = YES;
//        // 将要改变状态栏的方向-- 通知
//        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusBarChanged:) name:UIApplicationWillChangeStatusBarOrientationNotification object:nil];
//
//        // 相机检测变化通知
//        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setFocusPointAuto) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:nil];
//    }
//    return self;
//}

#pragma mark ---- 相机控制手势初始化

-(void)initTapGesture:(UIView *)view
{
    UIPinchGestureRecognizer *pinchGestureRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchGestureDetected:)];
    [pinchGestureRecognizer setDelegate:self];
    /*加载到要处理的View*/
    [view addGestureRecognizer:pinchGestureRecognizer];
    UITapGestureRecognizer *singleFingerOne = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                      action:@selector(handleFocusClickAction:)];
    singleFingerOne.numberOfTouchesRequired = 1; //手指数
    singleFingerOne.numberOfTapsRequired = 1; //tap次数
    singleFingerOne.delegate = self;
    [view addGestureRecognizer:singleFingerOne];
}

- (void)pinchGestureDetected:(UIPinchGestureRecognizer *)recognizer{
    /*获取状态*/
    UIGestureRecognizerState state = [recognizer state];
    if (state == UIGestureRecognizerStateBegan){
        _currentPinchZoomFactor = _zoomScale;
    }
    /*获取捏合大小比例*/
    CGFloat scale = [recognizer scale];
    CGFloat   zoomFactor = _currentPinchZoomFactor * scale;
    [self setZoomScale: (zoomFactor < 1) ? 1 : ((zoomFactor > 3) ? 3 : zoomFactor)];
    _zoomScale = (zoomFactor < 1) ? 1 : ((zoomFactor > 3) ? 3 : zoomFactor);
}

/** 更改焦距操作*/
-(void)handleFocusClickAction:(UIPinchGestureRecognizer *)recognizer{
    CGPoint  point = [recognizer locationInView:recognizer.view];
    //    [self.focusView frameByAnimationCenter:point];
    [self setFocusPoint:point view:recognizer.view];
}

#pragma mark - 相机初始化

/**
 *  初始化AVCapture会话
 */
- (void)initAVCaptureSession
{
    
    [self captureSession];
    //1、添加 "视频" 与 "音频" 输入流到session
    [self setupVideo];
    [self setupAudio];
    // 白平衡和防抖效果
    [self setupCamera];
    
}

/**
 *  设置视频输入输出
 */
- (void)setupVideo
{
    if (self.videoCaptureDeviceInput) {
        // 添加摄像头的输入 -- 默认后置
        if ([_captureSession canAddInput:self.videoCaptureDeviceInput]) {
            [_captureSession addInput:self.videoCaptureDeviceInput];
        }
    } else {
        NSLog(@"OVLVC no camerainput " );
    }
    
    if (self.captureVideoDataOutput) {
        // 添加视频输出
        if ([_captureSession canAddOutput:self.captureVideoDataOutput]) {
            [_captureSession addOutput:self.captureVideoDataOutput];
        }
    } else {
        NSLog(@"OVLVC no cameraoutput " );
    }
}

/**
 *  设置音频录入输出
 */
- (void)setupAudio
{
    if (self.audioCaptureDeviceInput) {
        // 添加麦克风输入
        if ([_captureSession canAddInput:self.audioCaptureDeviceInput]) {
            [_captureSession addInput:self.audioCaptureDeviceInput];
        }
    } else {
        NSLog(@"OVLVC no microphoneinput " );
    }
    // 添加音频输出
    if (self.captureAudioDataOutput) {
        if ([_captureSession canAddOutput:self.captureAudioDataOutput]) {
            [_captureSession addOutput:self.captureAudioDataOutput];
        }
    } else {
        NSLog(@"OVLVC no microphoneoutput " );
    }
}

/**
 相机参数  白平衡和防抖
 */
- (void)setupCamera
{
    /// 自动白平衡
    if ([self.videoCaptureDeviceInput.device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeAutoWhiteBalance]) {
        [self.videoCaptureDeviceInput.device setWhiteBalanceMode:AVCaptureWhiteBalanceModeAutoWhiteBalance];
    }
    /// 防抖功能
    if ([self.videoConnection isVideoStabilizationSupported]) {
        self.videoConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeStandard;
    }
    /// 设置分辨率
    if ([_captureSession canSetSessionPreset:self.configuration.avSessionPreset])
    {
        _captureSession.sessionPreset = self.configuration.avSessionPreset;
    }
    // 设置视频采集方向
    if (self.videoConnection.isVideoOrientationSupported) {
        self.videoConnection.videoOrientation = self.configuration.videoOrientation;
    }
    /// 设置帧率
    [self adjustFrameRate:self.configuration.videoFrameRate];
    /// 设置镜像
    [self reloadMirror:self.mirror];
}

#pragma mark ---- 相机控制
// 开启摄像头采集
- (void)sessionLayerRunning
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self.captureSession isRunning]) {
            [self.captureSession startRunning];
            
        }
    });
}

// 结束摄像头采集
- (void)sessionLayerStop
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.captureSession isRunning]) {
            NSLog(@"CameraSource: stopRunning");
            [self.captureSession stopRunning];
        }
    });
}

// 开启录制
- (void)startRecording:(NSURL *_Nullable)localFileURL
{
    NSError* error = nil;
    _videoWriter = [[AVAssetWriter alloc] initWithURL:localFileURL fileType:AVFileTypeQuickTimeMovie
                                                error:&error];
    _videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                     outputSettings:@{
        AVVideoCodecKey:AVVideoCodecTypeH264,
        //AVVideoCompressionPropertiesKey:compression,
        AVVideoWidthKey:[NSNumber numberWithInt:self.configuration.videoSize.width],
        AVVideoHeightKey:[NSNumber numberWithInt:self.configuration.videoSize.height]
    }];
    
    AVCaptureVideoOrientation orientation = AVCaptureVideoOrientationPortrait;
    switch([UIDevice currentDevice].orientation) {
        case UIDeviceOrientationLandscapeLeft:
            orientation = AVCaptureVideoOrientationLandscapeRight;
            break;
        case UIDeviceOrientationLandscapeRight:
            orientation = AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            orientation = AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        default:
            break;
    }
    _videoInput.expectsMediaDataInRealTime = YES;
    
    [_videoWriter addInput:_videoInput];
    
    NSDictionary* attr = @{
        (id)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithInt:kCVPixelFormatType_32BGRA],
        (id)kCVPixelBufferWidthKey: [NSNumber numberWithInteger:self.configuration.videoSize.width],
        (id)kCVPixelBufferHeightKey: [NSNumber numberWithInteger:self.configuration.videoSize.height]
    };
    _adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoInput sourcePixelBufferAttributes:attr];
    if (!self.muted) {
        // Configure the channel layout as stereo.
        AudioChannelLayout stereoChannelLayout = {
            .mChannelLayoutTag = kAudioChannelLayoutTag_Stereo,
            .mChannelBitmap = 0,
            .mNumberChannelDescriptions = 0
        };
        
        // Convert the channel layout object to an NSData object.
        NSData *channelLayoutAsData = [NSData dataWithBytes:&stereoChannelLayout
                                                     length:offsetof(AudioChannelLayout, mChannelDescriptions)];
        NSDictionary* audioSettings = @{
            AVFormatIDKey: [NSNumber numberWithUnsignedInt:kAudioFormatMPEG4AAC],
            AVEncoderBitRateKey  : [NSNumber numberWithInteger:128000],
            AVSampleRateKey : [NSNumber numberWithInteger:44100],
            AVChannelLayoutKey : channelLayoutAsData,
            AVNumberOfChannelsKey : [NSNumber numberWithUnsignedInteger:2]
        };
        _audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioSettings];
        [_videoWriter addInput:_audioInput];
    }
    [_videoWriter startWriting];
}

// 结束录制
- (void)stopRecordingWithCompletionHandler:(void(^_Nullable)(BOOL  success))completionHandler
{
    [_videoInput markAsFinished];
    NSLog(@"finishig %ld", (long)_videoWriter.status);
    [_videoWriter finishWritingWithCompletionHandler:^{
        NSLog(@"done");
        completionHandler(true);
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_videoWriter = nil;
            self->_videoInput = nil;
            self->_audioInput = nil;
            self->_adaptor = nil;
        });
    }];
    if (_videoWriter.status == AVAssetWriterStatusFailed) {
        NSLog(@"finish failed %@", _videoWriter.error);
        completionHandler(false);
    }
}

#pragma mark ---- 代理传递设置
- (void)setAudioDelegate:(nullable id<AVCaptureAudioDataOutputSampleBufferDelegate>)sampleBufferDelegate{
    [self.captureAudioDataOutput setSampleBufferDelegate:sampleBufferDelegate queue:self.captureQueue];
}

- (void)setVideoDelegate:(nullable id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate{
    [self.captureVideoDataOutput setSampleBufferDelegate:sampleBufferDelegate queue:self.captureQueue];
}

#pragma mark ---- 采集基础设置
/** 切换摄像头*/
- (void)setCaptureDevicePosition:(AVCaptureDevicePosition)captureDevicePosition {
    /// 切换摄像头，重置缩放比例
    _currentPinchZoomFactor = 1.0f;
    _zoomScale = 1.0f;
    if(captureDevicePosition ==  [self.videoCaptureDeviceInput.device position]) return;
    [self reverseCamera:captureDevicePosition];
    // 设置帧率
    [self adjustFrameRate:self.configuration.videoFrameRate];
    //设置镜像
    [self reloadMirror:self.mirror];
}

-(void)reverseCamera:(AVCaptureDevicePosition)captureDevicePosition{
    AVCaptureDevice *camera = [self cameraWithPosition:captureDevicePosition];
    // 获取当前摄像头方向
    AVCaptureDevicePosition currentPosition = self.videoCaptureDeviceInput.device.position;
    AVCaptureDevicePosition toPosition = AVCaptureDevicePositionUnspecified;
    if (currentPosition == AVCaptureDevicePositionBack || currentPosition == AVCaptureDevicePositionUnspecified)
    {
        toPosition = AVCaptureDevicePositionFront;
    }
    else
    {
        toPosition = AVCaptureDevicePositionBack;
    }
    NSError *error = nil;
    AVCaptureDeviceInput *newInput = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
    // 修改输入设备
    [self.captureSession beginConfiguration];
    // 删除之前的输入
    [self.captureSession removeInput:self.videoCaptureDeviceInput];
    // 重新添加输入
    if ([_captureSession canAddInput:newInput])
    {
        [_captureSession addInput:newInput];
        self.videoCaptureDeviceInput = newInput;
    }
    [self.captureSession commitConfiguration];
    
    // 重新获取连接
    self.videoConnection = [self.captureVideoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    // 设置摄像头镜像，不设置的话前置摄像头采集出来的图像是反转的
    if (toPosition == AVCaptureDevicePositionFront && self.videoConnection.supportsVideoMirroring)
    {
        self.videoConnection.videoMirrored = self.mirror;
    }
    
    // 设置视频录制方向
    if (self.videoConnection.isVideoOrientationSupported) {
        self.videoConnection.videoOrientation = self.configuration.videoOrientation;
    }
}

-(void)setVideoOrientation:(AVCaptureVideoOrientation)videoOrientation
{
    if (self.videoConnection.isVideoOrientationSupported) {
        self.videoConnection.videoOrientation = videoOrientation;
    }
}

/** 设置闪光灯*/
- (void)setTorch:(BOOL)torch {
    if (!self.captureSession) return;
    [self changeDevice:YES withProperty:^(AVCaptureDevice *captureDevice) {
        if (captureDevice.torchAvailable) {
            [captureDevice setTorchMode:(torch ? AVCaptureTorchModeOn : AVCaptureTorchModeOff) ];
        }
    }];
}

/** 设置帧率 */
- (NSError *)adjustFrameRate:(float)frameRate
{
    NSError *error = nil;
    int maxFrameRate = [self getMaxFrameRateByCurrentResolutionWithResolutionHeight:self.configuration.videoSize.height
                                                                           position:self.configuration.devicePosition
                                                                        videoFormat:self.videoFormat];
    if (frameRate > maxFrameRate) {
        NSLog(@"%s: Auto adjust, current frame rate:%ld > max frame rate:%d",__func__,(long)frameRate,maxFrameRate);
        frameRate = maxFrameRate;
    }
    [self setCameraFrameRateAndResolutionWithFrameRate:frameRate
                                   andResolutionHeight:self.configuration.videoSize.height
                                             bySession:_captureSession
                                              position:self.configuration.devicePosition
                                           videoFormat:self.videoFormat];
    return error;
}

- (int)getMaxFrameRateByCurrentResolutionWithResolutionHeight:(int)resolutionHeight position:(AVCaptureDevicePosition)position videoFormat:(OSType)videoFormat {
    float maxFrameRate = 0;
    AVCaptureDevice *captureDevice = [self cameraWithPosition:position];
    for(AVCaptureDeviceFormat *vFormat in [captureDevice formats]) {
        CMFormatDescriptionRef description = vFormat.formatDescription;
        CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(description);
        if (CMFormatDescriptionGetMediaSubType(description) == videoFormat && dims.height == resolutionHeight && dims.width == [self getResolutionWidthByHeight:resolutionHeight]) {
            float maxRate = vFormat.videoSupportedFrameRateRanges.firstObject.maxFrameRate;
            if (maxRate > maxFrameRate) {
                maxFrameRate = maxRate;
            }
        }
    }
    return maxFrameRate;
}

- (BOOL)setCameraFrameRateAndResolutionWithFrameRate:(int)frameRate andResolutionHeight:(CGFloat)resolutionHeight bySession:(AVCaptureSession *)session position:(AVCaptureDevicePosition)position videoFormat:(OSType)videoFormat {
    AVCaptureDevice *captureDevice = [self cameraWithPosition:position];
    BOOL isSuccess = NO;
    for(AVCaptureDeviceFormat *vFormat in [captureDevice formats]) {
        CMFormatDescriptionRef description = vFormat.formatDescription;
        float maxRate = ((AVFrameRateRange*) [vFormat.videoSupportedFrameRateRanges objectAtIndex:0]).maxFrameRate;
        if (maxRate >= frameRate && CMFormatDescriptionGetMediaSubType(description) == videoFormat) {
            if ([captureDevice lockForConfiguration:NULL] == YES) {
                // 对比镜头支持的分辨率和当前设置的分辨率
                CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(description);
                if (dims.height == resolutionHeight && dims.width == [self getResolutionWidthByHeight:resolutionHeight]) {
                    [session beginConfiguration];
                    if ([captureDevice lockForConfiguration:NULL]){
                        captureDevice.activeFormat = vFormat;
                        [captureDevice setActiveVideoMinFrameDuration:CMTimeMake(1, frameRate)];
                        [captureDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, frameRate)];
                        [captureDevice unlockForConfiguration];
                    }
                    [session commitConfiguration];
                    
                    return YES;
                }
            }else {
                NSLog(@"%s: lock failed!",__func__);
            }
        }
    }
    NSLog(@"Set camera frame is success : %d, frame rate is %lu, resolution height = %f",isSuccess,(unsigned long)frameRate,resolutionHeight);
    return NO;
}

- (int)getResolutionWidthByHeight:(int)height {
    switch (height) {
        case 2160:
            return 3840;
        case 1080:
            return 1920;
        case 720:
            return 1280;
        case 480:
            return 640;
        default:
            return -1;
    }
}

/** 采集过程中动态修改视频分辨率 */
- (void)changeSessionPreset:(AVCaptureSessionPreset)sessionPreset
{
    if ([self.captureSession canSetSessionPreset:sessionPreset])
    {
        self.captureSession.sessionPreset = sessionPreset;
    }
}

//设置镜像
- (void)reloadMirror:(BOOL)mirror
{
    if (self.videoConnection.isVideoMirroringSupported && self.captureDevicePosition == AVCaptureDevicePositionFront) {
        if(mirror){
            self.videoConnection.videoMirrored = YES;
        }else{
            self.videoConnection.videoMirrored = NO;
        }
    }
}

/**自动聚焦*/
-(void) setFocusPointAuto{
    [self setFocusPoint:CGPointMake(0.5, 0.5) view:nil];
}

/**点击聚焦*/
-(void) setFocusPoint:(CGPoint)point view:(UIView * _Nullable)view
{
    if ([self.videoCaptureDeviceInput.device isFocusPointOfInterestSupported] || [self.videoCaptureDeviceInput.device isExposurePointOfInterestSupported]) {
        CGPoint  convertedFocusPoint = [self convertToPointOfInterestFromViewCoordinates:point captureVideoPreviewLayer:view];
        [self autoFocusAtPoint:convertedFocusPoint];
    }
}

/**
 *  设置聚焦点
 *
 *  @param focusPoint 聚焦点
 */
-(void)autoFocusAtPoint:(CGPoint )focusPoint
{
    [self changeDevice:NO withProperty:^(AVCaptureDevice *captureDevice)
     {
        // 聚焦
        if ([captureDevice isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus])
        {
            [captureDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
        }
        if ([captureDevice isFocusPointOfInterestSupported])
        {
            [captureDevice setFocusPointOfInterest:focusPoint];
        }
        // 曝光
        if ([captureDevice isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
        {
            [captureDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        }
        if ([captureDevice isExposurePointOfInterestSupported])
        {
            [captureDevice setExposurePointOfInterest:focusPoint];
        }
        // 接收画面动态变化通知
        [captureDevice setSubjectAreaChangeMonitoringEnabled:YES];
    }];
}

-(CGPoint )convertToPointOfInterestFromViewCoordinates:(CGPoint )viewCoordinates  captureVideoPreviewLayer:(UIView *)view{
    CGPoint pointOfInterest = CGPointMake(0.5, 0.5);
    if (view) {
        CGSize frameSize = [view frame].size;
        // 坐标转换
        pointOfInterest = CGPointMake(viewCoordinates.y / frameSize.height, 1 - viewCoordinates.x / frameSize.width);
        if (self.captureDevicePosition == AVCaptureDevicePositionFront) {
            pointOfInterest = CGPointMake(pointOfInterest.x, 1 - pointOfInterest.y);
        }
    }
    return  pointOfInterest;
}

/// 获取当前视频采集设备位置
- (AVCaptureDevicePosition)captureDevicePosition {
    return [self.videoCaptureDeviceInput.device position];
}

/**
 设置缩放
 */
- (void)setZoomScale:(CGFloat)zoomScale
{
    if (self.videoCaptureDeviceInput && self.videoCaptureDeviceInput.device) {
        [self changeDevice:NO withProperty:^(AVCaptureDevice *captureDevice) {
            captureDevice.videoZoomFactor = zoomScale;
        }];
    }
}

#pragma mark ---- 通知方法
- (void)statusBarChanged:(NSNotification *)notification {
    /**
     AVCaptureVideoOrientationPortrait           = 1,
     AVCaptureVideoOrientationPortraitUpsideDown = 2,
     AVCaptureVideoOrientationLandscapeRight     = 3,
     AVCaptureVideoOrientationLandscapeLeft       = 4,
     */
    NSLog(@"UIApplicationWillChangeStatusBarOrientationNotification. UserInfo: %@", notification.userInfo);
    UIInterfaceOrientation statusBar = [[UIApplication sharedApplication] statusBarOrientation];
    if(self.configuration.autorotate){
        if (self.configuration.landscape) {
            if (statusBar == UIInterfaceOrientationLandscapeLeft) {
                self.videoConnection.videoOrientation  =  AVCaptureVideoOrientationLandscapeRight;
            } else if (statusBar == UIInterfaceOrientationLandscapeRight) {
                self.videoConnection.videoOrientation   = AVCaptureVideoOrientationLandscapeLeft;
            }
        } else {
            if (statusBar == UIInterfaceOrientationPortrait) {
                self.videoConnection.videoOrientation  =  AVCaptureVideoOrientationPortraitUpsideDown;
            } else if (statusBar == UIInterfaceOrientationPortraitUpsideDown) {
                self.videoConnection.videoOrientation  =  AVCaptureVideoOrientationPortrait;
            }
        }
    }
}

#pragma mark ---- 公共方法

/**
 *  改变设备属性的统一操作方法
 *
 *  @param propertyChange 属性改变操作
 */
- (void)changeDevice:(BOOL)beginConfiguration withProperty:(PropertyChangeBlock)propertyChange
{
    AVCaptureSession *session = (AVCaptureSession *)self.captureSession;
    
    AVCaptureDevice *captureDevice = [self.videoCaptureDeviceInput device];
    NSError *error;
    if (beginConfiguration) [session beginConfiguration];
    //注意改变设备属性前一定要首先调用lockForConfiguration:调用完之后使用unlockForConfiguration方法解锁
    if ([captureDevice lockForConfiguration:&error])
    {
        propertyChange(captureDevice);
        [captureDevice unlockForConfiguration];
    }
    else
    {
        NSLog(@"设置设备属性过程发生错误，错误信息：%@",error.localizedDescription);
    }
    if (beginConfiguration) [session commitConfiguration];
}

#pragma mark ---- 采集输出控制懒加载

/** captureSession*/
- (AVCaptureSession *)captureSession {
    if (!_captureSession) {
        _captureSession = [[AVCaptureSession alloc] init];
    }
    return  _captureSession;
}

// 摄像头输入
- (AVCaptureDeviceInput *)videoCaptureDeviceInput {
    if (!_videoCaptureDeviceInput) {
        NSError *error;
        _videoCaptureDeviceInput =[AVCaptureDeviceInput deviceInputWithDevice:[self cameraWithPosition:AVCaptureDevicePositionBack] error:&error];
    }
    return _videoCaptureDeviceInput;
}

// 麦克风输入
- (AVCaptureDeviceInput *)audioCaptureDeviceInput {
    if (!_audioCaptureDeviceInput) {
        NSError *error;
        _audioCaptureDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:[self microphoneWithPosition:AVCaptureDevicePositionBack] error:&error];
    }
    return  _audioCaptureDeviceInput;
}

//视频输出
//kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange格式 无法渲染 使用
- (AVCaptureVideoDataOutput *)captureVideoDataOutput {
    if (!_captureVideoDataOutput) {
        _captureVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        _captureVideoDataOutput.videoSettings = @{
            (id)kCVPixelBufferPixelFormatTypeKey:[NSNumber numberWithInt:self.videoFormat]
        };
    }
    return _captureVideoDataOutput;
}

//音频输出
- (AVCaptureAudioDataOutput *)captureAudioDataOutput {
    if (!_captureAudioDataOutput) {
        _captureAudioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
        
    }
    return _captureAudioDataOutput;
}

//视频连接
- (AVCaptureConnection *)videoConnection {
    if (!_videoConnection) {
        _videoConnection = [self.captureVideoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    }
    return _videoConnection;
}

//音频连接
- (AVCaptureConnection *)audioConnection {
    if (_audioConnection == nil) {
        _audioConnection = [self.captureAudioDataOutput connectionWithMediaType:AVMediaTypeAudio];
    }
    return _audioConnection;
}

// 录制对列
- (dispatch_queue_t)captureQueue {
    if (!_captureQueue) {
        _captureQueue = dispatch_get_main_queue();
    }
    return  _captureQueue;
}

#pragma  mark --- 获取设备
// 摄像头设备
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position {
    // 获取所有摄像头
    NSArray *cameras = nil;
    if (@available(iOS 10.0, *)) {
        AVCaptureDeviceDiscoverySession *captureDeviceDiscoverySession =  [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
        cameras = captureDeviceDiscoverySession.devices;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        cameras = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
#pragma clang diagnostic pop
    }
    //遍历这些设备返回跟position相关的设备
    for (AVCaptureDevice *device in cameras) {
        if ([device position] == position) {
            return device;
        }
    }
    return nil;
}
// 麦克风设备
- (AVCaptureDevice *)microphoneWithPosition:(AVCaptureDevicePosition)position {
    // 获取所有麦克风
    NSArray *microphones = nil;
    if (@available(iOS 10.0, *)) {
        AVCaptureDeviceDiscoverySession *captureDeviceDiscoverySession =  [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInMicrophone] mediaType:AVMediaTypeAudio position:AVCaptureDevicePositionUnspecified];
        microphones = captureDeviceDiscoverySession.devices;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        microphones = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
#pragma clang diagnostic pop
    }
    //遍历这些设备返回跟position相关的设备
    for (AVCaptureDevice *device in microphones) {
        if ([device position] == position) {
            return device;
        }
    }
    return nil;
}
@end

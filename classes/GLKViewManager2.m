//
//  OpenGLViewController.m
//
//  Created by Satoshi Nakajima on 9/23/13.
//  Copyright (c) 2013 Satoshi Nakajima. All rights reserved.
//
// http://stackoverflow.com/questions/5808557/avassetwriterinputpixelbufferadaptor-and-cmtime
// http://stackoverflow.com/questions/9550297/faster-alternative-to-glreadpixels-in-iphone-opengl-es-2-0/9704392#9704392
//

#import <Accelerate/Accelerate.h>
#import "GLKViewManager.h"
#import "OVLPlaneShaders.h"
#import "OVLScript.h"
#import "OVLTexture.h"
#import "OVLFilter.h"
#import <UIKit/UIKit.h>
#import "ADYAdjustFocusView.h"
#import "CMHFileManager.h"



@interface GLKViewManager ()

<
UIGestureRecognizerDelegate,
GLKViewDelegate
>
{
    __weak IBOutlet GLKView *_glkView;
    OVLPlaneShaders* _shader;
    OVLScript* _script;
    CGSize _size;
    BOOL _fInitializingShader;
    CGFloat _clipRatio;
    BOOL _isRecord;
    BOOL capturePaused; //采集状态--用于设备进入后台 阻断相机数据采集
    OSType videoFormat;
    
    /** 设备*/
    AVCaptureDevice* _camera;
    AVCaptureStillImageOutput* _stillImageOutput;
    
    CVOpenGLESTextureRef _videoTexture;
    CVOpenGLESTextureCacheRef _textureCache;
    NSMutableArray  *_filters;
    //
    AVAssetWriter* _videoWriter;
    AVAssetWriterInput* _videoInput;
    AVAssetWriterInputPixelBufferAdaptor* _adaptor;
    AVAssetWriterInput* _audioInput;
    BOOL _fFirstFrame;
    CMTime _timeStamp, _startTime;
    BOOL _fUpdated;
    NSInteger _duration;
    // Fast buffer
    CVPixelBufferRef _renderPixelBuffer;
    CVOpenGLESTextureRef _renderTexture;
    // External display support
    GLuint _frameBufferEx;
    
    // FFT
    FFTSetup _fftSetup;
    DSPSplitComplex _fftA;
    CMItemCount _fftSize;
    
    
    // assetSrc
    AVAssetReader *_assetReader;
    AVAssetReaderTrackOutput* _assetReaderOutput;
    AVAssetReaderAudioMixOutput *_audioMixOutput;
    CGAffineTransform _assetTransform;
}
/** 采集会话 负责输入和输出设备之间的数据传递*/
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
@property (strong, nonatomic) AVCaptureConnection        *audioConnection;//音频录制连接
@property (strong, nonatomic) AVCaptureConnection        *videoConnection;//视频录制连接

/** 队列 */
@property (copy  , nonatomic) dispatch_queue_t             captureQueue;//录制的队列

/** 是否已经在采集 */
@property (nonatomic, assign) BOOL isCapturing;
@property (nonatomic, assign)CGFloat  zoomScale;
@property (nonatomic, assign)CGFloat  currentPinchZoomFactor;
@property (nonatomic, strong) ADYLiveVideoConfiguration *configuration;
@property (nonatomic, assign)NSInteger  frameRate;
//@property (nonatomic, strong) ADYAdjustFocusView *focusView;
@end

@implementation GLKViewManager
@dynamic duration;
@dynamic context;
@synthesize filterIndex = _filterIndex;
@synthesize torch = _torch;
@synthesize beautyLevel = _beautyLevel;
@synthesize brightLevel = _brightLevel;
@synthesize toneLevel = _toneLevel;
@synthesize filterLookupName = _filterLookupName;

@synthesize zoomScale = _zoomScale;

+(NSString*) tempFilePath:(NSString*)extension {
    NSString *absolutePath = live_recording(extension)
    if (![CMHFileManager isFileAtPath:absolutePath]) {
        [CMHFileManager createFileAtPath:absolutePath overwrite:NO];
    }
    return absolutePath;
}
+(void)deleteLiveRecording:(NSString*)extension{
    NSString *absolutePath = live_recording(extension)
    [CMHFileManager removeItemAtPath:absolutePath];
}

-(GLKView*) glkView {
    return _glkView;
}


-(EAGLContext*) context {
    return _glkView.context;
}

-(NSInteger) duration {
    return _duration;
}

-(AVCaptureDevice*) camera {
    return _camera;
}
#pragma mark  instancetype---initWithFrame
- (instancetype)initWithFrame:(CGRect)frame configuration:(ADYLiveVideoConfiguration *)configuration {
    if (self = [super initWithFrame:frame]) {
        self= [[[NSBundle mainBundle] loadNibNamed:@"GLKViewManager"owner:self options:nil] firstObject];
        self.frame = frame;
        _configuration = configuration;
        [OVLFilter setFrontCameraMode:NO];
        
        
        
        
        
        
        
        
        _isRecord = NO;
        self.fHD = YES;
        [self initFilter];
        [self initTapGesture];
    }
    return self;
}
- (void)awakeFromNib
{
    [super awakeFromNib];
    
}
- (void)setFilterNames:(NSArray<FilterModel *> *)filterNames
{
    _filterNames = filterNames;
    /**此处定义滤镜切换效果*/
    _filters = [NSMutableArray new];
    for (FilterModel *model in filterNames) {
        NSDictionary* extra = @{
            @"pipeline":@[
                @{
                    @"filter":@"lookup",
                    @"attr": @{
                        @"texture": model.name,
                        @"intensity": [NSNumber numberWithFloat:model.intensity]
                    },
                },
            ],
        };
        OVLScript* script = [[OVLScript alloc] initWithDictionary:extra];
        [_filters addObject:script];
    }
}
-(void)initFilter{
    videoFormat = kCVPixelFormatType_32BGRA;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterBackground:) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForeground:) name:UIApplicationDidBecomeActiveNotification object:nil];
    //将要改变状态栏的方向-- 通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusBarChanged:) name:UIApplicationWillChangeStatusBarOrientationNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setFocusPointAuto) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:nil];
    self.beautyLevel = 5;
    self.toneLevel = 5;
    self.brightLevel = 5;
    self.zoomScale = 1.0;
    self.currentPinchZoomFactor = 1.0;
    self.mirror = YES;
    
    // Initialize FFT
    _fftSetup = vDSP_create_fftsetup(11, kFFTRadix2);

    // Initialize the view's layer
    _glkView.contentScaleFactor = [UIScreen mainScreen].scale;
    CAEAGLLayer* eaglLayer = (CAEAGLLayer*)_glkView.layer;
    eaglLayer.opaque = YES;
    eaglLayer.contentsScale = _glkView.contentScaleFactor;
    _glkView.delegate = self;
    // Initialize the context
    _glkView.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!_glkView.context || ![EAGLContext setCurrentContext:_glkView.context]) {
        NSLog(@"Failed to initialize or set current OpenGL context");
        exit(1);
    }
    self.maxDuration = kCMTimeIndefinite;
}

-(void)initTapGesture{
    UIPinchGestureRecognizer *pinchGestureRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchGestureDetected:)];
    [pinchGestureRecognizer setDelegate:self];
    /*加载到要处理的View*/
    [self addGestureRecognizer:pinchGestureRecognizer];
    UITapGestureRecognizer *singleFingerOne = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                      action:@selector(handleDoubleClickAction:)];
    singleFingerOne.numberOfTouchesRequired = 1; //手指数
    singleFingerOne.numberOfTapsRequired = 1; //tap次数
    singleFingerOne.delegate = self;
    [self addGestureRecognizer:singleFingerOne];
}
-(void) _setupVideoCaptureSession {
    ///5
    [self captureSession];
    
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
    [self _addCamera]; // back
    
    // 自动白平衡
    if ([self.videoCaptureDeviceInput.device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeAutoWhiteBalance]) {
        [self.videoCaptureDeviceInput.device setWhiteBalanceMode:AVCaptureWhiteBalanceModeAutoWhiteBalance];
    }
    if (self.captureVideoDataOutput) {
        // 添加视频输出
        if ([_captureSession canAddOutput:self.captureVideoDataOutput]) {
            [_captureSession addOutput:self.captureVideoDataOutput];
        }
    }
    // 设置视频录制方向
    if (self.videoConnection.isVideoOrientationSupported) {
        self.videoConnection.videoOrientation = self.configuration.videoOrientation;
    }
    // For still image
    _stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    [_stillImageOutput setOutputSettings:@{AVVideoCodecKey:AVVideoCodecTypeJPEG}];
    if (![_captureSession canAddOutput:_stillImageOutput]) {
        NSLog(@"OVLVC Can't add stillImageOutput");
    }
    [_captureSession addOutput:_stillImageOutput];
}
-(void) _addCamera {
    ///6
    AVCaptureDevicePosition position = [self.videoCaptureDeviceInput.device position];
    _camera = nil;
    _camera = [self cameraWithPosition:position];
    if (_camera) {
        // 设置分辨率
        if ([_captureSession canSetSessionPreset:self.configuration.avSessionPreset])
        {
            _captureSession.sessionPreset = self.configuration.avSessionPreset;
        }
        if (self.videoCaptureDeviceInput) {
            // 添加摄像头的输入 -- 默认后置
            if ([_captureSession canAddInput:self.videoCaptureDeviceInput]) {
                [_captureSession addInput:self.videoCaptureDeviceInput];
            }
        }
        
        // 设置摄像头镜像，不设置的话前置摄像头采集出来的图像是反转的
        [self reloadMirror:self.mirror];
        // 设置帧率
        [self adjustFrameRate:self.configuration.videoFrameRate];
        _glkView.transform = (position==AVCaptureDevicePositionFront) ? CGAffineTransformMakeScale(-1.0, 1.0) : CGAffineTransformIdentity;
    }
}


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
// 麦克风输入
- (AVCaptureDeviceInput *)audioCaptureDeviceInput {
    if (!_audioCaptureDeviceInput) {
        NSError *error;
        _audioCaptureDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:[self microphoneWithPosition:AVCaptureDevicePositionBack] error:&error];
    }
    return  _audioCaptureDeviceInput;
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
//视频输出
//kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange格式 无法渲染 使用
- (AVCaptureVideoDataOutput *)captureVideoDataOutput {
    if (!_captureVideoDataOutput) {
        _captureVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        _captureVideoDataOutput.videoSettings = @{
            (id)kCVPixelBufferPixelFormatTypeKey:[NSNumber numberWithInt:videoFormat]
        };
        [_captureVideoDataOutput setSampleBufferDelegate:self queue:self.captureQueue];
        
    }
    return _captureVideoDataOutput;
}
//音频输出
- (AVCaptureAudioDataOutput *)captureAudioDataOutput {
    if (!_captureAudioDataOutput) {
        _captureAudioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
        [_captureAudioDataOutput setSampleBufferDelegate:self queue:self.captureQueue];
    }
    return _captureAudioDataOutput;
}
//视频连接
- (AVCaptureConnection *)videoConnection {
    if (!_videoConnection) {
        _videoConnection = [self.captureVideoDataOutput connectionWithMediaType:AVMediaTypeVideo];
        //防抖功能
        if ([_videoConnection isVideoStabilizationSupported]) {
            _videoConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeStandard;
        }
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
//设置帧率
- (NSError *)adjustFrameRate:(float)frameRate
{
    NSError *error = nil;
    int maxFrameRate = [self getMaxFrameRateByCurrentResolutionWithResolutionHeight:self.configuration.videoSize.height
                                                                           position:self.configuration.devicePosition
                                                                        videoFormat:videoFormat];
    if (frameRate > maxFrameRate) {
        NSLog(@"%s: Auto adjust, current frame rate:%ld > max frame rate:%d",__func__,(long)frameRate,maxFrameRate);
        frameRate = maxFrameRate;
    }
    [self setCameraFrameRateAndResolutionWithFrameRate:frameRate
                                   andResolutionHeight:self.configuration.videoSize.height
                                             bySession:_captureSession
                                              position:self.configuration.devicePosition
                                           videoFormat:videoFormat];
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
- (void)reloadMirror:(BOOL)mirror{
    if (self.videoConnection.isVideoMirroringSupported && self.captureDevicePosition == AVCaptureDevicePositionFront) {
        if(mirror){
            self.videoConnection.videoMirrored = YES;
        }else{
            self.videoConnection.videoMirrored = NO;
        }
    }
}
// 开启摄像头采集
- (void)sessionLayerRunning{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self.captureSession isRunning]) {
            [self.captureSession startRunning];
            
        }
    });
}
// 结束摄像头采集
- (void)sessionLayerStop{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.captureSession isRunning]) {
            [self.captureSession stopRunning];
        }
    });
}

-(IBAction) resetShader {
    [_shader cleanupNodelist];
    _shader = nil;
    [self _tearDownRenderTarget];
}

- (void)setCaptureDevicePosition:(AVCaptureDevicePosition)captureDevicePosition {
    if(captureDevicePosition ==  [self.videoCaptureDeviceInput.device position]) return;
    [OVLFilter setFrontCameraMode:(captureDevicePosition == AVCaptureDevicePositionFront)];
    [self reverseCamera:captureDevicePosition];
    // 设置帧率
    [self adjustFrameRate:self.configuration.videoFrameRate];
    //设置镜像
    [self reloadMirror:self.mirror];
}

-(void)reverseCamera:(AVCaptureDevicePosition)captureDevicePosition {
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
    
    [self resetShader];
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
- (AVCaptureDevicePosition)captureDevicePosition {
    return [self.videoCaptureDeviceInput.device position];
}

- (void)setVideoFrameRate:(NSInteger)videoFrameRate {
    
    if (videoFrameRate <= 0) return;
    _frameRate = videoFrameRate;
    // 设置帧率
    [self adjustFrameRate:self.configuration.videoFrameRate];
}

- (NSInteger)videoFrameRate {
    return _frameRate;
}

- (void)setTorch:(BOOL)torch {
    BOOL ret = false;
    if (!self.captureSession) return;
    AVCaptureSession *session = (AVCaptureSession *)self.captureSession;
    [session beginConfiguration];
    if (self.videoCaptureDeviceInput.device) {
        if (self.videoCaptureDeviceInput.device.torchAvailable) {
            NSError *err = nil;
            if ([self.videoCaptureDeviceInput.device lockForConfiguration:&err]) {
                [self.videoCaptureDeviceInput.device setTorchMode:(torch ? AVCaptureTorchModeOn : AVCaptureTorchModeOff) ];
                [self.videoCaptureDeviceInput.device unlockForConfiguration];
                ret = (self.videoCaptureDeviceInput.device.torchMode == AVCaptureTorchModeOn);
            } else {
                NSLog(@"Error while locking device for torch: %@", err);
                ret = false;
            }
        } else {
            NSLog(@"Torch not available in current camera input");
        }
    }
    [session commitConfiguration];
    _torch = ret;
}
/**
 闪光灯
 */
- (BOOL)torch {
    return self.videoCaptureDeviceInput.device.torchMode;
}
/**
 镜像
 */
- (void)setMirror:(BOOL)mirror {
    _mirror = mirror;
    [self reloadMirror:mirror];
}
/**
 开启美颜
 */
- (void)setBeautyFace:(BOOL)beautyFace{
    _beautyFace = beautyFace;
    self.configuration.beautyFace = beautyFace;
    _shader = nil;
    [_script compile];
}
/**
 美颜程度 --磨皮
 */
- (void)setBeautyLevel:(CGFloat)beautyLevel {
    if (beautyLevel >=10) {
        beautyLevel = 10;
    }
    if (beautyLevel <=0) {
        beautyLevel = 0;
    }
    CGFloat number = beautyLevel/10*2.5;
    _beautyLevel = number;
    _shader = nil;
    [_script compile];
}

- (CGFloat)beautyLevel {
    return _beautyLevel;
}
/**
 美白程度
 */
- (void)setBrightLevel:(CGFloat)brightLevel {
    if (brightLevel >=10) {
        brightLevel = 10;
    }
    if (brightLevel <=0) {
        brightLevel = 0;
    }
    CGFloat number = brightLevel/10;
    _brightLevel = number;
    _shader = nil;
    [_script compile];
}

- (CGFloat)brightLevel {
    return _brightLevel;
}
/**
 色调强度
 */
- (void)setToneLevel:(CGFloat)toneLevel{
    if (toneLevel >=10) {
        toneLevel = 10;
    }
    if (toneLevel <=0) {
        toneLevel = 0;
    }
    CGFloat number = toneLevel/10;
    _toneLevel = number;
    _shader = nil;
    [_script compile];
}

- (CGFloat)toneLevel{
    return _toneLevel;
}
/**
 控制滤镜显示
 */
- (void)setFilterLookupName:(NSString *)filterLookupName intensity:(CGFloat)intensity index:(NSInteger)index
{
    _filterLookupName = filterLookupName;
    _filterIndex = index;
    NSDictionary* extra = @{
        @"pipeline":@[
            @{
                @"filter":@"lookup",
                @"attr": @{
                    @"texture": filterLookupName,
                    @"intensity": [NSNumber numberWithFloat:intensity]
                },
            },
        ],
    };
    OVLScript* scriptExtra = [[OVLScript alloc] initWithDictionary:extra];
    [self switchScript:scriptExtra];
}
- (NSString *)filterLookupName{
    return _filterLookupName;
}

/**
 缩放
 */
- (void)setZoomScale:(CGFloat)zoomScale {
    if (self.videoCaptureDeviceInput && self.videoCaptureDeviceInput.device) {
        AVCaptureDevice *device = (AVCaptureDevice *)self.videoCaptureDeviceInput.device;
        if ([device lockForConfiguration:nil]) {
            device.videoZoomFactor = zoomScale;
            [device unlockForConfiguration];
            _zoomScale = zoomScale;
        }
    }
}

- (CGFloat)zoomScale {
    return _zoomScale;
}

//-(ADYAdjustFocusView *)focusView{
//    if (!_focusView) {
//        _focusView = [[ADYAdjustFocusView alloc]initWithFrame:CGRectMake(0, 0, 80, 80)];
//        _focusView.hidden = YES;
//        [self addSubview:self.focusView];
//    }
//    return _focusView;
//}
/**点击聚焦*/
-(void) setFocusPoint:(CGPoint)point{
    if ([self.videoCaptureDeviceInput.device isFocusPointOfInterestSupported]) {
        CGPoint  convertedFocusPoint = [self convertToPointOfInterestFromViewCoordinates:point captureVideoPreviewLayer:self.videoConnection.videoPreviewLayer];
        [self autoFocusAtPoint:convertedFocusPoint];
    }
}

/**自动聚焦*/
-(void) setFocusPointAuto{
    [self setFocusPoint:self.center];
}

-(void)autoFocusAtPoint:(CGPoint )point{
    NSError *err = nil;
    if ([self.videoCaptureDeviceInput.device isFocusPointOfInterestSupported] && [self.videoCaptureDeviceInput.device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        if ([self.videoCaptureDeviceInput.device lockForConfiguration:&err]) {
            self.videoCaptureDeviceInput.device.exposurePointOfInterest = point;
            self.videoCaptureDeviceInput.device.exposureMode = AVCaptureExposureModeAutoExpose;
            self.videoCaptureDeviceInput.device.focusPointOfInterest = point;
            self.videoCaptureDeviceInput.device.focusMode = AVCaptureFocusModeAutoFocus;
            [self.videoCaptureDeviceInput.device unlockForConfiguration];
        }
    }
}
-(CGPoint )convertToPointOfInterestFromViewCoordinates:(CGPoint )viewCoordinates  captureVideoPreviewLayer:(AVCaptureVideoPreviewLayer *)captureVideoPreviewLayer{
    CGPoint pointOfInterest = CGPointMake(0.5, 0.5);
    CGPoint coordinates = viewCoordinates;
    CGSize  frameSize = captureVideoPreviewLayer.frame.size;
    if ([self.videoConnection isVideoMirrored]) {
        coordinates.x = frameSize.width - coordinates.x;
    }
    pointOfInterest = [captureVideoPreviewLayer captureDevicePointOfInterestForPoint:coordinates];
    return  pointOfInterest;
}
#pragma  mark setTouchZoomScale 更改焦距

-(void)handleDoubleClickAction:(UIPinchGestureRecognizer *)recognizer{
    CGPoint  point = [recognizer locationInView:recognizer.view];
//    [self.focusView frameByAnimationCenter:point];
    [self setFocusPoint:point];
    
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
}


#pragma mark Notification

- (void)willEnterBackground:(NSNotification *)notification {
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    capturePaused = YES;
    [self resetShader];
    
}

- (void)willEnterForeground:(NSNotification *)notification {
    capturePaused = NO;
    [UIApplication sharedApplication].idleTimerDisabled = YES;
}


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

- (IBAction)swipedWithCender:(UISwipeGestureRecognizer *)sender {
    int  delta = (sender.direction == UISwipeGestureRecognizerDirectionRight) ? -1 : 1;
    _filterIndex = (_filterIndex + delta + _filters.count) % _filters.count;
    NSLog(@"向%@滑动,选取%ld",(delta == -1) ? @"右" : @"左",_filterIndex);
    [self switchScript:_filters[_filterIndex]];
    
}

-(void)setRunning:(BOOL)running
{
    if (_running == running) return;
    _running = running;
    if (!_running) {
        if (!self.isCapturing)
        {
            return;
        }
        // 自动锁屏
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].idleTimerDisabled = NO;
        });
        // 结束采集
        [self sessionLayerStop];
        self.isCapturing = NO;
    } else {
        if (self.isCapturing)
        {
            return;
        }
        // 不自动锁屏
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIApplication sharedApplication].idleTimerDisabled = YES;
        });
        [self captureLoad];
    }
}
-(void)captureLoad{
    OVLScript* scriptExtra = _filters[_filterIndex];
    __weak typeof(self) _self = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(_self) self = _self;
        [self loadScript:scriptExtra];
        // 开始采集
        [self sessionLayerRunning];
        self.isCapturing = YES;
    });
}

-(void) switchScript:(OVLScript*)script {
    _shader = nil;
    _script = script;
    [_script compile];
}

-(void) loadScript:(OVLScript*)script {
    _script = script;
    ///4
    [_script compile];
    // Initialize the view's properties
    _glkView.drawableDepthFormat = GLKViewDrawableDepthFormatNone;
    //_glkView.drawableMultisample = GLKViewDrawableMultisample4X;
    _glkView.drawableColorFormat = GLKViewDrawableColorFormatRGB565;
    
    CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _glkView.context, NULL, &_textureCache);
    if (self.assetSrc) {
        _assetReader = [AVAssetReader assetReaderWithAsset:self.assetSrc error:nil];
        NSArray *videoTracks = [self.assetSrc tracksWithMediaType:AVMediaTypeVideo];
        NSDictionary* settings = @{ (id)kCVPixelBufferPixelFormatTypeKey:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]};
        AVAssetTrack* videoTrack = videoTracks[0];
        _assetTransform = videoTrack.preferredTransform;
        _assetReaderOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack outputSettings:settings];
        //[AVAssetReaderVideoCompositionOutput assetReaderVideoCompositionOutputWithVideoTracks:videoTracks videoSettings:settings];
        [_assetReader addOutput:_assetReaderOutput];
        
        NSArray *audioTracks = [self.assetSrc tracksWithMediaType:AVMediaTypeAudio];
        if (audioTracks.count > 0) {
            NSLog(@"OVLVC has audioTracks, %lu", (unsigned long)audioTracks.count);
            NSDictionary *decompressionAudioSettings = @{ AVFormatIDKey : [NSNumber numberWithUnsignedInt:kAudioFormatLinearPCM] };
            _audioMixOutput = [AVAssetReaderAudioMixOutput assetReaderAudioMixOutputWithAudioTracks:audioTracks audioSettings:decompressionAudioSettings];
            AVMutableAudioMix* mutableAudioMix = [AVMutableAudioMix audioMix];
            _audioMixOutput.audioMix = mutableAudioMix;
            [_assetReader addOutput:_audioMixOutput];
        }
        [_assetReader startReading];
        [self _setInitialSize:videoTrack.naturalSize];
    } else {
        [self _setupVideoCaptureSession];
    }
    
    // deferred
#if TARGET_IPHONE_SIMULATOR
    [self _initShader:image.size];
#endif
}

-(void) _initShader:(CGSize)size {
    NSLog(@"OVC _initShader: %.0f,%.0f", size.width, size.height);
    NSArray* nodes = _script.nodes;
    if (_clipRatio > 1.0) {
        NSLog(@"OVC _clipRatio is %f", _clipRatio);
        NSDictionary* extra = @{
            @"pipeline":@[
                @{ @"filter":@"stretch", @"attr":@{
                    @"ratio":@[@1.0, [NSNumber numberWithFloat:_clipRatio]] } },
            ]
        };
        OVLScript* scriptExtra = [[OVLScript alloc] initWithDictionary:extra];
        [scriptExtra compile];
        NSMutableArray* nodesNew = [NSMutableArray arrayWithArray:scriptExtra.nodes];
        [nodesNew addObjectsFromArray:nodes];
        nodes = nodesNew;
    }
   
    if (self.beautyFace) {
        float tone = (0.1 + 0.3 * _toneLevel);
        float beauty2 = (1.0 - 0.3 * _beautyLevel);
        float beauty1 = (1.0 - 0.6 * _beautyLevel);
        float bright = 0.6 * (-0.5 + _brightLevel);
        NSArray *params = @[
            [NSNumber numberWithFloat:beauty1],
            [NSNumber numberWithFloat:beauty2],
            [NSNumber numberWithFloat:tone],
            [NSNumber numberWithFloat:tone],
        ];
        CGPoint offset = CGPointMake(2.0f / _size.width, 2.0f / _size.height);
        NSDictionary* extra = @{
            @"pipeline":@[
                @{ @"filter":@"beauty",
                   @"attr":@{
                       @"brightness":[NSNumber numberWithFloat:bright],
                       @"params":params,
                       @"singleStepOffset":@[[NSNumber numberWithFloat:offset.x], [NSNumber numberWithFloat:offset.y]],
                   }
                }
            ]
        };
        OVLScript* scriptExtra = [[OVLScript alloc] initWithDictionary:extra];
        [scriptExtra compile];
        NSMutableArray* nodesNew = [NSMutableArray arrayWithArray:nodes];
        [nodesNew addObjectsFromArray:scriptExtra.nodes];
        nodes = nodesNew;
    }
    
    if (self.warterMarkView) {
        NSDictionary* extra = @{
            @"pipeline":@[
                @{ @"filter":@"watermark",
                   @"attr":@{
                       @"scale":[NSNumber numberWithFloat:50.0/480.0 /*size.height*/],
                       @"ratio":@1.0, // 透明度
                   }
                }
            ]
        };
        OVLScript* scriptExtra = [[OVLScript alloc] initWithDictionary:extra];
        [scriptExtra compile];
        NSMutableArray* nodesNew = [NSMutableArray arrayWithArray:nodes];
        [nodesNew addObjectsFromArray:scriptExtra.nodes];
        nodes = nodesNew;
    }
    if (self.imageTexture) {
        NSLog(@"OVLVC imageOrientation %ld", (long)self.imageTexture.imageOrientation);
        NSDictionary* extra = @{
            @"pipeline":@[
                @{ @"source":@"texture" },
                @{ @"filter":@"rotation" },
                @{ @"filter":@"stretch" },
                @{ @"filter":@"timedzoom" },
            ]
        };
        OVLScript* scriptExtra = [[OVLScript alloc] initWithDictionary:extra];
        OVLTexture* nodeTexture = [scriptExtra.nodes objectAtIndex:0];
        if ([nodeTexture isKindOfClass:[OVLTexture class]]) {
            // taking the orientation out
            UIGraphicsBeginImageContextWithOptions(self.imageTexture.size, NO, self.imageTexture.scale);
            [self.imageTexture drawInRect:(CGRect){0, 0, self.imageTexture.size}];
            nodeTexture.imageTexture = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        }
        OVLFilter* nodeRotation = [scriptExtra.nodes objectAtIndex:1];
        OVLFilter* nodeStretch = [scriptExtra.nodes objectAtIndex:2];
        float angle = 0.0;
        //CGImageRef imageRef = self.imageTexture.CGImage;
        //CGSize size = { CGImageGetWidth(imageRef), CGImageGetHeight(imageRef) };
        CGSize size = nodeTexture.imageTexture.size;
        CGSize sizeOut = { 9.0, 16.0 };
        float ratioX = size.width / sizeOut.width;
        float ratioY = size.height / sizeOut.height;
        switch ([UIDevice currentDevice].orientation) {
            case UIDeviceOrientationPortrait:
                angle = M_PI_2;
                break;
            case UIDeviceOrientationPortraitUpsideDown:
                angle = -M_PI_2;
                break;
            case UIDeviceOrientationLandscapeRight:
                angle = M_PI;
                // fall through
            default:
                ratioX = size.height / sizeOut.width;
                ratioY = size.width / sizeOut.height;
                break;
        }
        if (ratioX < ratioY) {
            ratioY = ratioY / ratioX;
            ratioX = 1.0;
        } else {
            ratioX = ratioX / ratioY;
            ratioY = 1.0;
        }
        [nodeRotation setAttr:[NSNumber numberWithFloat:angle] forName:@"angle"];
        [nodeStretch setAttr:@[[NSNumber numberWithFloat:ratioX], [NSNumber numberWithFloat:ratioY]] forName:@"ratio"];
        
        [scriptExtra compile];
        NSMutableArray* nodesNew = [NSMutableArray arrayWithArray:scriptExtra.nodes];
        [nodesNew addObjectsFromArray:nodes];
        nodes = nodesNew;
    }
    
    if (nodes.count == 0) {
        NSLog(@"OVC _initShader: ### special case, empty pipeline");
        NSDictionary* extra = @{
            @"pipeline":@[
                @{ @"filter":@"simple" }
            ]
        };
        OVLScript* scriptExtra = [[OVLScript alloc] initWithDictionary:extra];
        [scriptExtra compile];
        nodes = scriptExtra.nodes;
    }
    
    _shader = [[OVLPlaneShaders alloc] initWithSize:size withNodeList:nodes viewSize:_glkView.bounds.size landscape:self.configuration.landscape];
    
    // Set the initial projection to all the shaders
    GLKMatrix4 matrix = GLKMatrix4MakeOrtho(0.0, 1.0, 1.0, 0.0, 1.0, 100.0);
    [_shader setProjection:&matrix];
    
    if (_renderPixelBuffer) {
        NSLog(@"OVLVC _initShader calling setRenderTexture");
        [_shader setRenderTexture:_renderTexture];
    }
}

-(BOOL) _readAssetBuffer {
    BOOL fSkipShader = YES;
    /*if (_fFirstBufferIsAlreadyCaptured) {
     _fFirstBufferIsAlreadyCaptured = NO;
     fSkipShader = NO;
     } else */
    if (_fUpdated && self.fRecording) {
        NSLog(@"OVL _readAssetBuffer, pending writing");
        [self _writeToBuffer];
    } else if (_assetReader.status == AVAssetReaderStatusReading) {
        BOOL fProcessing = NO;
        CMSampleBufferRef buffer = [_assetReaderOutput copyNextSampleBuffer];
        if (buffer) {
            CMTime t = CMSampleBufferGetPresentationTimeStamp(buffer);
            NSLog(@"OVLVC video t=%.2f", (double)t.value / (double)t.timescale);
            [self captureOutput:nil didOutputSampleBuffer:buffer fromConnection:nil];
            CFRelease(buffer);
            fSkipShader = NO;
            fProcessing = YES;
        } else {
            NSLog(@"OVLVC -- video done");
        }
        
        if (_audioMixOutput) {
            // We can't process audio until we call _writeToBuffer at least once
            if (!_fFirstFrame && _audioInput.readyForMoreMediaData) {
                CMSampleBufferRef buffer = [_audioMixOutput copyNextSampleBuffer];
                if (buffer) {
                    CMTime t = CMSampleBufferGetPresentationTimeStamp(buffer);
                    NSLog(@"OVLVC audio t=%.2f", (double)t.value / (double)t.timescale);
                    [_audioInput appendSampleBuffer:buffer];
                    CFRelease(buffer);
                    fProcessing = YES;
                } else {
                    NSLog(@"OVLVC -- audio done");
                    _audioMixOutput = nil;
                }
            } else {
                fProcessing = YES;
            }
        }
        if (!fProcessing) {
            NSLog(@"OVLVC -- all done");
            _assetReaderOutput = nil;
            _assetReader = nil;
            [self resetShader];
            if (self.fRecording) {
                [self _stopRecording];
            }
        }
    } else {
        NSLog(@"OVLVC -- stop");
    }
    return fSkipShader;
}


// <GLKViewDelegate> method
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    if (!_shader) {
        // We don't want to do anything if the shader is not initialized yet.
        return;
    }
    if (_assetReader && self.fRecording) {
        BOOL fSkipShader = [self _readAssetBuffer];
        if (fSkipShader) {
            return;
        }
    }
    
    //    NSLog(@"OVLVL drawInRect shading");
    [_shader process];
    
    [view bindDrawable];
    glClearColor(0.333, 0.333, 0.333, 1.0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    [_shader render];
    
    if (self.fRecording) {
        [self _writeToBuffer];
    }
    
    if (_renderPixelBuffer == NULL) {
        [self _renderPixelBufferCreate];
    }
    [self _upDataPixelBuffer];
    
    if (self.renderbufferEx) {
        if (!_frameBufferEx) {
            glGenFramebuffers(1, &_frameBufferEx);
            /*
             _programHandleEx = [OVLBaseShader compileAndLinkShader:@"simple.vsh" fragment:@"simple.fsh"];
             GLuint uProjection = glGetUniformLocation(_programHandleEx, "uProjection");
             GLuint uModelView = glGetUniformLocation(_programHandleEx, "uModelView");
             //GLuint uRatio = glGetUniformLocation(_programHandleEx, "ratio");
             _uTextureEx = glGetUniformLocation(_programHandleEx, "uTexture");
             //_uRatio = glGetUniformLocation(_programHandle, "ratio");
             //_aPosition = glGetAttribLocation(_programHandle, "aPosition");
             //_aTextCoord = glGetAttribLocation(_programHandle, "aTextCoord");
             GLKMatrix4 modelView = GLKMatrix4Identity;
             GLKMatrix4 projection = GLKMatrix4MakeOrtho(0.0, 1.0, 1.0, 0.0, 1.0, 100.0);
             glUseProgram(_programHandleEx);
             glUniformMatrix4fv(uProjection, 1, 0, projection.m);
             glUniformMatrix4fv(uModelView, 1, 0, modelView.m);
             //glUniform2f(uRatio, 1.0, 1.0);
             */
        }
        glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferEx);
        glClearColor(0.333, 0.333, 0.333, 1.0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glBindRenderbuffer(GL_RENDERBUFFER, self.renderbufferEx);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                  GL_RENDERBUFFER, self.renderbufferEx);
        //[_shader renderWithProgram:_programHandleEx texture:_uTextureEx];
        [_shader render];
        [_glkView.context presentRenderbuffer:GL_RENDERBUFFER];
        [view bindDrawable];
    }
}

-(void) _setInitialSize:(CGSize)size {
    ///8
    _size = size;
    if (!self.fHD) {
        // NOTE: Using floor add a green line at the bottom
        _size.width = ceil(480.0 * _size.width / _size.height);
        _size.height = 480.0;
    }
    _clipRatio = 1.0;
    if (self.fPhotoRatio) {
        CGFloat width = _size.height / 3.0 * 4.0;
        if (_size.width > width + 1.0) {
            _clipRatio = _size.width / width;
            _size.width = width;
            NSLog(@"OVL capture size adjusted to %f,%f", _size.width, _size.height);
        }
    }
    
    if (_assetReader) {
        _fInitializingShader = NO;
        [self _initShader:_size];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            _fInitializingShader = NO;
            [self _initShader:_size];
        });
    }
}
#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    NSLog(@"丢失了");
}

/**
 摄像头采集的数据回调
 
 @param captureOutput 输出设备
 @param sampleBuffer 帧缓存数据，描述当前帧信息
 @param connection 连接
 */
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (capturePaused) {//退后台停止输出
        return;
    }
    if (captureOutput == _captureVideoDataOutput || _assetReader) {
        CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        _timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        size_t width = CVPixelBufferGetWidth(pixelBuffer);
        size_t height = CVPixelBufferGetHeight(pixelBuffer);
        if (!_shader && _script && !_fInitializingShader) {
            _fInitializingShader = YES;
            // NOTE: We assumes that the camera is always in the landscape mode.
            [self _setInitialSize:CGSizeMake(width, height)];
        }
        
        [self _cleanUpTextures];
        
        // Create a live binding between the captured pixelBuffer and an openGL texture
        CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage(
                                                                    kCFAllocatorDefault,    // allocator
                                                                    _textureCache,     // texture cache
                                                                    pixelBuffer,            // source Image
                                                                    NULL,                   // texture attributes
                                                                    GL_TEXTURE_2D,          // target
                                                                    GL_RGBA,                // internal format
                                                                    (int)width,             // width
                                                                    (int)height,            // height
                                                                    GL_BGRA,                // format
                                                                    GL_UNSIGNED_BYTE,       // type
                                                                    0,                      // planeIndex
                                                                    &_videoTexture);        // texture out
        if (err) {
            NSLog(@"OVLVC Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        [_shader setSourceTexture:CVOpenGLESTextureGetName(_videoTexture)];
        _fUpdated = YES;
        [_glkView display];
    }
    else if (captureOutput == _captureAudioDataOutput) {
        if (_shader.fProcessAudio) {
            // http://stackoverflow.com/questions/14088290/passing-avcaptureaudiodataoutput-data-into-vdsp-accelerate-framework/14101541#14101541
            // Pitch detection
            // http://stackoverflow.com/questions/7181630/fft-on-iphone-to-ignore-background-noise-and-find-lower-pitches?lq=1
            // https://github.com/irtemed88/PitchDetector/blob/master/RIOInterface.mm
            // get a pointer to the audio bytes
            CMItemCount numSamples = CMSampleBufferGetNumSamples(sampleBuffer);
            CMBlockBufferRef audioBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
            size_t lengthAtOffset;
            size_t totalLength;
            char *samples;
            CMBlockBufferGetDataPointer(audioBuffer, 0, &lengthAtOffset, &totalLength, &samples);
            
            CMAudioFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
            const AudioStreamBasicDescription *desc = CMAudioFormatDescriptionGetStreamBasicDescription(format);
            if (desc->mFormatID == kAudioFormatLinearPCM) {
                if (desc->mChannelsPerFrame == 1 && desc->mBitsPerChannel == 16) {
                    /*
                     NSInteger total = 0;
                     short* values = (short*)samples;
                     for (int i=0; i<numSamples; i++) {
                     total += abs(values[i]);
                     }
                     _shader.audioVolume = (float)total/(float)numSamples/(float)0x4000;
                     */
                    // Convert it to float vector
                    if (_fftSize ==0) {
                        _fftA.realp = malloc(numSamples * sizeof(float));
                        _fftA.imagp = malloc(numSamples * sizeof(float));
                        _fftSize = numSamples;
                    } else if (_fftSize < numSamples) {
                        _fftA.realp = realloc(_fftA.realp, numSamples * sizeof(float));
                        _fftA.imagp = realloc(_fftA.imagp, numSamples * sizeof(float));
                        _fftSize = numSamples;
                    }
                    vDSP_vflt16((short *)samples, 1, _fftA.realp, 1, numSamples);
                    
                    float scale = 1.0 / 0x7fff;
                    vDSP_vsmul(_fftA.realp, 1, &scale, _fftA.realp, 1, numSamples);
                    float maxValue;
                    vDSP_maxv(_fftA.realp, 1, &maxValue, numSamples);
                    _shader.audioVolume = maxValue;
                    
                    NSLog(@"OVLVC s1=%.2f, %.2f, %.2f, %.2f, %.2f, %.2f", _fftA.realp[0], _fftA.realp[1], _fftA.realp[2], _fftA.realp[3], _fftA.realp[4], _fftA.realp[5]);
                    float a = 0.0;
                    vDSP_vfill(&a, _fftA.imagp, 1, numSamples);
                    NSLog(@"OVLVC s2=%.2f, %.2f, %.2f, %.2f, %.2f, %.2f", _fftA.imagp[0], _fftA.imagp[1], _fftA.imagp[2], _fftA.imagp[3], _fftA.imagp[4], _fftA.imagp[5]);
                    vDSP_Length log2n = log2(numSamples);
                    vDSP_fft_zrip(_fftSetup, &_fftA, 1, log2n, FFT_FORWARD);
                    
                    /*
                     scale = 1.0 / (2 * numSamples);
                     vDSP_vsmul(_fftA.realp, 1, &scale, _fftA.realp, 1, numSamples/2);
                     vDSP_vsmul(_fftA.imagp, 1, &scale, _fftA.imagp, 1, numSamples/2);
                     */
                    
                    NSLog(@"OVLVC s3=%.2f, %.2f, %.2f, %.2f, %.2f, %.2f", _fftA.realp[0], _fftA.realp[1], _fftA.realp[2], _fftA.realp[3], _fftA.realp[4], _fftA.realp[5]);
                    maxValue = 0.0;
                    int maxIndex = -1;
                    for (int i=0; i < numSamples/2; i++) {
                        float value = _fftA.realp[i] * _fftA.realp[i] + _fftA.imagp[i] * _fftA.imagp[i];
                        if (value > maxValue) {
                            maxValue = value;
                            maxIndex = i;
                        }
                    }
                    NSLog(@"OVLVC maxIndex=%d", maxIndex);
                } else {
                    // handle other cases as required
                }
            }
        }
        
        if (self.fRecording && _audioInput && !_fFirstFrame) {
            NSLog(@"OGL _captureAudioDataOutput");
            [_audioInput appendSampleBuffer:sampleBuffer];
        }
    }
}

- (void)_cleanUpTextures
{
    ///9
    if (_videoTexture) {
        //glActiveTexture(GL_TEXTURE7);
        //glBindTexture(CVOpenGLESTextureGetTarget(_videoTexture), 0);
        CFRelease(_videoTexture);
        _videoTexture = NULL;
    }
    
    // Periodic texture cache flush every frame
    CVOpenGLESTextureCacheFlush(_textureCache, 0);
}

-(void) _tearDownRenderTarget {
    if (_renderPixelBuffer) {
        CVPixelBufferRelease(_renderPixelBuffer);
        _renderPixelBuffer = NULL;
        if (_renderTexture) {
            CFRelease(_renderTexture);
            _renderTexture = NULL;
        }
    }
}

- (void) _tearDownAVCapture {
    [self _cleanUpTextures];
    if (_textureCache) {
        CFRelease(_textureCache);
        _textureCache = nil;
    }
}

// NOTE: It calls back synchronously if there is no need for a sound.
-(void) snapshot:(BOOL)sound callback:(void (^)(UIImage* image))callback {
    if (sound) {
        [_stillImageOutput captureStillImageAsynchronouslyFromConnection:_stillImageOutput.connections.lastObject completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
            NSLog(@"OVLVC still image captured (not used at this moment, just using the sound)");
            UIImage* image = [self->_shader snapshot:YES];
            callback(image);
        }];
    } else {
        UIImage* image = [_shader snapshot:YES];
        callback(image);
    }
}

- (CGFloat)_angleOffsetFromPortraitOrientationToOrientation:(AVCaptureVideoOrientation)orientation
{
    CGFloat angle = 0.0;
    
    switch (orientation) {
        case AVCaptureVideoOrientationPortrait:
            angle = 0.0;
            break;
        case AVCaptureVideoOrientationPortraitUpsideDown:
            angle = M_PI;
            break;
        case AVCaptureVideoOrientationLandscapeRight:
            angle = -M_PI_2;
            break;
        case AVCaptureVideoOrientationLandscapeLeft:
            angle = M_PI_2;
            break;
        default:
            break;
    }
    
    return angle;
}

- (CGAffineTransform)_transformFromCurrentVideoOrientation:(AVCaptureVideoOrientation)videoOrientation toOrientation:(AVCaptureVideoOrientation)orientation
{
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    // Calculate offsets from an arbitrary reference orientation (portrait)
    if (_camera.position==AVCaptureDevicePositionFront) {
        if (orientation == AVCaptureVideoOrientationLandscapeLeft) {
            orientation = AVCaptureVideoOrientationLandscapeRight;
        } else if (orientation == AVCaptureVideoOrientationLandscapeRight) {
            orientation = AVCaptureVideoOrientationLandscapeLeft;
        }
    }
    CGFloat orientationAngleOffset = [self _angleOffsetFromPortraitOrientationToOrientation:orientation];
    CGFloat videoOrientationAngleOffset = [self _angleOffsetFromPortraitOrientationToOrientation:videoOrientation];
    
    // Find the difference in angle between the passed in orientation and the current video orientation
    CGFloat angleOffset = orientationAngleOffset - videoOrientationAngleOffset;
    transform = CGAffineTransformMakeRotation(angleOffset);
    
    return transform;
}

-(BOOL) isReadyToRecord {
    return (_size.width > 0);
}


/**
 * 录制
 * 开始录制：
 * @param localFileURL 录制路径
 */
- (void)startRecordingToLocalFileURL:(NSURL *_Nullable)localFileURL{
    if (!self.fRecording) {
        [self _startRecording];
    }
}

/**
 * 停止录制
 */
- (void)stopRecording{
    if (self.fRecording) {
        [self _stopRecording];
    }
}

-(void) _startRecording {
    if (![self isReadyToRecord]) {
        NSLog(@"OVLVC _size is not yet initialized.");
        return;
    }
    self.fRecording = YES;
    [_shader startRecording];
    self.saveLocalVideoPath = [NSURL fileURLWithPath:[GLKViewManager tempFilePath:@"mov"]];
    [GLKViewManager deleteLiveRecording:@"mov"];
    NSError* error = nil;
    _videoWriter = [[AVAssetWriter alloc] initWithURL:self.saveLocalVideoPath fileType:AVFileTypeQuickTimeMovie
                                                error:&error];
    _videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                     outputSettings:@{
        AVVideoCodecKey:AVVideoCodecTypeH264,
        //AVVideoCompressionPropertiesKey:compression,
        AVVideoWidthKey:[NSNumber numberWithInt:_size.width],
        AVVideoHeightKey:[NSNumber numberWithInt:_size.height]
    }];
    
    if (_assetReader) {
        _videoInput.transform = _assetTransform;
        _videoInput.expectsMediaDataInRealTime = YES;
    } else {
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
        _videoInput.transform = [self _transformFromCurrentVideoOrientation:AVCaptureVideoOrientationLandscapeRight
                                                              toOrientation:orientation];
        _videoInput.expectsMediaDataInRealTime = YES;
    }
    [_videoWriter addInput:_videoInput];
    
    NSDictionary* attr = @{
        (id)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithInt:kCVPixelFormatType_32BGRA],
        (id)kCVPixelBufferWidthKey: [NSNumber numberWithInteger:_size.width],
        (id)kCVPixelBufferHeightKey: [NSNumber numberWithInteger:_size.height]
    };
    _adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoInput sourcePixelBufferAttributes:attr];
    
    if (!self.fNoAudio) {
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
    _fFirstFrame = YES;
    _duration = 0;
}

-(void) _upDataPixelBuffer{
    glFlush(); // Making it sure that GPU won't update the texture particially
    NSTimeInterval  cameraTime = ((NSTimeInterval)CMTimeGetSeconds(_timeStamp))*1000;
    if (self.delegate && [self.delegate respondsToSelector:@selector(captureSYSOutput:pixelBuffer:timeStamp:)]) {
        [self.delegate captureSYSOutput:self pixelBuffer:_renderPixelBuffer timeStamp:cameraTime];
    }
}
-(void) _renderPixelBufferCreate{
    NSLog(@"OGLVC creating a new _renderTexture");
    CVReturn status;
    if (_isRecord) {
        status = CVPixelBufferPoolCreatePixelBuffer(NULL, [_adaptor pixelBufferPool], &_renderPixelBuffer);
    }else {
        CFDictionaryRef empty; // empty value for attr value.
        CFMutableDictionaryRef attrs;
        empty = CFDictionaryCreate(kCFAllocatorDefault, // our empty IOSurface properties dictionary
                                   NULL,
                                   NULL,
                                   0,
                                   &kCFTypeDictionaryKeyCallBacks,
                                   &kCFTypeDictionaryValueCallBacks);
        attrs = CFDictionaryCreateMutable(kCFAllocatorDefault, 1,
                                          &kCFTypeDictionaryKeyCallBacks,
                                          &kCFTypeDictionaryValueCallBacks);
        
        CFDictionarySetValue(attrs, kCVPixelBufferIOSurfacePropertiesKey, empty);
        status = CVPixelBufferCreate(kCFAllocatorDefault, _size.width, _size.height,
                                     kCVPixelFormatType_32BGRA, attrs, &(_renderPixelBuffer));
    }
    if ((_renderPixelBuffer == NULL) || (status != kCVReturnSuccess)) {
        NSLog(@"OVLVC can't create pixel buffer %d", status);
        return;
    }
    // Create a live binding between _renderPixelBuffer and an openGL texture
    CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                 _textureCache,
                                                 _renderPixelBuffer,
                                                 NULL, // texture attributes
                                                 GL_TEXTURE_2D,
                                                 GL_RGBA, // opengl format
                                                 (int)_size.width,
                                                 (int)_size.height,
                                                 GL_BGRA, // native iOS format
                                                 GL_UNSIGNED_BYTE,
                                                 0,
                                                 &_renderTexture);
    [_shader setRenderTexture:_renderTexture];
}

-(void) _stopRecording {
    self.fRecording = NO;
    [_videoInput markAsFinished];
    NSLog(@"finishig %ld", (long)_videoWriter.status);
    [_videoWriter finishWritingWithCompletionHandler:^{
        NSLog(@"done");
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_videoWriter = nil;
            self->_videoInput = nil;
            self->_audioInput = nil;
            self->_adaptor = nil;
        });
    }];
    if (_videoWriter.status == AVAssetWriterStatusFailed) {
        NSLog(@"finish failed %@", _videoWriter.error);
    }
}


-(void) _writeToBuffer {
    if (_fUpdated && _videoInput.readyForMoreMediaData) {
        glFlush(); // Making it sure that GPU won't update the texture particially
        _fUpdated = NO;
        CMTime timeStamp = _timeStamp;
        if (_fFirstFrame) {
            _fFirstFrame = NO;
            [_videoWriter startSessionAtSourceTime:_timeStamp];
            _startTime = _timeStamp;
            _duration = -1; // to force the notification
        } else if (self.speed > 0) {
            CMTime delta = CMTimeSubtract(_timeStamp, _startTime);
            delta.value /= self.speed;
            timeStamp = CMTimeAdd(_startTime, delta);
        }
        NSLog(@"OVLVC _write t=%.2f", (double)timeStamp.value / (double)timeStamp.timescale);
        [_adaptor appendPixelBuffer:_renderPixelBuffer withPresentationTime:timeStamp];
        
        
        self.timeRecorded = CMTimeSubtract(_timeStamp, _startTime);
        NSInteger d = (NSInteger)(self.timeRecorded.value / self.timeRecorded.timescale); // interested in only sec.
        if (d > _duration) {
            _duration = d;
            NSLog(@"_writeToBuffer writing %d, %lu", _fUpdated, (unsigned long)_duration);
        }
        if (CMTimeCompare(self.timeRecorded, _maxDuration) != -1) {
            NSLog(@"OVL stopping at %lld, %d", self.timeRecorded.value, self.timeRecorded.timescale);
            [self _stopRecording];
        }
    } else {
        NSLog(@"_writeToBuffer skipping %d", _fUpdated);
    }
}

-(void) dealloc {
    [self _tearDownAVCapture];
    [self _tearDownRenderTarget];
    if (_frameBufferEx) {
        glDeleteFramebuffers(1, &_frameBufferEx);
    }
    vDSP_destroy_fftsetup(_fftSetup);
    if (_fftSize > 0) {
        free(_fftA.realp);
        free(_fftA.imagp);
    }
}

@end

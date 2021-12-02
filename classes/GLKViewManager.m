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
#import "CameraManager.h"
#import "PhotoManager.h"

@interface GLKViewManager ()

<
GLKViewDelegate
>

@property (nonatomic, strong) OVLPlaneShaders* shader;
@property (nonatomic, strong) OVLScript* script;
@property (nonatomic, assign) CGSize size;
@property (nonatomic, assign) BOOL fInitializingShader;
@property (nonatomic, assign) CGFloat clipRatio;
@property (nonatomic, assign) BOOL capturePaused; //采集状态--用于设备进入后台 阻断相机数据采集
@property (nonatomic, assign) OSType videoFormat;



@property (nonatomic, assign) CVOpenGLESTextureRef videoTexture;
@property (nonatomic, assign) CVOpenGLESTextureCacheRef textureCache;
@property (nonatomic, strong) NSMutableArray  *filters;

@property (nonatomic, assign)   BOOL fFirstFrame;
@property (nonatomic, assign)  CMTime timeStamp;
@property (nonatomic, assign)  CMTime startTime;

@property (nonatomic, assign) BOOL fUpdated;
@property (nonatomic, assign)  NSInteger duration;
// Fast buffer
@property (nonatomic, assign)  CVPixelBufferRef renderPixelBuffer;
@property (nonatomic, assign)  CVOpenGLESTextureRef renderTexture;


// FFT
@property (nonatomic, assign)  FFTSetup fftSetup;
@property (nonatomic, assign) DSPSplitComplex fftA;
@property (nonatomic, assign)  CMItemCount fftSize;


/** 是否已经在采集 */
@property (nonatomic, assign) BOOL isCapturing;


@property (nonatomic, strong) ADYLiveVideoConfiguration *configuration;
@property (nonatomic, assign)NSInteger  frameRate;
@property (nonatomic, strong) NSURL *saveLocalVideoPath;

@property (nonatomic, strong) CameraManager *cameraManger;
//@property (nonatomic, strong) ADYAdjustFocusView *focusView;
@end

@implementation GLKViewManager
@synthesize duration = _duration;
@synthesize filterIndex = _filterIndex;
@synthesize torch = _torch;
@synthesize beautyLevel = _beautyLevel;
@synthesize brightLevel = _brightLevel;
@synthesize toneLevel = _toneLevel;
@synthesize filterLookupName = _filterLookupName;

-(NSInteger) duration {
    return _duration;
}

-(CameraManager *)cameraManger{
    if (!_cameraManger) {
        _cameraManger = [CameraManager sharedSingletonWithConfiguration:self.configuration];
        [_cameraManger setAudioDelegate:self];
        [_cameraManger setVideoDelegate:self];
    }
    return  _cameraManger;
}

#pragma mark  instancetype---initWithFrame
- (instancetype)initWithFrame:(CGRect)frame context:(EAGLContext *)context configuration:(ADYLiveVideoConfiguration *)configuration {
    if (self = [super initWithFrame:frame context:context]) {
        _configuration = configuration;
        [OVLFilter setFrontCameraMode:NO];
        self.fHD = YES;
        /// 初始化滤镜
        [self initFilter];
        /// 初始化相机
        [self cameraManger];
        /// 添加操作手势
        [self.cameraManger initTapGesture:self];
    }
    return self;
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
                    @"type":@"filter",
                    @"filter":@"lookup",
                    @"lookup":@true,
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
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterBackground:) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForeground:) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    self.beautyLevel = 0;
    self.toneLevel = 5;
    self.brightLevel = 5;
    
    self.mirror = YES;
    
    // Initialize FFT
    _fftSetup = vDSP_create_fftsetup(11, kFFTRadix2);
    // Initialize the view's layer
    self.contentScaleFactor = [UIScreen mainScreen].scale;
    CAEAGLLayer* eaglLayer = (CAEAGLLayer*)self.layer;
    eaglLayer.opaque = YES;
    eaglLayer.contentsScale = self.contentScaleFactor;
    self.delegate = self;
    self.maxDuration = kCMTimeIndefinite;
}

/**
 切换摄像头
 */
- (void)setCaptureDevicePosition:(AVCaptureDevicePosition)captureDevicePosition
{
    [self.cameraManger setCaptureDevicePosition:captureDevicePosition];
    [self resetShader];
}
- (AVCaptureDevicePosition)captureDevicePosition {
    return [self.cameraManger.videoCaptureDeviceInput.device position];
}
-(void) resetShader {
    [_shader cleanupNodelist];
    _shader = nil;
    [self _tearDownRenderTarget];
}



- (NSInteger)videoFrameRate {
    return _frameRate;
}
- (void)setTorch:(BOOL)torch {
    [self.cameraManger setTorch:torch];
}

/**
 镜像
 */
- (void)setMirror:(BOOL)mirror {
    _mirror = mirror;
    [self.cameraManger reloadMirror:mirror];
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
    CGFloat number = beautyLevel/10*2.0;
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
    CGFloat number = brightLevel/10 * 0.5;
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
    CGFloat number = toneLevel/10*5;
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
                @"type":@"filter",
                @"filter":@"lookup",
                @"lookup":@true,
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

//-(ADYAdjustFocusView *)focusView{
//    if (!_focusView) {
//        _focusView = [[ADYAdjustFocusView alloc]initWithFrame:CGRectMake(0, 0, 80, 80)];
//        _focusView.hidden = YES;
//        [self addSubview:self.focusView];
//    }
//    return _focusView;
//}

#pragma mark Notification

- (void)willEnterBackground:(NSNotification *)notification {
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    self.capturePaused = YES;
    [self resetShader];
}

- (void)willEnterForeground:(NSNotification *)notification {
    self.capturePaused = NO;
    [UIApplication sharedApplication].idleTimerDisabled = YES;
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
        [self.cameraManger sessionLayerStop];
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
        [self.cameraManger sessionLayerRunning];
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
    self.drawableDepthFormat = GLKViewDrawableDepthFormatNone;
    self.drawableColorFormat = GLKViewDrawableColorFormatRGB565;
    CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, self.context, NULL, &_textureCache);
    /// 启动相机
    [self.cameraManger initAVCaptureSession];
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
        float tone = 0.1 * _toneLevel;
        float beauty1 = (1.0 - 0.6 * _beautyLevel);
        float beauty2 = (1.0 - 0.3 * _beautyLevel);
        float bright = 0.6 * _brightLevel;
        NSArray *params = @[
            [NSNumber numberWithFloat:beauty1],
            [NSNumber numberWithFloat:beauty2],
            [NSNumber numberWithFloat:tone],
            [NSNumber numberWithFloat:tone],
        ];
        CGPoint offset = CGPointMake(2.0f / _size.width, 2.0f / _size.height);
        NSDictionary* extra = @{
            @"pipeline":@[
                @{
                    @"type":@"filter",
                    @"filter":@"beauty",
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
    
    if (self.warterMark) {
        NSDictionary* extra = @{
            @"pipeline":@[
                @{
                    @"type":@"filter",
                    @"filter":@"watermark",
                    @"texture":@true,
                    @"hidden":@true,
                    @"orientation":@true,
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
    
    if (nodes.count == 0) {
        NSLog(@"OVC _initShader: ### special case, empty pipeline");
        NSDictionary* extra = @{
            @"pipeline":@[
                @{
                    @"filter":@"simple",
                    @"type":@"filter",
                    @"hidden":@true,
                }
            ]
        };
        OVLScript* scriptExtra = [[OVLScript alloc] initWithDictionary:extra];
        [scriptExtra compile];
        nodes = scriptExtra.nodes;
    }
    _shader = [[OVLPlaneShaders alloc] initWithSize:size withNodeList:nodes viewSize:self.bounds.size landscape:self.configuration.landscape];
    // Set the initial projection to all the shaders
    GLKMatrix4 matrix = GLKMatrix4MakeOrtho(0.0, 1.0, 1.0, 0.0, 1.0, 100.0);
    [_shader setProjection:&matrix];
    
    if (_renderPixelBuffer) {
        NSLog(@"OVLVC _initShader calling setRenderTexture");
        [_shader setRenderTexture:_renderTexture];
    }
}

// <GLKViewDelegate> method
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    if (!_shader) {
        // We don't want to do anything if the shader is not initialized yet.
        return;
    }
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
}

-(void) _setInitialSize:(CGSize)size {
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
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_fInitializingShader = NO;
        [self _initShader:self->_size];
    });
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
    if (self.capturePaused) {//退后台停止输出
        return;
    }
    if (captureOutput == self.cameraManger.captureVideoDataOutput) {
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
        [self display];
    }
    else if (captureOutput == self.cameraManger.captureAudioDataOutput) {
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
        
        if (self.fRecording && self.cameraManger.audioInput && !_fFirstFrame) {
            NSLog(@"OGL _captureAudioDataOutput");
            [self.cameraManger.audioInput appendSampleBuffer:sampleBuffer];
        }
    }
}

- (void)_cleanUpTextures
{
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

-(BOOL) isReadyToRecord {
    return (_size.width > 0);
}


/**
 * 录制
 * 开始录制：
 * @param localFileURL 录制路径
 */
- (void)startRecordingToLocalFileURL:(NSURL *_Nullable)localFileURL{
    _saveLocalVideoPath = localFileURL;
    if (!self.fRecording) {
        
        if (![self isReadyToRecord]) {
            NSLog(@"OVLVC _size is not yet initialized.");
            return;
        }
        self.fRecording = YES;
        [_shader startRecording];
        if (!_saveLocalVideoPath) {
            _saveLocalVideoPath = [NSURL fileURLWithPath:[PhotoManager tempFilePath:@"live_recording.mov"]];
            [PhotoManager deleteLiveRecording:@"live_recording.mov"];
        }
        [self.cameraManger startRecording:_saveLocalVideoPath];
        _fFirstFrame = YES;
        _duration = 0;
        
    }
}

/**
 * 停止录制
 */
- (void)stopRecording
{
    if (self.fRecording) {
        [self _stopRecording];
    }
}

-(void) _upDataPixelBuffer{
    glFlush(); // Making it sure that GPU won't update the texture particially
    NSTimeInterval  cameraTime = ((NSTimeInterval)CMTimeGetSeconds(_timeStamp))*1000;
    if (self.myDelegate && [self.myDelegate respondsToSelector:@selector(captureSYSOutput:pixelBuffer:timeStamp:)]) {
        [self.myDelegate captureSYSOutput:self pixelBuffer:_renderPixelBuffer timeStamp:cameraTime];
    }
}

-(void) _renderPixelBufferCreate{
    NSLog(@"OGLVC creating a new _renderTexture");
    CVReturn status;
    if (_fRecording) {
        status = CVPixelBufferPoolCreatePixelBuffer(NULL, [self.cameraManger.adaptor pixelBufferPool], &_renderPixelBuffer);
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
    [self.cameraManger stopRecordingWithCompletionHandler:^(BOOL resuccess) {
        if (resuccess) {
            [PhotoManager saveVideoToAlbum:self->_saveLocalVideoPath.relativeString videoToAlbum:createVideoToAlbum callBack:^(BOOL phsuccess) {
                [[NSNotificationCenter defaultCenter] postNotificationName:SaveVideoToAlbumNotification object: phsuccess ? @NO : @YES];
            }];
        }else{
            NSLog(@"录制失败！");
            [[NSNotificationCenter defaultCenter] postNotificationName:SaveVideoToAlbumNotification object:@NO];
        }
    }];
}


-(void) _writeToBuffer {
    if (_fUpdated && self.cameraManger.videoInput.readyForMoreMediaData) {
        glFlush(); // Making it sure that GPU won't update the texture particially
        _fUpdated = NO;
        CMTime timeStamp = _timeStamp;
        if (_fFirstFrame) {
            _fFirstFrame = NO;
            [self.cameraManger.videoWriter startSessionAtSourceTime:_timeStamp];
            _startTime = _timeStamp;
            _duration = -1; // to force the notification
        } else if (self.speed > 0) {
            CMTime delta = CMTimeSubtract(_timeStamp, _startTime);
            delta.value /= self.speed;
            timeStamp = CMTimeAdd(_startTime, delta);
        }
//        NSLog(@"OVLVC _write t=%.2f", (double)timeStamp.value / (double)timeStamp.timescale);
        [self.cameraManger.adaptor appendPixelBuffer:_renderPixelBuffer withPresentationTime:timeStamp];
        
        
        self.timeRecorded = CMTimeSubtract(_timeStamp, _startTime);
        NSInteger d = (NSInteger)(self.timeRecorded.value / self.timeRecorded.timescale); // interested in only sec.
        if (d > _duration) {
            _duration = d;
//            NSLog(@"_writeToBuffer writing %d, %lu", _fUpdated, (unsigned long)_duration);
        }
        if (CMTimeCompare(self.timeRecorded, _maxDuration) != -1) {
            NSLog(@"OVL stopping at %lld, %d", self.timeRecorded.value, self.timeRecorded.timescale);
            [self _stopRecording];
        }
    } else {
//        NSLog(@"_writeToBuffer skipping %d", _fUpdated);
    }
}

-(void) dealloc {
    [self _tearDownAVCapture];
    [self _tearDownRenderTarget];
    vDSP_destroy_fftsetup(_fftSetup);
    if (_fftSize > 0) {
        free(_fftA.realp);
        free(_fftA.imagp);
    }
}

@end

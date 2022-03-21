//
//  CVTCameraCapture.m
//  Metal_Learn
//
//  Created by hejiangshan on 2022/3/14.
//

#import "CVTCameraCapture.h"
#import <AVFoundation/AVFoundation.h>

@interface CVTCameraCapture ()<AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong) dispatch_queue_t captureQueue;

@end

@implementation CVTCameraCapture
{
    AVCaptureVideoDataOutput *_videoDataOutput;
    AVCaptureSession *_captureSession;
    AVCaptureDevice *_currentDevice;
    FourCharCode _preferredOutputPixelFormat;
    FourCharCode _outputPixelFormat;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _captureSession = [[AVCaptureSession alloc] init];
        [self setupVideoDataOutput];
        [_captureSession addOutput:_videoDataOutput];
    }
    return self;
}

- (void)startCapture {
    AVCaptureDevicePosition position = AVCaptureDevicePositionFront;
    AVCaptureDevice *device = [self findDeviceForPosition:position];
    _currentDevice = device;
    
    AVCaptureDeviceFormat *format = [self selectFormatForDevice:device];
    
    if (format == nil) {
        NSLog(@"No valid formats for device %@", device);
        NSAssert(NO, @"");
        
        return;
    }
    
    int32_t fps = [self selectFpsForFormat:format];
    
    [self startCaptureWithDevice:device format:format fps:fps completionHandler:^(NSError *error) {
        
    }];
}

- (void)stopCapture {
    [self stopCaptureWithCompletionHandler:NULL];
}

- (void)stopCaptureWithCompletionHandler:(nullable void (^)(void))completionHandler {
    _currentDevice = nil;
    for (AVCaptureDeviceInput *oldInput in [_captureSession.inputs copy]) {
        [_captureSession removeInput:oldInput];
    }
    [_captureSession stopRunning];
    
    if (completionHandler) {
        completionHandler();
    }
}


//MARK: Camera Capture
- (void)setupVideoDataOutput {
    NSAssert(_videoDataOutput == nil, @"Setup video data output called twice.");
    AVCaptureVideoDataOutput *videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    // `videoDataOutput.availableVideoCVPixelFormatTypes` returns the pixel formats supported by the
    // device with the most efficient output format first. Find the first format that we support.
    NSSet<NSNumber *> *supportedPixelFormats = [CVTCameraCapture supportedPixelFormats];
    NSMutableOrderedSet *availablePixelFormats =
    [NSMutableOrderedSet orderedSetWithArray:videoDataOutput.availableVideoCVPixelFormatTypes];
    [availablePixelFormats intersectSet:supportedPixelFormats];
    NSNumber *pixelFormat = availablePixelFormats.firstObject;
    NSAssert(pixelFormat, @"Output device has no supported formats.");
    
    _preferredOutputPixelFormat = [pixelFormat unsignedIntValue];
    _outputPixelFormat = _preferredOutputPixelFormat;
    videoDataOutput.videoSettings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey : pixelFormat};
    videoDataOutput.alwaysDiscardsLateVideoFrames = NO;
    [videoDataOutput setSampleBufferDelegate:self queue:self.captureQueue];
    _videoDataOutput = videoDataOutput;
}

+ (NSSet<NSNumber*>*)supportedPixelFormats {
    return [NSSet setWithObjects:
            @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            @(kCVPixelFormatType_32BGRA),
            @(kCVPixelFormatType_32ARGB),
            nil];
}

- (AVCaptureDeviceFormat *)selectFormatForDevice:(AVCaptureDevice *)device {
    NSArray<AVCaptureDeviceFormat *> *formats = _currentDevice.formats;
    int targetWidth = 1920;//[_settings currentVideoResolutionWidthFromStore];
    int targetHeight = 1080;//[_settings currentVideoResolutionHeightFromStore];
    AVCaptureDeviceFormat *selectedFormat = nil;
    int currentDiff = INT_MAX;
    
    for (AVCaptureDeviceFormat *format in formats) {
        CMVideoDimensions dimension = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
        FourCharCode pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription);
        int diff = abs(targetWidth - dimension.width) + abs(targetHeight - dimension.height);
        if (diff < currentDiff) {
            selectedFormat = format;
            currentDiff = diff;
        } else if (diff == currentDiff && pixelFormat == _preferredOutputPixelFormat) {
            selectedFormat = format;
        }
    }
    
    return selectedFormat;
}


- (AVCaptureDevice *)findDeviceForPosition:(AVCaptureDevicePosition)position {
    NSArray<AVCaptureDevice *> *captureDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in captureDevices) {
        if (device.position == position) {
            return device;
        }
    }
    return captureDevices[0];
    //    AVCaptureDevice *capture = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    //    return capture;
}

- (int32_t)selectFpsForFormat:(AVCaptureDeviceFormat *)format {
    //    Float64 maxSupportedFramerate = 0;
    //    for (AVFrameRateRange *fpsRange in format.videoSupportedFrameRateRanges) {
    //        maxSupportedFramerate = fmax(maxSupportedFramerate, fpsRange.maxFrameRate);
    //    }
    //    return fmin(maxSupportedFramerate, kFramerateLimit);
    return 30.0;
}

- (void)startCaptureWithDevice:(AVCaptureDevice *)device
                        format:(AVCaptureDeviceFormat *)format
                           fps:(int32_t)fps
             completionHandler:(nullable void (^)(NSError *))completionHandler {
    [self reconfigureCaptureSessionInput];
    [self updateDeviceCaptureFormat:format fps:fps];
    [self updateVideoDataOutputPixelFormat:format];
    [_captureSession startRunning];
    [_currentDevice unlockForConfiguration];
    if (completionHandler) {
        completionHandler(nil);
    }
}

- (void)reconfigureCaptureSessionInput {
    //    NSAssert([RTCDispatcher isOnQueueForType:RTCDispatcherTypeCaptureSession],
    //             @"reconfigureCaptureSessionInput must be called on the capture queue.");
    NSError *error = nil;
    AVCaptureDeviceInput *input =
    [AVCaptureDeviceInput deviceInputWithDevice:_currentDevice error:&error];
    if (!input) {
        NSLog(@"Failed to create front camera input: %@", error.localizedDescription);
        return;
    }
    [_captureSession beginConfiguration];
    for (AVCaptureDeviceInput *oldInput in [_captureSession.inputs copy]) {
        [_captureSession removeInput:oldInput];
    }
    if ([_captureSession canAddInput:input]) {
        [_captureSession addInput:input];
    } else {
        NSLog(@"Cannot add camera as an input to the session.");
    }
    [_captureSession commitConfiguration];
}

- (void)updateDeviceCaptureFormat:(AVCaptureDeviceFormat *)format fps:(int32_t)fps {
    //    NSAssert([RTCDispatcher isOnQueueForType:RTCDispatcherTypeCaptureSession],
    //             @"updateDeviceCaptureFormat must be called on the capture queue.");
    @try {
        //    _currentDevice.activeFormat = format;
        //    _currentDevice.activeVideoMinFrameDuration = CMTimeMake(1, fps);
        
        AVCaptureDeviceFormat *bestFormat = nil;
        AVFrameRateRange *bestFrameRateRange = nil;
        for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
            if (range.maxFrameRate > bestFrameRateRange.maxFrameRate) {
                bestFormat = format;
                bestFrameRateRange = range;
            }
        }
        NSLog(@"minFrameDuration : %@", bestFrameRateRange);
        [_currentDevice lockForConfiguration:nil];
        _currentDevice.activeFormat = format;
//        _currentDevice.activeVideoMinFrameDuration = CMTimeMake(1, fps);//bestFrameRateRange.minFrameDuration;
//        _currentDevice.activeVideoMaxFrameDuration = CMTimeMake(1, fps);//bestFrameRateRange.maxFrameDuration;
        
        
        //      if ([_currentDevice lockForConfiguration:nil]) {
        //
        //          NSLog(@"selected format:%@", format);
        //          _currentDevice.activeFormat = format;
        //          _currentDevice.activeVideoMinFrameDuration = //CMTimeMake(1, fps);
        ////          _currentDevice.activeVideoMaxFrameDuration = CMTimeMake(1, fps);
        //
        //          [_currentDevice unlockForConfiguration];
        //      }
    } @catch (NSException *exception) {
        NSLog(@"Failed to set active format!\n User info:%@", exception.userInfo);
        return;
    }
}

- (void)updateVideoDataOutputPixelFormat:(AVCaptureDeviceFormat *)format {
    FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(format.formatDescription);
    if (![[CVTCameraCapture supportedPixelFormats] containsObject:@(mediaSubType)]) {
        mediaSubType = _preferredOutputPixelFormat;
    }
    
    if (mediaSubType != _outputPixelFormat) {
        _outputPixelFormat = mediaSubType;
        _videoDataOutput.videoSettings =
        @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(mediaSubType) };
    }
}

- (dispatch_queue_t)captureQueue {
    if (!_captureQueue) {
        _captureQueue =
        dispatch_queue_create("org.cvte.cameravideocapturer.video", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_captureQueue,
                                  dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
    }
    return _captureQueue;
}

#pragma mark AVCaptureVideoDataOutputSampleBuffer Delegate
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    NSParameterAssert(captureOutput == _videoDataOutput);
    
    if (CMSampleBufferGetNumSamples(sampleBuffer) != 1 || !CMSampleBufferIsValid(sampleBuffer) ||
        !CMSampleBufferDataIsReady(sampleBuffer)) {
        return;
    }
    
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferRetain(pixelBuffer);
    if (pixelBuffer == nil) {
        return;
    }
    if ([self.delegate respondsToSelector:@selector(didOutputPiexlBuffer:)]) {
        [self.delegate didOutputPiexlBuffer:pixelBuffer];
    }
    CVPixelBufferRelease(pixelBuffer);
}

@end

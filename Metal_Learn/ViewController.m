//
//  ViewController.m
//  Metal_Learn
//
//  Created by hejiangshan on 2021/3/4.
//

#import "ViewController.h"
#import "CVTMetalView.h"
#import <AVFoundation/AVFoundation.h>
#import "CVTCameraCapture.h"

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, CVTMetalViewDelegate, CVTCameraCaptureDelegate>

@property (nonatomic, strong) CVTMetalView *metalView;

@property (nonatomic, strong) dispatch_queue_t captureQueue;

@property (nonatomic, copy) NSString *videoFilePath;

@property (weak) IBOutlet NSTextField *timeLabel;

@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, strong) CVTCameraCapture *cameraCapture;

@end

@implementation ViewController
{
    CVTCameraCapture *_cameraCapture;
    BOOL _cameraRunning;
    CVTVideoRotation _rotation;
    
    NSInteger _time;
}

- (IBAction)startCapture:(id)sender {
    if (_cameraRunning) {
        return;
    }
    _time = 0;
    if (!self.timer) {
        __weak ViewController *weakSelf = self;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            __strong ViewController *strongSelf = weakSelf;
            strongSelf -> _time++;
            strongSelf.timeLabel.stringValue = [NSString stringWithFormat:@"%lds", strongSelf -> _time];
        }];
    }
    _cameraRunning = YES;
    [_cameraCapture startCapture];
}

- (IBAction)stopCapture:(id)sender {
    if (!_cameraRunning) {
        return;
    }
    _cameraRunning = NO;
    [_cameraCapture stopCapture];
    [self.timer invalidate];
    self.timer = nil;
    _time = 0;
    self.timeLabel.stringValue = @"0s";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.videoFilePath = [NSHomeDirectory() stringByAppendingFormat:@"/Documents/camera.h264"];
    NSLog(@"videoFilePath : %@", self.videoFilePath);
    _cameraCapture = [[CVTCameraCapture alloc] init];
    _cameraCapture.delegate = self;
    _cameraRunning = NO;
    
    [self createMetalView];
    
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

- (void)createMetalView {
    if ([CVTMetalView isMetalAvailable]) {
        CGFloat height = self.view.frame.size.width * 9 / 16.0;
        self.metalView = [[CVTMetalView alloc] initWithFrame:NSMakeRect(0, 0, self.view.frame.size.width, height)];
        self.metalView.delegate = self;
        self.metalView.wantsLayer = YES;
        self.metalView.layer.backgroundColor = [NSColor blackColor].CGColor;
        [self.view addSubview:self.metalView];
    }
}

#pragma mark CVTCameraCaptureDelegate delegate
- (void)didOutputPiexlBuffer:(CVPixelBufferRef)pixelBuffRef {
    _rotation = CVTVideoRotation_0;
    [self.metalView renderPixelBuffer:pixelBuffRef];
}

//MARK: CVTMetalView delegate
- (void)videoView:(CVTMetalView *)videoView didChangeVideoSize:(NSSize)size {
    
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    
    // Update the view, if already loaded.
}


@end

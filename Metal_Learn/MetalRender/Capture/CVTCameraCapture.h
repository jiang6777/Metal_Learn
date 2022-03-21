//
//  CVTCameraCapture.h
//  Metal_Learn
//
//  Created by hejiangshan on 2022/3/14.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

@protocol CVTCameraCaptureDelegate <NSObject>

- (void)didOutputPiexlBuffer:(CVPixelBufferRef)pixelBuffRef;

@end


@interface CVTCameraCapture : NSObject

@property (nonatomic, weak) id<CVTCameraCaptureDelegate> delegate;

- (void)startCapture;

- (void)stopCapture;

@end

NS_ASSUME_NONNULL_END

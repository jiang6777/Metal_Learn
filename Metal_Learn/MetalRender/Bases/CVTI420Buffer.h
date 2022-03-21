//
//  CVTI420Buffer.h
//  Metal_Learn
//
//  Created by hejiangshan on 2022/3/7.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CVTVideoRotation) {
  CVTVideoRotation_0 = 0,
  CVTVideoRotation_90 = 90,
  CVTVideoRotation_180 = 180,
  CVTVideoRotation_270 = 270,
};

@interface CVTI420Buffer : NSObject

@property CVPixelBufferRef pixelBufferRef;

/** Width without rotation applied. */
@property(nonatomic) int width;
/** Height without rotation applied. */
@property(nonatomic) int height;

@property(nonatomic, readonly) CVTVideoRotation rotation;
@property(nonatomic, assign, readonly) uint8_t *dataY;
@property(nonatomic, assign, readonly) uint8_t *dataU;
@property(nonatomic, assign, readonly) uint8_t *dataV;
@property(nonatomic, assign, readonly) int strideY;
@property(nonatomic, assign, readonly) int strideU;
@property(nonatomic, assign, readonly) int strideV;

- (instancetype)initWithPixelBuffer:(CVPixelBufferRef)pixelBuffer rotation:(CVTVideoRotation)rotation;

+ (instancetype)newI420Frame:(CVPixelBufferRef)pixelBuffer rotation:(CVTVideoRotation)rotation;

/// If the return result is 0, it means that the conversion to I420 is successful. If it is -1, it means that the conversion fails. If the conversion is successful, the values ​​of the three plane components of Y, U, and V will be filled into the attributes dataY, dataU, and dataV. The length will be filled into the attributes strideY, strideU, strideV
/// @param pixelBufferRef pixelBuffer
- (int)toI420:(CVPixelBufferRef)pixelBufferRef;

@end

NS_ASSUME_NONNULL_END

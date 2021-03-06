//
//  CVTI420Buffer.m
//  Metal_Learn
//
//  Created by cvte on 2022/3/7.
//

#import "CVTI420Buffer.h"
#include "libyuv/convert_argb.h"
#include "libyuv/convert_from.h"
#include "libyuv/planar_functions.h"
#include "libyuv/scale.h"

static int const align_pixel = 16;

@implementation CVTI420Buffer
{
    CVTVideoRotation _rotation;
}

- (instancetype)initWithPixelBuffer:(CVPixelBufferRef)pixelBuffer
                           rotation:(CVTVideoRotation)rotation {
    self = [super init];
    if (self) {
        _pixelBufferRef = pixelBuffer;
        CVPixelBufferRetain(pixelBuffer);
        _rotation = rotation;
    }
    return self;
}

- (instancetype)newI420Buffer {
    CVTI420Buffer *i420Buffer = [[CVTI420Buffer alloc] initWithPixelBuffer:self.pixelBufferRef rotation:_rotation];
    if ([i420Buffer toI420:self.pixelBufferRef] != -1) {
        return i420Buffer;
    }
    return nil;
}

+ (instancetype)newI420Frame:(CVPixelBufferRef)pixelBuffer rotation:(CVTVideoRotation)rotation {
    CVTI420Buffer *i420Buffer = [[CVTI420Buffer alloc] initWithPixelBuffer:pixelBuffer rotation:rotation];
    if ([i420Buffer toI420:pixelBuffer] != -1) {
        return i420Buffer;
    }
    return nil;
}

- (int)toI420:(CVPixelBufferRef)pixelBufferRef {
    if (_pixelBufferRef) {
        CVPixelBufferRelease(_pixelBufferRef);
        _pixelBufferRef = nil;
    }
    
    CVPixelBufferRetain(pixelBufferRef);
    _pixelBufferRef = pixelBufferRef;
    
    int ret = -1;
    if (!_pixelBufferRef) {
        return ret;
    }
    
    const OSType pixelFormat = CVPixelBufferGetPixelFormatType(_pixelBufferRef);
    
    CVPixelBufferLockBaseAddress(_pixelBufferRef, kCVPixelBufferLock_ReadOnly);
    
    int width = (int)CVPixelBufferGetWidth(_pixelBufferRef);
    int height = (int)CVPixelBufferGetHeight(_pixelBufferRef);
    self.width = width;
    self.height = height;
    
    //Note: Due to the size rules of the YUV data, the width may be inconsistent with the size of the y plane and the uv plane, so you need to use src_stride_y to calculate the memory size of _dataY, _dataU, and _dataV, otherwise there will be problems.
    
    
    switch (pixelFormat) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: {
            uint8_t *yBuffer = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(_pixelBufferRef, 0);
            uint8_t *cbCrBuffer = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(_pixelBufferRef, 1);
            int src_stride_y = (int)CVPixelBufferGetBytesPerRowOfPlane(_pixelBufferRef, 0);
            int src_stride_uv = (int)CVPixelBufferGetBytesPerRowOfPlane(_pixelBufferRef, 1);
            int sourceHeight = (int)CVPixelBufferGetHeight(_pixelBufferRef);
            int strideY_ = src_stride_y;
            int strideU_ = (src_stride_uv + 1) / 2;
            int strideV_ = (src_stride_uv + 1) / 2;
            
            _strideY = strideY_;
            _strideU = strideU_;
            _strideV = strideV_;
            
            [self createBufferWithStrideY:src_stride_y strideUV:src_stride_uv sourceHeight:sourceHeight];
            
            ret = NV12ToI420(yBuffer,
                             strideY_,
                             cbCrBuffer,
                             src_stride_uv,
                             _dataY,
                             strideY_,
                             _dataU,
                             strideU_,
                             _dataV,
                             strideV_,
                             width, height);
            break;
        }
        case kCVPixelFormatType_32BGRA:
        case kCVPixelFormatType_32ARGB:
        case kCVPixelFormatType_24RGB: {
            uint8_t *src = (uint8_t *)CVPixelBufferGetBaseAddress(_pixelBufferRef);
            int bytesPerRow = (int)CVPixelBufferGetBytesPerRow(_pixelBufferRef);
            int sourceWidth = (int)CVPixelBufferGetWidth(_pixelBufferRef);
            int sourceHeight = (int)CVPixelBufferGetHeight(_pixelBufferRef);
            
            int strideY_ = ceil(sourceWidth / (1.0 * align_pixel)) * align_pixel;
            int strideU_ = (strideY_ + 1) / 2;
            int strideV_ = (strideY_ + 1) / 2;
            
            _strideY = strideY_;
            _strideU = strideU_;
            _strideV = strideV_;
            
            [self createBufferWithStrideY:strideY_ strideUV:strideY_ sourceHeight:sourceHeight];
            if (pixelFormat == kCVPixelFormatType_32BGRA) {
                // Corresponds to libyuv::FOURCC_ARGB
                ret = ARGBToI420(src,
                                 bytesPerRow,
                                 _dataY,
                                 strideY_,
                                 _dataU,
                                 strideU_,
                                 _dataV,
                                 strideV_,
                                 width,
                                 sourceHeight);
            } else if (pixelFormat == kCVPixelFormatType_32ARGB) {
                // Corresponds to libyuv::FOURCC_BGRA
                ret = BGRAToI420(src,
                                 bytesPerRow,
                                 _dataY,
                                 strideY_,
                                 _dataU,
                                 strideU_,
                                 _dataV,
                                 strideV_,
                                 width,
                                 sourceHeight);
            } else if (pixelFormat == kCVPixelFormatType_24RGB) {
                ret = RGB24ToI420(src,
                                  bytesPerRow,
                                  _dataY,
                                  strideY_,
                                  _dataU,
                                  strideU_,
                                  _dataV,
                                  strideV_,
                                  width,
                                  height);
            }
            break;
        }
        default: {}
    }
    
    CVPixelBufferUnlockBaseAddress(_pixelBufferRef, kCVPixelBufferLock_ReadOnly);
    return ret;
}

- (void)createBufferWithStrideY:(int)src_stride_y
                       strideUV:(int)src_stride_uv
                   sourceHeight:(int)sourceHeight {
    
    if (_dataY == NULL) {
        _dataY = (uint8_t *)malloc(_strideY * sourceHeight);
    }
    memset(_dataY, 0, _strideY * sourceHeight);
    if (_dataU == NULL) {
        _dataU = (uint8_t *)malloc(_strideU * (sourceHeight + 1) / 2);
    }
    memset(_dataU, 0, _strideU * (sourceHeight + 1) / 2);
    if (_dataV == NULL) {
        _dataV = (uint8_t *)malloc(_strideV * (sourceHeight + 1) / 2);
    }
    memset(_dataV, 0, _strideV * (sourceHeight + 1) / 2);
}

- (CVTVideoRotation)rotation {
    return _rotation;
}

- (void)dealloc {
    //    NSLog(@"%s", __func__);
    if (_pixelBufferRef) {
        CVPixelBufferRelease(_pixelBufferRef);
        _pixelBufferRef = nil;
    }
    if (_dataY) {
        free((void *)_dataY);
        _dataY = NULL;
    }
    if (_dataU) {
        free((void *)_dataU);
        _dataU = NULL;
    }
    if (_dataV) {
        free((void *)_dataV);
        _dataV = NULL;
    }
}

@end

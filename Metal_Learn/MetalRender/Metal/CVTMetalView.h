//
//  CVTMetalView.h
//  Metal_Learn
//
//  Created by hejiangshan on 2022/3/8.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>
#import "CVTI420Buffer.h"
@class CVTMetalView;

NS_ASSUME_NONNULL_BEGIN

@protocol CVTMetalViewDelegate <NSObject>

- (void)videoView:(CVTMetalView *)videoView didChangeVideoSize:(NSSize)size;

@end

@interface CVTMetalView : NSView

@property (nonatomic, weak) id<CVTMetalViewDelegate> delegate;

/** @abstract   A wrapped RTCVideoRotation, or nil.
    @discussion When not nil, the rotation of the actual frame is ignored when rendering.
 */
@property(atomic, nullable) NSValue *rotationOverride;

+ (BOOL)isMetalAvailable;

- (void)renderPixelBuffer:(nullable CVPixelBufferRef)pixelBuffer;

- (void)setSize:(CGSize)size;


@end

NS_ASSUME_NONNULL_END

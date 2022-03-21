//
//  CVTMetalView.m
//  Metal_Learn
//
//  Created by hejiangshan on 2022/3/8.
//

#define MTL_STRINGIFY(s) @ #s

#import "CVTMetalView.h"

static const NSInteger kMaxInflightBuffers = 1;

static NSString *const vertexFunctionName = @"vertexPassthrough";
static NSString *const fragmentFunctionName = @"fragmentColorConversion";

static NSString *const pipelineDescriptorLabel = @"RTCPipeline";
static NSString *const commandBufferLabel = @"RTCCommandBuffer";
static NSString *const renderEncoderLabel = @"RTCEncoder";
static NSString *const renderEncoderDebugGroup = @"RTCDrawFrame";

static NSString *const shaderSource = MTL_STRINGIFY(
                                                    using namespace metal;
                                                    
                                                    typedef struct {
                                                        packed_float2 position;
                                                        packed_float2 texcoord;
                                                    } Vertex;
                                                    
                                                    typedef struct {
                                                        float4 position[[position]];
                                                        float2 texcoord;
                                                    } Varyings;
                                                    
                                                    vertex Varyings vertexPassthrough(constant Vertex *verticies[[buffer(0)]],
                                                                                      unsigned int vid[[vertex_id]]) {
                                                                                          Varyings out;
                                                                                          constant Vertex &v = verticies[vid];
                                                                                          out.position = float4(float2(v.position), 0.0, 1.0);
                                                                                          out.texcoord = v.texcoord;
                                                                                          
                                                                                          return out;
                                                                                      }
                                                    
                                                    fragment half4 fragmentColorConversion(
                                                                                           Varyings in[[stage_in]],
                                                                                           texture2d<float, access::sample> textureY[[texture(0)]],
                                                                                           texture2d<float, access::sample> textureU[[texture(1)]],
                                                                                           texture2d<float, access::sample> textureV[[texture(2)]]) {
                                                                                               constexpr sampler s(address::clamp_to_edge, filter::linear);
                                                                                               float y;
                                                                                               float u;
                                                                                               float v;
                                                                                               float r;
                                                                                               float g;
                                                                                               float b;
                                                                                               // Conversion for YUV to rgb from http://www.fourcc.org/fccyvrgb.php
                                                                                               y = textureY.sample(s, in.texcoord).r;
                                                                                               u = textureU.sample(s, in.texcoord).r;
                                                                                               v = textureV.sample(s, in.texcoord).r;
                                                                                               u = u - 0.5;
                                                                                               v = v - 0.5;
                                                                                               r = y + 1.403 * v;
                                                                                               g = y - 0.344 * u - 0.714 * v;
                                                                                               b = y + 1.770 * u;
                                                                                               
                                                                                               float4 out = float4(r, g, b, 1.0);
                                                                                               
                                                                                               return half4(out);
                                                                                           });

// Computes the texture coordinates given rotation and cropping.
static inline void getCubeVertexData(int cropX,
                                     int cropY,
                                     int cropWidth,
                                     int cropHeight,
                                     size_t frameWidth,
                                     size_t frameHeight,
                                     CVTVideoRotation rotation,
                                     float *buffer) {
    // The computed values are the adjusted texture coordinates, in [0..1].
    // For the left and top, 0.0 means no cropping and e.g. 0.2 means we're skipping 20% of the
    // left/top edge.
    // For the right and bottom, 1.0 means no cropping and e.g. 0.8 means we're skipping 20% of the
    // right/bottom edge (i.e. render up to 80% of the width/height).
    float cropLeft = cropX / (float)frameWidth;
    float cropRight = (cropX + cropWidth) / (float)frameWidth;
    float cropTop = cropY / (float)frameHeight;
    float cropBottom = (cropY + cropHeight) / (float)frameHeight;
    
    // These arrays map the view coordinates to texture coordinates, taking cropping and rotation
    // into account. The first two columns are view coordinates, the last two are texture coordinates.
    switch (rotation) {
        case CVTVideoRotation_0: {
            float values[16] = {-1.0, -1.0, cropLeft, cropBottom,
                1.0, -1.0, cropRight, cropBottom,
                -1.0,  1.0, cropLeft, cropTop,
                1.0,  1.0, cropRight, cropTop};
            memcpy(buffer, &values, sizeof(values));
        } break;
        case CVTVideoRotation_90: {
            float values[16] = {-1.0, -1.0, cropRight, cropBottom,
                1.0, -1.0, cropRight, cropTop,
                -1.0,  1.0, cropLeft, cropBottom,
                1.0,  1.0, cropLeft, cropTop};
            memcpy(buffer, &values, sizeof(values));
        } break;
        case CVTVideoRotation_180: {
            float values[16] = {-1.0, -1.0, cropRight, cropTop,
                1.0, -1.0, cropLeft, cropTop,
                -1.0,  1.0, cropRight, cropBottom,
                1.0,  1.0, cropLeft, cropBottom};
            memcpy(buffer, &values, sizeof(values));
        } break;
        case CVTVideoRotation_270: {
            float values[16] = {-1.0, -1.0, cropLeft, cropTop,
                1.0, -1.0, cropLeft, cropBottom,
                -1.0, 1.0, cropRight, cropTop,
                1.0, 1.0, cropRight, cropBottom};
            memcpy(buffer, &values, sizeof(values));
        } break;
    }
}


@interface CVTMetalView () <MTKViewDelegate>

@property(nonatomic, strong) MTKView *metalView;
@property(atomic, strong) CVTI420Buffer *videoFrame;

@end

@implementation CVTMetalView
{
    // Controller.
    dispatch_semaphore_t _inflight_semaphore;
    
    // Renderer.
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLLibrary> _defaultLibrary;
    id<MTLRenderPipelineState> _pipelineState;
    
    // Buffers.
    id<MTLBuffer> _vertexBuffer;
    
    // Textures.
    id<MTLTexture> _yTexture;
    id<MTLTexture> _uTexture;
    id<MTLTexture> _vTexture;
    
    MTLTextureDescriptor *_descriptor;
    MTLTextureDescriptor *_chromaDescriptor;
    
    int _width;
    int _height;
    int _chromaWidth;
    int _chromaHeight;
    
    int _oldFrameWidth;
    int _oldFrameHeight;
    int _oldCropWidth;
    int _oldCropHeight;
    int _oldCropX;
    int _oldCropY;
    CVTVideoRotation _oldRotation;
}

@synthesize rotationOverride = _rotationOverride;

- (instancetype)initWithFrame:(CGRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self configure];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aCoder {
    self = [super initWithCoder:aCoder];
    if (self) {
        [self configure];
    }
    return self;
}

+ (BOOL)isMetalAvailable {
    return [MTLCopyAllDevices() count] > 0;
}

- (void)configure {
    if ([[self class] isMetalAvailable]) {
        _inflight_semaphore = dispatch_semaphore_create(kMaxInflightBuffers);
        
        _metalView = [[MTKView alloc] initWithFrame:self.bounds];
        [self addSubview:_metalView];
        _metalView.layerContentsPlacement = NSViewLayerContentsPlacementScaleProportionallyToFit;
        _metalView.translatesAutoresizingMaskIntoConstraints = NO;
        _metalView.framebufferOnly = YES;
        _metalView.delegate = self;
        
        BOOL success = NO;
        if ([self setupMetal]) {
            _metalView.device = _device;
            _metalView.preferredFramesPerSecond = 30;
            _metalView.autoResizeDrawable = NO;
            
            [self loadAssets];
            
            float vertexBufferArray[16] = {0};
            _vertexBuffer = [_device newBufferWithBytes:vertexBufferArray
                                                 length:sizeof(vertexBufferArray)
                                                options:MTLResourceCPUCacheModeWriteCombined];
            success = YES;
        }
    }
}

- (BOOL)setupMetal {
    // Set the view to use the default device.
    _device = MTLCreateSystemDefaultDevice();
    if (!_device) {
        return NO;
    }
    
    // Create a new command queue.
    _commandQueue = [_device newCommandQueue];
    
    // Load metal library from source.
    NSError *libraryError = nil;
    NSString *shaderSource = [self shaderSource];
    
    id<MTLLibrary> sourceLibrary =
    [_device newLibraryWithSource:shaderSource options:NULL error:&libraryError];
    
    if (libraryError) {
        //        RTCLogError(@"Metal: Library with source failed\n%@", libraryError);
        return NO;
    }
    
    if (!sourceLibrary) {
        //        RTCLogError(@"Metal: Failed to load library. %@", libraryError);
        return NO;
    }
    _defaultLibrary = sourceLibrary;
    
    return YES;
}

- (NSString *)shaderSource {
    return shaderSource;
}

- (void)loadAssets {
    id<MTLFunction> vertexFunction = [_defaultLibrary newFunctionWithName:vertexFunctionName];
    id<MTLFunction> fragmentFunction = [_defaultLibrary newFunctionWithName:fragmentFunctionName];
    
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = pipelineDescriptorLabel;
    pipelineDescriptor.vertexFunction = vertexFunction;
    pipelineDescriptor.fragmentFunction = fragmentFunction;
    pipelineDescriptor.colorAttachments[0].pixelFormat = _metalView.colorPixelFormat;
    pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatInvalid;
    NSError *error = nil;
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!_pipelineState) {
        //        RTCLogError(@"Metal: Failed to create pipeline state. %@", error);
    }
}

- (void)render {
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = commandBufferLabel;
    
    __block dispatch_semaphore_t block_semaphore = _inflight_semaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull) {
        // GPU work completed.
        dispatch_semaphore_signal(block_semaphore);
    }];
    
    MTLRenderPassDescriptor *renderPassDescriptor = _metalView.currentRenderPassDescriptor;
    if (renderPassDescriptor) {  // Valid drawable.
        id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = renderEncoderLabel;
        
        // Set context state.
        [renderEncoder pushDebugGroup:renderEncoderDebugGroup];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
        [self uploadTexturesToRenderEncoder:renderEncoder];
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                          vertexStart:0
                          vertexCount:4
                        instanceCount:1];
        [renderEncoder popDebugGroup];
        [renderEncoder endEncoding];
        
        [commandBuffer presentDrawable:_metalView.currentDrawable];
    }
    
    // CPU work is completed, GPU work can be started.
    [commandBuffer commit];
}

- (BOOL)setupTexturesForFrame:(nonnull CVTI420Buffer *)frame {
    if (![self setTexturesForFrame:frame]) {
        return NO;
    }

    id<MTLDevice> device = _device;
    if (!device) {
        return NO;
    }

    // Luma (y) texture.
    if (!_descriptor || _width != frame.width || _height != frame.height) {
        _width = frame.width;
        _height = frame.height;
        _descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                                                         width:_width
                                                                        height:_height
                                                                     mipmapped:NO];
        _descriptor.usage = MTLTextureUsageShaderRead;
        _yTexture = [device newTextureWithDescriptor:_descriptor];
    }

    // Chroma (u,v) textures
    [_yTexture replaceRegion:MTLRegionMake2D(0, 0, _width, _height)
                 mipmapLevel:0
                   withBytes:frame.dataY
                 bytesPerRow:frame.strideY];

    if (!_chromaDescriptor || _chromaWidth != frame.width / 2 || _chromaHeight != frame.height / 2) {
        _chromaWidth = frame.width / 2;
        _chromaHeight = frame.height / 2;
        _chromaDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                                                           width:_chromaWidth
                                                          height:_chromaHeight
                                                       mipmapped:NO];
        _chromaDescriptor.usage = MTLTextureUsageShaderRead;
        _uTexture = [device newTextureWithDescriptor:_chromaDescriptor];
        _vTexture = [device newTextureWithDescriptor:_chromaDescriptor];
    }

    [_uTexture replaceRegion:MTLRegionMake2D(0, 0, _chromaWidth, _chromaHeight)
                 mipmapLevel:0
                   withBytes:frame.dataU
                 bytesPerRow:frame.strideU];
    [_vTexture replaceRegion:MTLRegionMake2D(0, 0, _chromaWidth, _chromaHeight)
                 mipmapLevel:0
                   withBytes:frame.dataV
                 bytesPerRow:frame.strideV];

    return (_uTexture != nil) && (_yTexture != nil) && (_vTexture != nil);
}

- (BOOL)setTexturesForFrame:(nonnull CVTI420Buffer *)frame {
    // Apply rotation override if set.
    CVTVideoRotation rotation;
    NSValue *rotationOverride = self.rotationOverride;
    if (rotationOverride) {
#if defined(__IPHONE_11_0) && defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && \
(__IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_11_0)
        if (@available(iOS 11, *)) {
            [rotationOverride getValue:&rotation size:sizeof(rotation)];
        } else
#endif
        {
            [rotationOverride getValue:&rotation];
        }
    } else {
        rotation = frame.rotation;
    }
    
    int frameWidth, frameHeight, cropWidth, cropHeight, cropX, cropY;
    [self getWidth:&frameWidth
            height:&frameHeight
         cropWidth:&cropWidth
        cropHeight:&cropHeight
             cropX:&cropX
             cropY:&cropY
           ofFrame:frame];
    
    // Recompute the texture cropping and recreate vertexBuffer if necessary.
    if (cropX != _oldCropX || cropY != _oldCropY || cropWidth != _oldCropWidth ||
        cropHeight != _oldCropHeight || rotation != _oldRotation || frameWidth != _oldFrameWidth ||
        frameHeight != _oldFrameHeight) {
        getCubeVertexData(cropX,
                          cropY,
                          cropWidth,
                          cropHeight,
                          frameWidth,
                          frameHeight,
                          rotation,
                          (float *)_vertexBuffer.contents);
        _oldCropX = cropX;
        _oldCropY = cropY;
        _oldCropWidth = cropWidth;
        _oldCropHeight = cropHeight;
        _oldRotation = rotation;
        _oldFrameWidth = frameWidth;
        _oldFrameHeight = frameHeight;
    }
    
    return YES;
}

- (void)getWidth:(nonnull int *)width
          height:(nonnull int *)height
       cropWidth:(nonnull int *)cropWidth
      cropHeight:(nonnull int *)cropHeight
           cropX:(nonnull int *)cropX
           cropY:(nonnull int *)cropY
         ofFrame:(nonnull CVTI420Buffer *)frame {
    *width = frame.width;
    *height = frame.height;
    *cropWidth = frame.width;
    *cropHeight = frame.height;
    *cropX = 0;
    *cropY = 0;
}

- (void)uploadTexturesToRenderEncoder:(id<MTLRenderCommandEncoder>)renderEncoder {
    [renderEncoder setFragmentTexture:_yTexture atIndex:0];
    [renderEncoder setFragmentTexture:_uTexture atIndex:1];
    [renderEncoder setFragmentTexture:_vTexture atIndex:2];
}


#pragma mark - Public methods
- (void)renderPixelBuffer:(nullable CVPixelBufferRef)pixelBuffer {
    if (pixelBuffer == nil) {
        return;
    }
    
//    if (!self.videoFrame) {
////        self.videoFrame = [[CVTI420Buffer alloc] initWithPixelBuffer:pixelBuffer rotation:CVTVideoRotation_0];
//    }
    /*
     When rendering data, the reason why a new CVTI420Buffer object is created every time is to prevent the problem that dataY, dataU, and dataV in a CVTI420Buffer object are just cleared when the Metal is refreshed, causing the green screen to flash.
     */
    self.videoFrame = [CVTI420Buffer newI420Frame:pixelBuffer rotation:CVTVideoRotation_0];
//    int ret = [self.videoFrame toI420:pixelBuffer];
}

- (void)setSize:(CGSize)size {
    _metalView.drawableSize = size;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(videoView:didChangeVideoSize:)]) {
            [self.delegate videoView:self didChangeVideoSize:size];
        }
    });
    [_metalView draw];
}

#pragma mark - MTKViewDelegate methods
- (void)drawInMTKView:(nonnull MTKView *)view {
//    NSLog(@"drawInMTKView--Thread: %@ ", [NSThread currentThread]);
    if (self.videoFrame == nil) {
        return;
    }
    if (view == self.metalView) {
        [self drawFrame:self.videoFrame];
    }
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    
}

- (void)drawFrame:(CVTI420Buffer *)frame {
    @autoreleasepool {
        // Wait until the inflight (curently sent to GPU) command buffer
        // has completed the GPU work.
        dispatch_semaphore_wait(_inflight_semaphore, DISPATCH_TIME_FOREVER);
        
        if ([self setupTexturesForFrame:frame]) {
            [self render];
        } else {
            dispatch_semaphore_signal(_inflight_semaphore);
        }
    }
}

- (void)dealloc
{
    NSLog(@"%s", __func__);
}
@end

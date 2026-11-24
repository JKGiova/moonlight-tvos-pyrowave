// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <TargetConditionals.h>
#if TARGET_OS_TV
#import <AVKit/AVKit.h>
#import <AVKit/UIWindow.h>
#endif
#include <memory>

namespace PWClient {
// Retain the IOSurface-backed buffer and Metal views until GPU completion.
struct VideoSurface {
    CVPixelBufferRef image=nullptr;
    CVMetalTextureRef y=nullptr,uv=nullptr;
    CMVideoFormatDescriptionRef format=nullptr;
    CMSampleBufferRef sample=nullptr;
    ~VideoSurface() {
        if (sample) CFRelease(sample);
        if (format) CFRelease(format);
        if (uv) CFRelease(uv);
        if (y) CFRelease(y);
        if (image) CFRelease(image);
    }
};
enum class VideoEnqueueResult { Enqueued, Backpressure, Failed };
class HDRPresenter {
    CVPixelBufferPoolRef pool=nullptr;
    CVMetalTextureCacheRef cache=nullptr;
    id<MTLComputePipelineState> pack;
    int width=0,height=0;
    bool chroma444=false;
#if TARGET_OS_TV
    AVDisplayCriteria* ownedCriteria=nil;
    int lastHDR=-1,lastSpace=-1;
#endif
    std::shared_ptr<VideoSurface> allocateSurface() {
        auto surface=std::make_shared<VideoSurface>();
        // At most three presentation surfaces; never grow an unbounded video queue.
        NSDictionary* limit=@{(id)kCVPixelBufferPoolAllocationThresholdKey:@3};
        CVReturn allocation=CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nullptr,pool,(__bridge CFDictionaryRef)limit,&surface->image);
        if (allocation==kCVReturnWouldExceedAllocationThreshold) {
            CVMetalTextureCacheFlush(cache,0);
            allocation=CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nullptr,pool,(__bridge CFDictionaryRef)limit,&surface->image);
        }
        if (allocation!=kCVReturnSuccess) return {};
        NSDictionary* textureAttributes=@{(id)kCVMetalTextureUsage:@(MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite)};
        if (CVMetalTextureCacheCreateTextureFromImage(nullptr,cache,surface->image,(__bridge CFDictionaryRef)textureAttributes,MTLPixelFormatR16Unorm,width,height,0,&surface->y)!=kCVReturnSuccess ||
            CVMetalTextureCacheCreateTextureFromImage(nullptr,cache,surface->image,(__bridge CFDictionaryRef)textureAttributes,MTLPixelFormatRG16Unorm,width/(chroma444?1:2),height/(chroma444?1:2),1,&surface->uv)!=kCVReturnSuccess) return {};
        return surface;
    }
public:
    int frameRate=60;
#if TARGET_OS_TV
    __weak UIView* hostView=nil;
#endif
    AVSampleBufferDisplayLayer* layer=nil;
    ~HDRPresenter() { if (cache) CFRelease(cache); if (pool) CFRelease(pool); }
    bool prepare(id<MTLDevice> device,int w,int h,bool full,bool c444) {
        if (@available(tvOS 17.0,macOS 14.0,iOS 17.0,*)) {} else return false;
        width=w;height=h;chroma444=c444;
        const OSType type=c444?(full?kCVPixelFormatType_444YpCbCr10BiPlanarFullRange:kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange):
            (full?kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange);
        NSDictionary* attributes=@{(id)kCVPixelBufferPixelFormatTypeKey:@(type),
            (id)kCVPixelBufferWidthKey:@(w),(id)kCVPixelBufferHeightKey:@(h),
            (id)kCVPixelBufferMetalCompatibilityKey:@YES,(id)kCVPixelBufferIOSurfacePropertiesKey:@{}};
        if (CVPixelBufferPoolCreate(nullptr,nullptr,(__bridge CFDictionaryRef)attributes,&pool)!=kCVReturnSuccess ||
            CVMetalTextureCacheCreate(nullptr,nullptr,device,nullptr,&cache)!=kCVReturnSuccess) return false;
        // Quantize normalized code values to 10-bit MSB-aligned biplanar samples.
        // No matrix/transfer conversion: preserve host PQ (or 10-bit SDR) values.
        const char* source=R"MSL(
#include <metal_stdlib>
using namespace metal;
kernel void pw_pack10(texture2d<float,access::read> y [[texture(0)]],
    texture2d<float,access::read> u [[texture(1)]],texture2d<float,access::read> v [[texture(2)]],
    texture2d<float,access::write> oy [[texture(3)]],texture2d<float,access::write> ouv [[texture(4)]],uint2 p [[thread_position_in_grid]]) {
    if (p.x<oy.get_width() && p.y<oy.get_height())
        oy.write(float4(round(clamp(y.read(p).r,0.0f,1.0f)*1023.0f)*64.0f/65535.0f),p);
    if (p.x<ouv.get_width() && p.y<ouv.get_height()) {
        float2 c=round(clamp(float2(u.read(p).r,v.read(p).r),0.0f,1.0f)*1023.0f)*64.0f/65535.0f;
        ouv.write(float4(c,0,1),p);
    }
})MSL";
        NSError* error=nil;
        auto library=[device newLibraryWithSource:@(source) options:nil error:&error];
        if (!library) return false;
        pack=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"pw_pack10"] error:&error];
        if (!pack) return false;
        auto probe=allocateSurface();
        const bool supported=bool(probe);
        probe.reset(); CVMetalTextureCacheFlush(cache,0);
        return supported;
    }
    std::shared_ptr<VideoSurface> encode(id<MTLCommandBuffer> command,id<MTLTexture> const planes[3],
            int space,bool hdr,NSData* mastering,NSData* light) {
        if (space<0 || space>2 || (hdr && space!=2)) return {};
        auto surface=allocateSurface();
        if (!surface) return {};
        CFStringRef primaries=space==2?kCVImageBufferColorPrimaries_ITU_R_2020:kCVImageBufferColorPrimaries_ITU_R_709_2;
        CFStringRef matrix=space==2?kCVImageBufferYCbCrMatrix_ITU_R_2020:space==0?kCVImageBufferYCbCrMatrix_ITU_R_601_4:kCVImageBufferYCbCrMatrix_ITU_R_709_2;
        CVBufferSetAttachment(surface->image,kCVImageBufferColorPrimariesKey,primaries,kCVAttachmentMode_ShouldPropagate);
        CVBufferSetAttachment(surface->image,kCVImageBufferYCbCrMatrixKey,matrix,kCVAttachmentMode_ShouldPropagate);
        CVBufferSetAttachment(surface->image,kCVImageBufferTransferFunctionKey,hdr?kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ:kCVImageBufferTransferFunction_ITU_R_709_2,kCVAttachmentMode_ShouldPropagate);
        CVBufferSetAttachment(surface->image,kCVImageBufferChromaLocationTopFieldKey,kCVImageBufferChromaLocation_Center,kCVAttachmentMode_ShouldPropagate);
        CVBufferRemoveAttachment(surface->image,kCVImageBufferMasteringDisplayColorVolumeKey);
        CVBufferRemoveAttachment(surface->image,kCVImageBufferContentLightLevelInfoKey);
        if (hdr && mastering) CVBufferSetAttachment(surface->image,kCVImageBufferMasteringDisplayColorVolumeKey,(__bridge CFDataRef)mastering,kCVAttachmentMode_ShouldPropagate);
        if (hdr && light) CVBufferSetAttachment(surface->image,kCVImageBufferContentLightLevelInfoKey,(__bridge CFDataRef)light,kCVAttachmentMode_ShouldPropagate);
        auto encoder=[command computeCommandEncoder];
        if (!encoder) return {};
        [encoder setComputePipelineState:pack];
        for (unsigned i=0;i<3;++i) [encoder setTexture:planes[i] atIndex:i];
        [encoder setTexture:CVMetalTextureGetTexture(surface->y) atIndex:3];
        [encoder setTexture:CVMetalTextureGetTexture(surface->uv) atIndex:4];
        [encoder dispatchThreadgroups:MTLSizeMake((width+7)/8,(height+7)/8,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
        [encoder endEncoding];
        return surface;
    }
    void stop() {
#if TARGET_OS_TV
        auto manager=hostView.window.avDisplayManager;
        if (ownedCriteria && manager.preferredDisplayCriteria==ownedCriteria)
            manager.preferredDisplayCriteria=nil;
        ownedCriteria=nil;
#endif
        if (@available(tvOS 17.0,macOS 14.0,iOS 17.0,*))
            [layer.sampleBufferRenderer flushWithRemovalOfDisplayedImage:YES completionHandler:nil];
        [layer removeFromSuperlayer];
    }
    bool makeSample(const std::shared_ptr<VideoSurface>& surface) {
        // GPU completion precedes this call. A surface is submitted at most once.
        if (surface->sample) return false;
        if (CMVideoFormatDescriptionCreateForImageBuffer(nullptr,surface->image,&surface->format)!=noErr) return false;
        CMSampleTimingInfo timing={kCMTimeInvalid,kCMTimeZero,kCMTimeInvalid};
        if (CMSampleBufferCreateReadyWithImageBuffer(nullptr,surface->image,surface->format,&timing,&surface->sample)!=noErr) return false;
        CFArrayRef attachments=CMSampleBufferGetSampleAttachmentsArray(surface->sample,true);
        CFDictionarySetValue((CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments,0),kCMSampleAttachmentKey_DisplayImmediately,kCFBooleanTrue);
        return true;
    }
    VideoEnqueueResult enqueue(const std::shared_ptr<VideoSurface>& surface) {
        // Main thread only; readiness and the pool threshold bound backpressure.
        if (@available(tvOS 17.0,macOS 14.0,iOS 17.0,*)) {
            auto renderer=layer.sampleBufferRenderer;
            if (renderer.status==AVQueuedSampleBufferRenderingStatusFailed) return VideoEnqueueResult::Failed;
            if (!renderer.readyForMoreMediaData) return VideoEnqueueResult::Backpressure;
            if (!makeSample(surface)) return VideoEnqueueResult::Failed;
#if TARGET_OS_TV
            auto transfer=CVBufferCopyAttachment(surface->image,kCVImageBufferTransferFunctionKey,nullptr);
            auto primary=CVBufferCopyAttachment(surface->image,kCVImageBufferColorPrimariesKey,nullptr);
            const bool hdr=transfer && CFEqual(transfer,kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ);
            const int space=primary && CFEqual(primary,kCVImageBufferColorPrimaries_ITU_R_2020)?2:1;
            if (transfer) CFRelease(transfer);
            if (primary) CFRelease(primary);
            if (lastHDR!=int(hdr) || lastSpace!=space) {
                auto manager=hostView.window.avDisplayManager;
                manager.preferredDisplayCriteria=[[AVDisplayCriteria alloc] initWithRefreshRate:frameRate formatDescription:surface->format];
                ownedCriteria=manager.preferredDisplayCriteria;
                lastHDR=hdr;lastSpace=space;
            }
#endif
            [renderer enqueueSampleBuffer:surface->sample];
            return renderer.status==AVQueuedSampleBufferRenderingStatusFailed ? VideoEnqueueResult::Failed : VideoEnqueueResult::Enqueued;
        }
        return VideoEnqueueResult::Failed;
    }
};
}

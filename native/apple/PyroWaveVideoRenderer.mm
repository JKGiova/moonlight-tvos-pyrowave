// SPDX-License-Identifier: GPL-3.0-or-later
#import "PyroWaveVideoRenderer.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include "pyrowave_metal.h"
#include "pyrowave_decoder_backend.h"
#include "pyrowaveframing.h"
#include "latest_frame_queue.hpp"
#include "color_conversion.hpp"
#include "PyroWavePresenterSource.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <memory>

namespace {
constexpr size_t MaxFrameBytes = 64U*1024U*1024U;
struct Frame { NSData* data; int colorSpace; bool fullRange; double received; };
struct Slot {
    pyrowave_decoder decoder = nullptr;
    __strong id<MTLTexture> planes[3];
    PyroWaveFraming::Frame parsed;
    ~Slot() { if (decoder) pyrowave_decoder_destroy(decoder); }
};
// Kept in the command-buffer completion block until GPU work has finished.
struct Runtime {
    pyrowave_device device = nullptr;
    Slot slots[2];
    ~Runtime() {
        for (auto& slot:slots) { if (slot.decoder) pyrowave_decoder_destroy(slot.decoder); slot.decoder=nullptr; }
        if (device) pyrowave_device_destroy(device);
    }
};

id distribution(std::vector<double> values) {
    if (values.empty()) return NSNull.null;
    std::sort(values.begin(),values.end());
    auto p=[&](double q) { return values.at(size_t(std::ceil(values.size()*q))-1); };
    return @{@"p50":@(p(.5)),@"p95":@(p(.95)),@"p99":@(p(.99)),@"samples":@(values.size())};
}
}

@implementation PyroWaveVideoRenderer {
    __weak UIView* _view;
    id<ConnectionCallbacks> _callbacks;
    CAMetalLayer* _layer;
    id<MTLDevice> _metal;
    id<MTLCommandQueue> _commands;
    id<MTLRenderPipelineState> _presenter;
    dispatch_queue_t _worker;
    NSLock* _lock;
    PWClient::LatestFrameQueue<Frame> _mailbox;
    std::shared_ptr<Runtime> _runtime;
    PyroWaveFraming::StreamGeometry _geometry;
    BOOL _pumpScheduled, _shown, _fatalReported, _fullRange;
    uint64_t _parserRejected, _profileRejected, _decodeFailed, _drawableDropped, _completed;
    std::array<double,2048> _readyTimes, _gpuTimes;
    size_t _readyCount, _gpuCount;
}

+ (BOOL)isDecoderBackendCandidate {
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();
    return device && pw_decoder_backend_is_candidate((__bridge void*)device);
}

- (instancetype)initWithView:(UIView*)view callbacks:(id<ConnectionCallbacks>)callbacks {
    if ((self=[super init])) {
        NSAssert([NSThread isMainThread],@"Metal layer must be created on the main thread");
        _view=view; _callbacks=callbacks; _lock=[NSLock new];
        _worker=dispatch_queue_create("org.moonlight.pyrowave.decode",DISPATCH_QUEUE_SERIAL);
        _metal=MTLCreateSystemDefaultDevice();
        _layer=[CAMetalLayer layer]; _layer.device=_metal;
        _layer.pixelFormat=MTLPixelFormatBGRA8Unorm; _layer.framebufferOnly=YES;
        _layer.maximumDrawableCount=2; _layer.allowsNextDrawableTimeout=YES;
        _layer.hidden=YES; _layer.backgroundColor=UIColor.blackColor.CGColor;
        CGColorSpaceRef colorSpace=CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
        _layer.colorspace=colorSpace; CGColorSpaceRelease(colorSpace);
        [view.layer addSublayer:_layer];
    }
    return self;
}

// Called during decoder setup, on the connection worker (never the UI thread).
- (int)prepareWidth:(int)width height:(int)height fullRange:(BOOL)fullRange {
    if ([NSThread isMainThread] || width<128 || height<128 || width>4096 || height>2160 || width%2 || height%2 ||
        !_metal || !pw_decoder_backend_is_candidate((__bridge void*)_metal)) return -1;
    _geometry={width,height,false}; _fullRange=fullRange;
    auto runtime=std::make_shared<Runtime>();
    pyrowave_device_create_info deviceInfo{}; deviceInfo.mtl_device=(__bridge void*)_metal;
    BOOL portable=NO;
#if DEBUG
    portable=[[NSUserDefaults standardUserDefaults] boolForKey:@"PyroWavePortable"];
#endif
    if (pw_decoder_device_create(&deviceInfo,portable,&runtime->device)!=PYROWAVE_SUCCESS) return -1;
    for (auto& slot:runtime->slots) {
        pyrowave_decoder_create_info info{}; info.device=runtime->device; info.width=width; info.height=height;
        info.chroma=PYROWAVE_CHROMA_SUBSAMPLING_420;
        if (pyrowave_decoder_create(&info,&slot.decoder)!=PYROWAVE_SUCCESS) return -1;
        for (unsigned p=0;p<3;++p) {
            auto descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                width:width/(p?2:1) height:height/(p?2:1) mipmapped:NO];
            descriptor.storageMode=MTLStorageModePrivate;
            descriptor.usage=MTLTextureUsageShaderWrite|MTLTextureUsageShaderRead;
            slot.planes[p]=[_metal newTextureWithDescriptor:descriptor];
            if (!slot.planes[p]) return -1;
        }
    }
    NSError* error=nil;
    id<MTLLibrary> library=[_metal newLibraryWithSource:[NSString stringWithUTF8String:PWClient::PresenterSource] options:nil error:&error];
    if (!library) { NSLog(@"PyroWave presenter: %@",error.localizedDescription); return -1; }
    auto descriptor=[MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction=[library newFunctionWithName:@"pw_vertex"];
    descriptor.fragmentFunction=[library newFunctionWithName:@"pw_fragment"];
    descriptor.colorAttachments[0].pixelFormat=_layer.pixelFormat;
    _presenter=[_metal newRenderPipelineStateWithDescriptor:descriptor error:&error];
    _commands=[_metal newCommandQueue];
    if (!_presenter || !_commands) return -1;
    _runtime=std::move(runtime);
    dispatch_sync(dispatch_get_main_queue(), ^{
        const CGFloat aspect=(CGFloat)width/height;
        CGSize bounds=self->_view.bounds.size;
        CGSize size=bounds.width>bounds.height*aspect ? CGSizeMake(bounds.height*aspect,bounds.height) : CGSizeMake(bounds.width,bounds.width/aspect);
        self->_layer.bounds=CGRectMake(0,0,size.width,size.height);
        self->_layer.position=CGPointMake(CGRectGetMidX(self->_view.bounds),CGRectGetMidY(self->_view.bounds));
        self->_layer.contentsScale=self->_view.window.screen.scale ?: 1;
        self->_layer.drawableSize=CGSizeMake(size.width*self->_layer.contentsScale,size.height*self->_layer.contentsScale);
    });
    return 0;
}

// Must be called with _lock held; at most one pump block is queued.
- (void)schedulePumpLocked {
    if (!_pumpScheduled && !_mailbox.stopped()) {
        _pumpScheduled=YES;
        dispatch_async(_worker, ^{ @autoreleasepool { [self pump]; } });
    }
}

- (int)submitDecodeUnit:(PDECODE_UNIT)unit {
    const double received=CACurrentMediaTime();
    if (!unit || unit->fullLength<8 || size_t(unit->fullLength)>MaxFrameBytes) {
        [_lock lock]; ++_parserRejected; [_lock unlock]; return DR_OK;
    }
    if ((unit->colorspace!=COLORSPACE_REC_601 && unit->colorspace!=COLORSPACE_REC_709) || unit->hdrActive) {
        [_lock lock]; ++_profileRejected; [_lock unlock]; [self failSession]; return DR_OK;
    }
    [_lock lock];
    if (_mailbox.stopped() || !_runtime) { [_lock unlock]; return DR_OK; }
    // Ownership is transferred before LiCompleteVideoFrame frees network buffers.
    void* bytes=malloc(size_t(unit->fullLength));
    if (!bytes) { ++_decodeFailed; [_lock unlock]; return DR_OK; }
    size_t offset=0, entries=0;
    bool valid=true;
    for (PLENTRY entry=unit->bufferList;entry;entry=entry->next) {
        if (++entries>65536 || entry->bufferType!=BUFFER_TYPE_PICDATA || entry->length<=0 || !entry->data ||
            size_t(entry->length)>size_t(unit->fullLength)-offset) { valid=false; break; }
        memcpy(static_cast<uint8_t*>(bytes)+offset,entry->data,size_t(entry->length)); offset+=size_t(entry->length);
    }
    if (!valid || offset!=size_t(unit->fullLength)) { free(bytes); ++_parserRejected; [_lock unlock]; return DR_OK; }
    NSData* data=[NSData dataWithBytesNoCopy:bytes length:offset freeWhenDone:YES];
    _mailbox.submit({data,unit->colorspace,bool(_fullRange),received});
    [self schedulePumpLocked]; [_lock unlock];
    return DR_OK; // PyroWave frames are independent; never request an IDR for a drop.
}

- (void)pump {
    for (;;) {
        [_lock lock];
        auto work=_mailbox.take();
        if (!work) { _pumpScheduled=NO; [_lock unlock]; return; }
        auto runtime=_runtime;
        [_lock unlock];
        auto& slot=runtime->slots[work->slot];
        std::string error;
        bool valid=PyroWaveFraming::parse(static_cast<const uint8_t*>(work->frame.data.bytes),work->frame.data.length,
            _geometry,slot.parsed,error) && !slot.parsed.partial;
        if (!valid) {
            [_lock lock]; ++_parserRejected; _mailbox.complete(work->slot); [_lock unlock]; continue;
        }
        pyrowave_decoder_clear(slot.decoder);
        for (const auto& span:slot.parsed.spans) {
            if (pyrowave_decoder_push_packet(slot.decoder,static_cast<const uint8_t*>(work->frame.data.bytes)+span.offset,span.size)!=PYROWAVE_SUCCESS) { valid=false; break; }
        }
        if (!valid || !pyrowave_decoder_decode_is_ready(slot.decoder,false)) {
            [_lock lock]; ++_parserRejected; _mailbox.complete(work->slot); [_lock unlock]; continue;
        }
        // Drawable acquisition happens on this worker; never wait for GPU/UI on main.
        id<CAMetalDrawable> drawable=[_layer nextDrawable];
        if (!drawable) {
            [_lock lock]; ++_drawableDropped; _mailbox.complete(work->slot); [_lock unlock]; continue;
        }
        [_lock lock]; BOOL stopped=_mailbox.stopped(); [_lock unlock];
        if (stopped) { [_lock lock]; _mailbox.complete(work->slot); [_lock unlock]; continue; }
        id<MTLCommandBuffer> command=[_commands commandBuffer];
        pyrowave_gpu_buffers output{};
        for (unsigned p=0;p<3;++p) output.planes[p]=(__bridge void*)slot.planes[p];
        if (!command || pyrowave_decoder_decode_gpu_buffer(slot.decoder,(__bridge void*)command,&output)!=PYROWAVE_SUCCESS) {
            [_lock lock]; ++_decodeFailed; _mailbox.complete(work->slot); [_lock unlock]; [self failSession]; continue;
        }
        auto pass=[MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture=drawable.texture;
        pass.colorAttachments[0].loadAction=MTLLoadActionDontCare; pass.colorAttachments[0].storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> encoder=[command renderCommandEncoderWithDescriptor:pass];
        if (!encoder) {
            [_lock lock]; ++_decodeFailed; _mailbox.complete(work->slot); [_lock unlock]; [self failSession]; continue;
        }
        const auto conversion=PWClient::colorConversion(work->frame.colorSpace,work->frame.fullRange);
        [encoder setRenderPipelineState:_presenter];
        for (unsigned p=0;p<3;++p) [encoder setFragmentTexture:slot.planes[p] atIndex:p];
        [encoder setFragmentBytes:&conversion length:sizeof(conversion) atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; [encoder endEncoding];
        [command presentDrawable:drawable];
        const size_t index=work->slot; const double received=work->frame.received;
        [command addCompletedHandler:^(id<MTLCommandBuffer> completed) {
            // runtime retains decoders, upload buffers and texture slots until completion.
            (void)runtime;
            [self->_lock lock];
            BOOL successful=completed.status==MTLCommandBufferStatusCompleted;
            BOOL reveal=successful && !self->_shown && !self->_mailbox.stopped();
            if (successful) {
                ++self->_completed;
                self->_readyTimes[self->_readyCount++%self->_readyTimes.size()]=(CACurrentMediaTime()-received)*1000;
                const double gpu=(completed.GPUEndTime-completed.GPUStartTime)*1000;
                if (completed.GPUStartTime>0 && gpu>0 && std::isfinite(gpu)) self->_gpuTimes[self->_gpuCount++%self->_gpuTimes.size()]=gpu;
                if (reveal) self->_shown=YES;
            } else ++self->_decodeFailed;
            self->_mailbox.complete(index); [self schedulePumpLocked]; [self->_lock unlock];
            if (reveal) dispatch_async(dispatch_get_main_queue(), ^{
                [self->_lock lock]; BOOL active=!self->_mailbox.stopped(); [self->_lock unlock];
                if (active) { self->_layer.hidden=NO; [self->_callbacks videoContentShown]; }
            });
            if (!successful) [self failSession];
        }];
        [command commit];
    }
}

- (void)failSession {
    [_lock lock];
    BOOL report=!_fatalReported && !_mailbox.stopped(); _fatalReported=YES;
    _mailbox.stop(); [_lock unlock];
    if (report) dispatch_async(dispatch_get_main_queue(), ^{ [self->_callbacks connectionTerminated:-1001]; });
}

- (void)stop {
    [_lock lock]; _mailbox.stop(); [_lock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{ [self->_layer removeFromSuperlayer]; });
}

- (NSDictionary*)statistics {
    [_lock lock];
    std::vector<double> ready(_readyTimes.begin(),_readyTimes.begin()+std::min(_readyCount,_readyTimes.size()));
    std::vector<double> gpu(_gpuTimes.begin(),_gpuTimes.begin()+std::min(_gpuCount,_gpuTimes.size()));
    NSDictionary* result=@{@"completed_frames":@(_completed),@"parser_rejected":@(_parserRejected),@"decode_failed":@(_decodeFailed),
        @"profile_rejected":@(_profileRejected),@"pending_replacements":@(_mailbox.pendingReplacements),@"drawable_dropped":@(_drawableDropped),
        @"gpu_in_flight":@(_mailbox.inFlight()),@"pending_frames":@(_mailbox.pending()?1:0),
        @"client_ready_completion_proxy_ms":distribution(ready),
        @"decode_and_color_gpu_ms":distribution(gpu),
        @"gpu_decode_ms":NSNull.null,@"auto_qualified":@NO,
        @"decoder_backend":@(pw_decoder_backend_name(_runtime ? _runtime->device : nullptr))};
    [_lock unlock]; return result;
}
@end

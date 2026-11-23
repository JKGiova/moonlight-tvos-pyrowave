// SPDX-License-Identifier: GPL-3.0-or-later
#import "PyroWaveVideoRenderer.h"
#import <Metal/Metal.h>
#import <TargetConditionals.h>
#import <QuartzCore/CAMetalLayer.h>
#include "pyrowave_metal.h"
#include "pyrowave_decoder_backend.h"
#include "pyrowaveframing.h"
#include "latest_frame_queue.hpp"
#include "frame_completion.hpp"
#include "color_conversion.hpp"
#include "PyroWavePresenterSource.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <memory>

namespace {
constexpr size_t MaxFrameBytes = 64U*1024U*1024U;
struct Frame {
    NSData* data;
    int colorSpace;
    bool fullRange;
    double received;
    int frameNumber;
    uint32_t rtpTimestamp;
    uint64_t receiveTimeUs, enqueueTimeUs, deliveryTimeUs;
    double copyMs;
};
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

struct FrameProgress {
    std::shared_ptr<Runtime> runtime;
    PWClient::FrameCompletion completion;
    int frameNumber;
    uint32_t rtpTimestamp;
    uint64_t receiveTimeUs, enqueueTimeUs, deliveryTimeUs;
    double received, workerStart, copyMs, prepareMs, drawableWaitMs = 0;
    double decodeCommitted = 0, decodeStart = 0, decodeEnd = 0;
    double renderCommitted = 0, renderStart = 0, renderEnd = 0, callbackTime = 0;
    bool decoded = false, rendered = false;
};

enum Timing {
    SubmitToWorker, InputQueue, CopyCpu, PrepareCpu, DrawableWait,
    DecodeQueue, RenderQueue, DecodeGpu, ColorGpu, DecodeAndColorGpu, ClientReady,
    CallbackDelay, SubmitToPresented, TimingCount
};
constexpr const char* TimingKeys[] = {
    "submit_to_worker_ms", "input_queue_ms", "copy_cpu_ms", "prepare_cpu_ms",
    "drawable_wait_ms", "decode_queue_ms", "render_queue_ms", "gpu_decode_ms", "color_gpu_ms",
    "decode_and_color_gpu_ms", "client_ready_gpu_end_ms",
    "gpu_callback_delay_ms", "submit_to_presented_ms"
};
static_assert(sizeof(TimingKeys)/sizeof(*TimingKeys) == TimingCount);
struct TimingWindow {
    std::array<double,2048> values{};
    size_t count = 0;
    void record(double milliseconds) {
        if (std::isfinite(milliseconds) && milliseconds >= 0)
            values[count++ % values.size()] = milliseconds;
    }
    std::vector<double> snapshot() const {
        return {values.begin(), values.begin() + std::min(count, values.size())};
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
    uint64_t _parserRejected, _profileRejected, _decodeFailed, _drawableDropped, _presentFailed, _decoded, _completed, _presented;
    std::array<TimingWindow,TimingCount> _timings;
    NSDictionary* _lastCompletedFrame;
}

+ (BOOL)isDecoderBackendCandidate {
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();
    return device && pw_decoder_backend_is_candidate((__bridge void*)device);
}

- (instancetype)initWithView:(UIView*)view callbacks:(id<ConnectionCallbacks>)callbacks {
    if ((self=[super init])) {
        NSAssert([NSThread isMainThread],@"Metal layer must be created on the main thread");
        _view=view; _callbacks=callbacks; _lock=[NSLock new];
        dispatch_queue_attr_t priority = dispatch_queue_attr_make_with_qos_class(
            DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        _worker=dispatch_queue_create("org.moonlight.pyrowave.decode",priority);
        _metal=MTLCreateSystemDefaultDevice();
        _layer=[CAMetalLayer layer]; _layer.device=_metal;
        _layer.pixelFormat=MTLPixelFormatBGRA8Unorm; _layer.framebufferOnly=YES;
        _layer.maximumDrawableCount=3; _layer.allowsNextDrawableTimeout=YES;
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
    [_lock lock];
    const bool unavailable=_mailbox.stopped() || bool(_runtime);
    [_lock unlock];
    if (unavailable) return -1;
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
    dispatch_sync(dispatch_get_main_queue(), ^{
        const CGFloat aspect=(CGFloat)width/height;
        CGSize bounds=self->_view.bounds.size;
        CGSize size=bounds.width>bounds.height*aspect ? CGSizeMake(bounds.height*aspect,bounds.height) : CGSizeMake(bounds.width,bounds.width/aspect);
        self->_layer.bounds=CGRectMake(0,0,size.width,size.height);
        self->_layer.position=CGPointMake(CGRectGetMidX(self->_view.bounds),CGRectGetMidY(self->_view.bounds));
        self->_layer.contentsScale=self->_view.window.screen.scale ?: 1;
        self->_layer.drawableSize=CGSizeMake(size.width*self->_layer.contentsScale,size.height*self->_layer.contentsScale);
    });
    // Publish fully initialized state under the same lock used by submit,
    // statistics and stop. An interrupted setup must never revive the session.
    [_lock lock];
    if (_mailbox.stopped()) { [_lock unlock]; return -1; }
    _geometry={width,height,false}; _fullRange=fullRange;
    _runtime=std::move(runtime);
    [_lock unlock];
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
    const uint64_t deliveryTimeUs=LiGetMicroseconds();
    if (!unit || unit->fullLength<8 || size_t(unit->fullLength)>MaxFrameBytes) {
        [_lock lock]; ++_parserRejected; [_lock unlock]; return DR_OK;
    }
    if ((unit->colorspace!=COLORSPACE_REC_601 && unit->colorspace!=COLORSPACE_REC_709) || unit->hdrActive) {
        [_lock lock]; ++_profileRejected; [_lock unlock]; [self failSession]; return DR_OK;
    }
    [_lock lock];
    if (_mailbox.stopped() || !_runtime) { [_lock unlock]; return DR_OK; }
    const bool fullRange = _fullRange;
    [_lock unlock];
    // Ownership is transferred before LiCompleteVideoFrame frees network buffers.
    void* bytes=malloc(size_t(unit->fullLength));
    if (!bytes) { [_lock lock]; ++_decodeFailed; [_lock unlock]; return DR_OK; }
    size_t offset=0, entries=0;
    bool valid=true;
    for (PLENTRY entry=unit->bufferList;entry;entry=entry->next) {
        if (++entries>65536 || entry->bufferType!=BUFFER_TYPE_PICDATA || entry->length<=0 || !entry->data ||
            size_t(entry->length)>size_t(unit->fullLength)-offset) { valid=false; break; }
        memcpy(static_cast<uint8_t*>(bytes)+offset,entry->data,size_t(entry->length)); offset+=size_t(entry->length);
    }
    if (!valid || offset!=size_t(unit->fullLength)) { free(bytes); [_lock lock]; ++_parserRejected; [_lock unlock]; return DR_OK; }
    NSData* data=[NSData dataWithBytesNoCopy:bytes length:offset freeWhenDone:YES];
    const double copyMs = (CACurrentMediaTime() - received) * 1000;
    [_lock lock];
    if (_mailbox.stopped()) { [_lock unlock]; return DR_OK; }
    _mailbox.submit({data,unit->colorspace,fullRange,received,unit->frameNumber,
        unit->rtpTimestamp,unit->receiveTimeUs,unit->enqueueTimeUs,deliveryTimeUs,copyMs});
    [self schedulePumpLocked]; [_lock unlock];
    return DR_OK; // PyroWave frames are independent; never request an IDR for a drop.
}

- (void)pump {
    for (;;) {
        @autoreleasepool {
            [_lock lock];
            auto work=_mailbox.take();
            if (!work) { _pumpScheduled=NO; [_lock unlock]; return; }
            auto runtime=_runtime;
            [_lock unlock];
            const double workerStart = CACurrentMediaTime();
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
            auto progress = std::make_shared<FrameProgress>();
            progress->runtime = runtime;
            progress->frameNumber = work->frame.frameNumber;
            progress->rtpTimestamp = work->frame.rtpTimestamp;
            progress->receiveTimeUs = work->frame.receiveTimeUs;
            progress->enqueueTimeUs = work->frame.enqueueTimeUs;
            progress->deliveryTimeUs = work->frame.deliveryTimeUs;
            progress->received = work->frame.received;
            progress->copyMs = work->frame.copyMs;
            progress->workerStart = workerStart;
            const size_t index = work->slot;
            id<MTLCommandBuffer> decode=[_commands commandBuffer];
            pyrowave_gpu_buffers output{};
            for (unsigned p=0;p<3;++p) output.planes[p]=(__bridge void*)slot.planes[p];
            if (!decode || pyrowave_decoder_decode_gpu_buffer(slot.decoder,(__bridge void*)decode,&output)!=PYROWAVE_SUCCESS) {
                [_lock lock]; ++_decodeFailed; _mailbox.complete(index); [_lock unlock]; [self failSession]; continue;
            }
            decode.label = @"PyroWave decode";
            [decode addCompletedHandler:^(id<MTLCommandBuffer> completed) {
                const double callbackTime = CACurrentMediaTime();
                [self->_lock lock];
                progress->decoded = completed.status == MTLCommandBufferStatusCompleted;
                if (progress->decoded) {
                    ++self->_decoded;
                    const double start = completed.GPUStartTime, end = completed.GPUEndTime;
                    if (start > 0 && progress->decodeCommitted <= start && start < end && end <= callbackTime) {
                        progress->decodeStart = start;
                        progress->decodeEnd = end;
                        self->_timings[DecodeGpu].record((end - start) * 1000);
                        self->_timings[DecodeQueue].record((start - progress->decodeCommitted) * 1000);
                    }
                } else ++self->_decodeFailed;
                if (progress->completion.completeDecode())
                    [self finishFrameLocked:progress slot:index];
                [self->_lock unlock];
                if (!progress->decoded) [self failSession];
            }];
            // Commit before asking the compositor for a drawable. Both command
            // buffers use the same queue and tracked plane textures.
            progress->decodeCommitted = CACurrentMediaTime();
            progress->prepareMs = (progress->decodeCommitted - workerStart) * 1000;
            [decode commit];

            const double drawableStart = CACurrentMediaTime();
            id<CAMetalDrawable> drawable=[_layer nextDrawable];
            progress->drawableWaitMs = (CACurrentMediaTime() - drawableStart) * 1000;
            [_lock lock];
            const bool stopped = _mailbox.stopped();
            if (!drawable) ++_drawableDropped;
            [_lock unlock];
            if (!drawable || stopped) {
                [_lock lock];
                if (progress->completion.completePresentation())
                    [self finishFrameLocked:progress slot:index];
                [_lock unlock];
                continue;
            }
            id<MTLCommandBuffer> command=[_commands commandBuffer];
            auto pass=[MTLRenderPassDescriptor renderPassDescriptor];
            pass.colorAttachments[0].texture=drawable.texture;
            pass.colorAttachments[0].loadAction=MTLLoadActionDontCare;
            pass.colorAttachments[0].storeAction=MTLStoreActionStore;
            id<MTLRenderCommandEncoder> encoder=[command renderCommandEncoderWithDescriptor:pass];
            if (!encoder) {
                [_lock lock];
                ++_presentFailed;
                if (progress->completion.completePresentation())
                    [self finishFrameLocked:progress slot:index];
                [_lock unlock];
                [self failSession];
                continue;
            }
            command.label = @"PyroWave conversion and presentation";
            const auto conversion=PWClient::colorConversion(work->frame.colorSpace,work->frame.fullRange);
            [encoder setRenderPipelineState:_presenter];
            for (unsigned p=0;p<3;++p) [encoder setFragmentTexture:slot.planes[p] atIndex:p];
            [encoder setFragmentBytes:&conversion length:sizeof(conversion) atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
            [encoder endEncoding];
#if !TARGET_OS_SIMULATOR
            const double received = progress->received;
            [drawable addPresentedHandler:^(id<MTLDrawable> presented) {
                const double time = presented.presentedTime;
                if (time >= received && time <= CACurrentMediaTime()) {
                    [self->_lock lock];
                    ++self->_presented;
                    self->_timings[SubmitToPresented].record((time - received) * 1000);
                    [self->_lock unlock];
                }
            }];
#endif
            [command presentDrawable:drawable];
            [command addCompletedHandler:^(id<MTLCommandBuffer> completed) {
                const double callbackTime = CACurrentMediaTime();
                [self->_lock lock];
                progress->rendered = completed.status == MTLCommandBufferStatusCompleted;
                progress->renderStart = completed.GPUStartTime;
                progress->renderEnd = completed.GPUEndTime;
                progress->callbackTime = callbackTime;
                if (!progress->rendered) ++self->_presentFailed;
                if (progress->completion.completePresentation())
                    [self finishFrameLocked:progress slot:index];
                [self->_lock unlock];
                if (!progress->rendered) [self failSession];
            }];
            progress->renderCommitted = CACurrentMediaTime();
            [command commit];
        }
    }
}

// Called with _lock held, once both decode and presentation have resolved.
// Abandoning presentation still waits for the submitted decode before slot reuse.
- (void)finishFrameLocked:(const std::shared_ptr<FrameProgress>&)progress slot:(size_t)index {
    if (progress->decoded && progress->rendered) {
        ++_completed;
        _timings[SubmitToWorker].record((progress->workerStart - progress->received) * 1000);
        _timings[CopyCpu].record(progress->copyMs);
        _timings[PrepareCpu].record(progress->prepareMs);
        _timings[DrawableWait].record(progress->drawableWaitMs);
        if (progress->enqueueTimeUs && progress->deliveryTimeUs >= progress->enqueueTimeUs)
            _timings[InputQueue].record((progress->deliveryTimeUs - progress->enqueueTimeUs) / 1000.0);
        const double start = progress->renderStart, end = progress->renderEnd;
        if (start > 0 && progress->received <= start && start < end && end <= progress->callbackTime) {
            _timings[ClientReady].record((end - progress->received) * 1000);
            _timings[ColorGpu].record((end - start) * 1000);
            if (start >= progress->renderCommitted)
                _timings[RenderQueue].record((start - progress->renderCommitted) * 1000);
            _timings[CallbackDelay].record((progress->callbackTime - end) * 1000);
            if (progress->decodeEnd > 0 && progress->decodeEnd <= end)
                _timings[DecodeAndColorGpu].record(
                    (progress->decodeEnd - progress->decodeStart + end - start) * 1000);
        }
        _lastCompletedFrame = @{
            @"frame_number":@(progress->frameNumber), @"rtp_timestamp":@(progress->rtpTimestamp),
            @"receive_time_us":@(progress->receiveTimeUs), @"enqueue_time_us":@(progress->enqueueTimeUs),
            @"delivery_time_us":@(progress->deliveryTimeUs),
            @"renderer_submit_seconds":@(progress->received),
            @"decode_commit_seconds":@(progress->decodeCommitted),
            @"decode_gpu_start_seconds":@(progress->decodeStart),
            @"decode_gpu_end_seconds":@(progress->decodeEnd),
            @"render_commit_seconds":@(progress->renderCommitted),
            @"render_gpu_start_seconds":@(progress->renderStart),
            @"render_gpu_end_seconds":@(progress->renderEnd)};
        if (!_shown && !_mailbox.stopped()) {
            _shown = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_lock lock]; BOOL active=!self->_mailbox.stopped(); [self->_lock unlock];
                if (active) { self->_layer.hidden=NO; [self->_callbacks videoContentShown]; }
            });
        }
    }
    _mailbox.complete(index);
    [self schedulePumpLocked];
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
    std::array<std::vector<double>,TimingCount> samples;
    for (size_t i=0; i<samples.size(); ++i) samples[i]=_timings[i].snapshot();
    NSMutableDictionary* result=[@{
        @"completed_frames":@(_completed),
        @"decoded_frames":@(_decoded),
        @"presented_frames":@(_presented),
        @"presentation_timing_available":@(!TARGET_OS_SIMULATOR),
        @"snapshot_time_seconds":@(CACurrentMediaTime()),
        @"parser_rejected":@(_parserRejected),
        @"decode_failed":@(_decodeFailed),
        @"present_failed":@(_presentFailed),
        @"profile_rejected":@(_profileRejected),
        @"pending_replacements":@(_mailbox.pendingReplacements),
        @"drawable_dropped":@(_drawableDropped),
        @"processing_slots":@(_mailbox.inFlight()),
        @"gpu_in_flight":@(_mailbox.inFlight()),
        @"pending_frames":@(_mailbox.pending()?1:0),
        @"last_completed_frame":_lastCompletedFrame ?: NSNull.null,
        @"auto_qualified":@NO,
        @"decoder_backend":@(pw_decoder_backend_name(_runtime ? _runtime->device : nullptr))
    } mutableCopy];
    [_lock unlock];
    // Sorting a diagnostic snapshot must not block arriving frames or GPU
    // completion handlers on the submission lock.
    for (size_t i=0; i<samples.size(); ++i)
        result[@(TimingKeys[i])]=distribution(std::move(samples[i]));
    return result;
}
@end

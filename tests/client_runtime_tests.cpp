// SPDX-License-Identifier: MIT
#include "bitstream_identity.h"
#include "latest_frame_queue.hpp"
#include "frame_completion.hpp"
#include "color_conversion.hpp"
#include "pyrowave_profiles.h"
#include <cmath>
#include <iostream>
#include <memory>
#include <stdexcept>
static unsigned checks;
static void require(bool success) { ++checks; if(!success) throw std::runtime_error("client runtime check failed"); }
static bool close(float a,float b) { return std::abs(a-b)<.0001f; }
int main() {
    require(pw_bitstream_matches_sdp("v=0\r\na=x-ss-pyrowave.bitstream:186f0393\r\na=rtpmap:99 PYROWAVE/90000\r\n"));
    require(pw_bitstream_matches_sdp("a=x-ss-pyrowave.bitstream:186f0393"));
    for(const char* s:std::array<const char*,8>{nullptr,"", "a=x-ss-pyrowave.bitstream:186f0394\n", "a=x-ss-pyrowave.bitstream:186f0393dead\n",
        "garbagea=x-ss-pyrowave.bitstream:186f0393\n", "a=x-ss-pyrowave.bitstream:186f0393-other\n",
        "a=x-ss-pyrowave.bitstream:186f0393\na=x-ss-pyrowave.bitstream:186f0393\n",
        "a=x-ss-pyrowave.bitstream:186f0393\na=x-ss-pyrowave.bitstream:bad\n"}) require(!pw_bitstream_matches_sdp(s));
    PWClient::LatestFrameQueue<int> queue;
    require(queue.submit(1)); auto first=queue.take(); require(first && first->frame==1);
    require(queue.submit(2)); auto second=queue.take(); require(second && second->frame==2 && first->slot!=second->slot);
    require(queue.inFlight()==2); require(queue.submit(3)); require(!queue.take());
    require(queue.submit(4)); require(queue.submit(5)); require(queue.pendingReplacements==2);
    require(queue.complete(first->slot)); auto newest=queue.take(); require(newest && newest->frame==5);
    require(!queue.pending() && queue.inFlight()==2); require(!queue.complete(10));
    require(queue.submit(6)); queue.stop(); require(!queue.pending() && !queue.take() && !queue.submit(7));
    require(queue.inFlight()==2); require(queue.complete(second->slot)); require(queue.complete(newest->slot));
    require(queue.inFlight()==0); require(!queue.complete(newest->slot));
    // Sustained producer overload remains bounded and chooses the newest frame.
    PWClient::LatestFrameQueue<int> stress;
    stress.submit(0); auto a=stress.take(); stress.submit(1); auto b=stress.take();
    for(int i=2;i<100002;++i) require(stress.submit(i) && stress.inFlight()==2 && !stress.take());
    require(stress.pendingReplacements==99999); require(stress.complete(a->slot));
    require(stress.take()->frame==100001); require(stress.complete(b->slot));
    std::cout<<"Overload check: 100000 extra frames, 2 occupied slots + 1 pending maximum; "
                "next frame 100001 (newest), 99999 pending replacements\n";
    // Stopping releases pending ownership, while work already taken retains
    // its payload until the GPU owner releases it after completion.
    PWClient::LatestFrameQueue<std::shared_ptr<int>> lifetime;
    auto payload=std::make_shared<int>(42); std::weak_ptr<int> observed=payload;
    require(lifetime.submit(std::move(payload))); auto retained=lifetime.take();
    require(retained && !observed.expired());
    auto pendingPayload=std::make_shared<int>(43); std::weak_ptr<int> pendingObserved=pendingPayload;
    require(lifetime.submit(std::move(pendingPayload)));
    require(lifetime.submit(std::make_shared<int>(44)) && pendingObserved.expired());
    lifetime.stop(); require(!observed.expired() && !lifetime.pending());
    require(lifetime.complete(retained->slot)); retained.reset(); require(observed.expired());
    // A drawable timeout or stop can resolve presentation before the GPU
    // finishes decoding. Its slot must remain occupied until both callbacks.
    for (bool decodeFirst : {false, true}) {
        PWClient::FrameCompletion completion;
        PWClient::LatestFrameQueue<int> split;
        split.submit(1); auto decoding = split.take();
        split.submit(2); auto rendering = split.take();
        split.submit(3);
        bool released = decodeFirst ? completion.completeDecode() : completion.completePresentation();
        require(!released && split.inFlight() == 2 && !split.take());
        require(!(decodeFirst ? completion.completeDecode() : completion.completePresentation()));
        released = decodeFirst ? completion.completePresentation() : completion.completeDecode();
        require(released);
        require(split.complete(decoding->slot));
        require(!completion.completeDecode() && !completion.completePresentation());
        auto successor = split.take();
        require(successor && successor->frame == 3 && split.inFlight() == 2);
        require(split.complete(rendering->slot));
        require(split.complete(successor->slot));
    }
    // On stop, abandon presentation and wait for the outstanding decode.
    PWClient::FrameCompletion stoppedCompletion;
    PWClient::LatestFrameQueue<int> stopping;
    stopping.submit(1); auto stoppedWork = stopping.take();
    stopping.submit(2); stopping.stop();
    require(!stoppedCompletion.completePresentation());
    require(stopping.inFlight() == 1 && !stopping.pending() && !stopping.take());
    require(stoppedCompletion.completeDecode() && stopping.complete(stoppedWork->slot));
    require(stopping.inFlight() == 0);
    for(int space:{0,1}) for(bool full:{false,true}) {
        auto conversion=PWClient::colorConversion(space,full);
        const float black=(full?0.f:16.f)/255.f, white=(full?255.f:235.f)/255.f, chroma=128.f/255.f;
        for(const float* row:{conversion.red,conversion.green,conversion.blue}) {
            auto rgb=[&](float y) { return row[0]*(y-conversion.range[0])*conversion.range[2]+(row[1]+row[2])*(chroma-conversion.range[1])*conversion.range[3]; };
            require(close(rgb(black),0)); require(close(rgb(white),1));
        }
        require(close(conversion.red[2],space==1?1.5748f:1.402f));
        require(close(conversion.blue[1],space==1?1.8556f:1.772f));
    }
    for (bool full:{false,true}) {
        auto c=PWClient::colorConversion(2,full);
        require(close(c.red[2],1.4746f) && close(c.blue[1],1.8814f));
    }
    const int formats[]={PW_FORMAT_420_8,PW_FORMAT_444_8,PW_FORMAT_420_10,PW_FORMAT_444_10};
    const int modes[]={PW_SERVER_420_8,PW_SERVER_444_8,PW_SERVER_420_10,PW_SERVER_444_10};
    for (int i=0;i<4;++i) {
        require(pw_select_profile(formats[i],modes[i]|PW_SERVER_420_8)==formats[i]);
        require(pw_profile_valid(formats[i]));
        for (int j=0;j<4;++j) if (j!=i)
            require(pw_select_profile(formats[i],modes[j]|(i==0?0:PW_SERVER_420_8))==0);
    }
    require(pw_select_profile(PW_FORMAT_MASK,0)==0);
    require(pw_select_profile(PW_FORMAT_MASK,0x07800000)==PW_FORMAT_444_10);
    require(!pw_profile_valid(PW_FORMAT_MASK));
    std::cout<<"Profile check: 4 matching profiles accepted, 12 mismatches refused; no unrequested downgrade\n";
    bool rejected=false; try { PWClient::colorConversion(3,false); } catch(const std::invalid_argument&) { rejected=true; }
    require(rejected);
    std::cout<<checks<<" client runtime checks passed (queue overload, strict identity, color conversion, profile selection; no GPU)\n";
}

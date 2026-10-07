// SPDX-License-Identifier: MIT
#include "bitstream_identity.h"
#include "latest_frame_queue.hpp"
#include "color_conversion.hpp"
#include <cmath>
#include <iostream>
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
    bool rejected=false; try { PWClient::colorConversion(2,false); } catch(const std::invalid_argument&) { rejected=true; }
    require(rejected);
    std::cout<<checks<<" client runtime checks passed (queue overload, strict identity, SDR conversion; no GPU)\n";
}

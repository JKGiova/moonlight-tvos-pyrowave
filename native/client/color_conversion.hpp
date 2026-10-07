// SPDX-License-Identifier: MIT
#pragma once
#include <stdexcept>
namespace PWClient {
// Four float4s, matching MSL without float3 alignment ambiguity. Input planes
// contain normalized 8-bit code values, including chroma center at 128/255.
struct ColorConversion { float range[4]; float red[4]; float green[4]; float blue[4]; };
inline ColorConversion colorConversion(int space, bool fullRange) {
    if (space != 0 && space != 1) throw std::invalid_argument("only BT.601/BT.709 SDR is supported");
    const float kr = space == 1 ? .2126f : .299f;
    const float kb = space == 1 ? .0722f : .114f;
    const float kg = 1-kr-kb;
    return {{fullRange?0.f:16.f/255.f,128.f/255.f,fullRange?1.f:255.f/219.f,fullRange?1.f:255.f/224.f},
            {1,0,2*(1-kr),0}, {1,-2*kb*(1-kb)/kg,-2*kr*(1-kr)/kg,0}, {1,2*(1-kb),0,0}};
}
}

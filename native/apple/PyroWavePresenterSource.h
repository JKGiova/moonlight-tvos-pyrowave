// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
namespace PWClient {
inline constexpr const char* PresenterSource = R"MSL(
#include <metal_stdlib>
using namespace metal;
struct Varying { float4 position [[position]]; float2 uv; };
struct Conversion { float4 range; float4 red; float4 green; float4 blue; };
vertex Varying pw_vertex(uint index [[vertex_id]]) {
    float2 p = index==0 ? float2(-1,-1) : index==1 ? float2(3,-1) : float2(-1,3);
    return {float4(p,0,1),float2((p.x+1)*.5,(1-p.y)*.5)};
}
fragment float4 pw_fragment(Varying v [[stage_in]], texture2d<float> y [[texture(0)]],
    texture2d<float> cb [[texture(1)]], texture2d<float> cr [[texture(2)]],
    constant Conversion& c [[buffer(0)]]) {
    constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::linear);
    float3 p=float3((y.sample(s,v.uv).r-c.range.x)*c.range.z,
        (cb.sample(s,v.uv).r-c.range.y)*c.range.w,(cr.sample(s,v.uv).r-c.range.y)*c.range.w);
    return float4(saturate(float3(dot(p,c.red.xyz),dot(p,c.green.xyz),dot(p,c.blue.xyz))),1);
}
)MSL";
}

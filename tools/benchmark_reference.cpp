// SPDX-License-Identifier: MIT
// Built in an isolated namespace when comparing a prior framing implementation.
#include "pyrowaveframing.h"

extern "C" bool benchmark_reference_parse(const uint8_t* data,size_t size,
                                          int width,int height,uint32_t* blocks) {
    static thread_local PyroWaveFraming::Frame frame;
    static thread_local std::string error;
    const bool valid=PyroWaveFraming::parse(data,size,{width,height,false},frame,error);
    *blocks=frame.blockRecords;
    return valid;
}

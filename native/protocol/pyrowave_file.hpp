// SPDX-License-Identifier: MIT
#pragma once
#include "pyrowaveframing.h"
#include <istream>
#include <ostream>
#include <stdexcept>
#include <array>
namespace PWFile {
constexpr uint32_t MaxFrameBytes = 64U * 1024U * 1024U;
inline uint32_t readWord(std::istream& in) {
    std::array<uint8_t,4> b{};
    if(!in.read(reinterpret_cast<char*>(b.data()),4)) throw std::runtime_error("truncated PyroWave file");
    return uint32_t(b[0]) | (uint32_t(b[1])<<8) | (uint32_t(b[2])<<16) | (uint32_t(b[3])<<24);
}
inline void writeWord(std::ostream& out,uint32_t word) {
    for(unsigned i=0;i<4;++i) out.put(char((word>>(8*i))&255));
    if(!out)throw std::runtime_error("cannot write PyroWave file");
}
struct Header { uint32_t width,height,fpsNumerator,fpsDenominator; bool fullRange; };
inline void writeHeader(std::ostream& out,const Header& h) {
    out.write("PYROWAVE",8);
    for(auto word:std::array<uint32_t,8>{h.width,h.height,0,0,uint32_t(h.fullRange),h.fpsNumerator,h.fpsDenominator,0})writeWord(out,word);
}
inline Header readHeader(std::istream& in) {
    std::array<char,8> magic{};
    if(!in.read(magic.data(),8)||std::string(magic.data(),8)!="PYROWAVE")throw std::runtime_error("not an upstream PyroWave offline file");
    std::array<uint32_t,8> p{};for(auto& x:p)x=readWord(in);
    if(p[0]<1||p[0]>16384||p[1]<1||p[1]>16384||p[0]%2||p[1]%2||p[2]!=0||p[3]!=0||p[4]>1||p[5]==0||p[6]==0||p[7]!=0)
        throw std::runtime_error("offline tool supports valid 8-bit 4:2:0 geometry only");
    return {p[0],p[1],p[5],p[6],p[4]!=0};
}
inline bool readFrame(std::istream& in,std::vector<uint8_t>& frame) {
    if(in.peek()==std::char_traits<char>::eof()) {
        if(in.bad())throw std::runtime_error("file read error");
        return false;
    }
    const auto length=readWord(in);
    if(length<8||length%4||length>MaxFrameBytes)throw std::runtime_error("invalid offline frame length");
    frame.resize(length);
    if(!in.read(reinterpret_cast<char*>(frame.data()),length))throw std::runtime_error("truncated offline frame payload");
    return true;
}
inline void writeFrame(std::ostream& out,const uint8_t* data,size_t size) {
    if(size<8||size%4||size>MaxFrameBytes)throw std::runtime_error("invalid encoded frame size");
    writeWord(out,uint32_t(size));out.write(reinterpret_cast<const char*>(data),std::streamsize(size));
    if(!out)throw std::runtime_error("cannot write frame payload");
}
inline void validateFrame(const std::vector<uint8_t>& payload,const Header& h,PyroWaveFraming::Frame& parsed) {
    std::string error;
    if(!PyroWaveFraming::parse(payload.data(),payload.size(),{int(h.width),int(h.height),false},parsed,error))throw std::runtime_error("invalid Nonary frame: "+error);
    if(parsed.partial)throw std::runtime_error("offline fixture unexpectedly partial");
}
}

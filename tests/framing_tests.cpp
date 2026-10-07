// SPDX-License-Identifier: MIT
#include "pyrowaveframing.h"
#include <iostream>
#include <limits>
#include <random>
#include <stdexcept>
using namespace PyroWaveFraming;
using Bytes = std::vector<uint8_t>;
static unsigned checks = 0;
void expect(bool result, const char* message) { ++checks; if (!result) throw std::runtime_error(message); }
void word(Bytes& b, uint32_t x) { for (int i=0;i<4;++i) b.push_back(uint8_t(x>>(8*i))); }
Bytes header(uint32_t count=1, uint32_t sequence=0) {
    Bytes b; word(b,0x80000000u|(sequence<<28)|127u|(127u<<14)); word(b,count); return b;
}
void block(Bytes& b, uint32_t index=0, uint32_t sequence=0) { word(b,(sequence<<28)|(2u<<16)); word(b,index<<8); }
Bytes wrap(const Bytes& b) { Bytes out; word(out,1);word(out,uint32_t(b.size()));out.insert(out.end(),b.begin(),b.end());return out; }
int main() try {
    Frame frame;std::string error;StreamGeometry geometry{128,128,false};
    auto parseBytes=[&](const Bytes& b){return parse(b.data(),b.size(),geometry,frame,error);};
    auto valid=header();block(valid);
    expect(parseBytes(valid),"valid records rejected");expect(frame.blockRecords==1,"block count");
    expect(parseBytes(wrap(valid)),"valid length-prefixed frame rejected");
    for(size_t n=0;n<valid.size();++n) { Bytes b(valid.begin(),valid.begin()+n);expect(!parseBytes(b),"truncated records accepted"); }
    auto prefixed=wrap(valid);
    for(size_t n=0;n<prefixed.size();++n) { Bytes b(prefixed.begin(),prefixed.begin()+n);expect(!parseBytes(b),"truncated lengths accepted"); }
    auto bad=header(2);block(bad);block(bad);expect(!parseBytes(bad),"duplicate record accepted");expect(!parseBytes(wrap(bad)),"duplicate prefixed block accepted");
    bad=header();block(bad,0,1);expect(!parseBytes(bad),"mixed record sequence accepted");expect(!parseBytes(wrap(bad)),"mixed prefixed sequence accepted");
    bad.clear();block(bad);auto h=header();bad.insert(bad.end(),h.begin(),h.end());expect(!parseBytes(wrap(bad)),"block before header accepted");
    bad=header();auto second=header();bad.insert(bad.end(),second.begin(),second.end());block(bad);expect(!parseBytes(wrap(bad)),"duplicate sequence header accepted");
    bad=header();block(bad,maxBlockCount(geometry));expect(!parseBytes(bad),"out-of-range block accepted");
    bad=header();word(bad,1u<<16);word(bad,0);expect(!parseBytes(bad),"short record accepted");
    bad=valid;word(bad,k_PaddingMagic);word(bad,1);word(bad,0);expect(parseBytes(bad),"valid padding rejected");expect(frame.paddingBytes==12,"padding byte count");
    bad=valid;word(bad,k_PaddingMagic);word(bad,0xffffffff);expect(!parseBytes(bad),"padding overflow accepted");
    bad.clear();word(bad,k_PaddingMagic);word(bad,0);bad.insert(bad.end(),valid.begin(),valid.end());expect(!parseBytes(bad),"leading padding accepted");
    expect(!parse(valid.data(),valid.size(),StreamGeometry{-1,128,false},frame,error),"negative geometry accepted");
    expect(!parse(valid.data(),valid.size(),StreamGeometry{16385,128,true},frame,error),"oversized geometry accepted");
    expect(!parse(valid.data(),valid.size(),StreamGeometry{127,128,false},frame,error),"odd 420 geometry accepted");
    expect(!parse(valid.data(),valid.size(),std::vector<Segment>{{0,std::numeric_limits<size_t>::max(),false}},geometry,frame,error),"segment overflow accepted");
    expect(!parse(valid.data(),valid.size(),std::vector<Segment>{{1,valid.size(),false}},geometry,frame,error),"map gap accepted");
    expect(!parse(valid.data(),valid.size(),std::vector<Segment>{{0,valid.size(),true}},geometry,frame,error),"lost header accepted");
    expect(!parse(valid.data(),valid.size(),{},1,geometry,frame,error),"invalid critical count accepted");
    bad=header(2);block(bad);block(bad,coarseBlockCount(geometry));
    expect(parse(bad.data(),bad.size(),{{0,16,false,true},{16,8,true,true}},1,geometry,frame,error),"recoverable detail loss rejected");
    expect(frame.partial&&frame.coarseLevelIntact&&frame.blockRecords==1,"detail loss metadata");
    expect(!parse(wrap(bad).data(),wrap(bad).size(),{{0,32,true,true}},geometry,frame,error),"prefixed loss accepted");
    bad=header();word(bad,(2u<<16)|1u);word(bad,0);expect(!parseBytes(bad),"missing block control codes accepted");
    bad=header();word(bad,(3u<<16)|1u);word(bad,0);word(bad,0x00ffffff);expect(!parseBytes(bad),"truncated magnitude planes accepted");
    bad=header();word(bad,(3u<<16)|1u);word(bad,0);word(bad,0xff000001);expect(!parseBytes(bad),"truncated sign plane accepted");
    bad=header();word(bad,(4u<<16)|1u);word(bad,0);word(bad,0x01000001);word(bad,0);expect(parseBytes(bad),"valid nonzero coefficient payload rejected");
    bad=header();word(bad,2u<<16);word(bad,255);expect(!parseBytes(bad),"invalid quantization exponent accepted");
    expect(parseBytes(valid)&&error.empty()&&!frame.partial,"state not reset after failure/loss");
    std::mt19937 rng(73);
    for(unsigned i=0;i<10000;++i){Bytes b((rng()%128)*4);for(auto& x:b)x=uint8_t(rng());if(parseBytes(b))for(auto span:frame.spans)expect(span.offset<=b.size()&&span.size<=b.size()-span.offset,"span outside input");}
    std::cout<<checks<<" framing checks and 10000 random malformed frames passed\n";
    return 0;
} catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}

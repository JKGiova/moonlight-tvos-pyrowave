// SPDX-License-Identifier: MIT
#include "dequant_fixture.hpp"
#include <iostream>
#include <random>
int main() try {
    unsigned mutations=0, accepted=0;
    std::mt19937 random(1860393);
    for (unsigned seed=0;seed<8;++seed) {
        PWTest::DequantFixture fixture;PWTest::makeFixture(fixture,seed);
        PyroWave::BitstreamParser parser;PWTest::parseFixture(fixture,parser);
        const auto& offsets=parser.dequant_offsets();
        for (unsigned i=0;i<3;++i) PWTest::require(offsets.at(size_t(fixture.blockOffset)+i)!=UINT32_MAX,"coded block missing");
        PWTest::require(offsets.at(size_t(fixture.blockOffset)+3)==UINT32_MAX,"missing block became coded");
        for (unsigned y=32;y<64;++y) for (unsigned x=32;x<64;++x)
            PWTest::require(fixture.expected[y*64+x]==0,"missing block reference");
        // Mutating valid records reaches control/magnitude/sign parsing much
        // more often than random bytes with an invalid sequence header.
        PyroWaveFraming::Frame frame;
        for (unsigned trial=0;trial<1250;++trial) {
            auto bytes=fixture.packet;
            if (trial%3==0) bytes.resize((random()%(bytes.size()/4))*4);
            else for (unsigned edit=0;edit<1+trial%4;++edit)
                bytes[random()%bytes.size()]^=uint8_t(1u<<(random()%8));
            std::string error;
            ++mutations;
            if (!PyroWaveFraming::parse(bytes.data(),bytes.size(),{128,128,false},frame,error)) continue;
            ++accepted;
            parser.clear();
            for (auto span:frame.spans) {
                PWTest::require(span.offset<=bytes.size() && span.size<=bytes.size()-span.offset,"mutated span bounds");
                PWTest::require(parser.push_packet(bytes.data()+span.offset,span.size),"accepted mutation rejected by pinned parser");
            }
            PWTest::require(uint32_t(parser.get_decoded_blocks())==frame.blockRecords,"mutation block count disagreement");
            PWTest::require(parser.decode_is_ready(false),"accepted complete mutation is not ready");
        }
    }
    std::cout<<"8 synthetic dequant fixtures and "<<mutations<<" valid-record mutations passed; "
             <<accepted<<" accepted mutations also checked by the pinned CPU parser (no GPU)\n";
    return 0;
} catch(const std::exception& e) {std::cerr<<e.what()<<'\n';return 1;}

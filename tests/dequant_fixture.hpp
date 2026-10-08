// SPDX-License-Identifier: MIT
// Synthetic coefficient records, not GPU-encoded video or a performance test.
#pragma once
#include "pyrowave_bitstream.hpp"
#include "pyrowaveframing.h"
#include <array>
#include <cmath>
#include <cstring>
#include <stdexcept>
#include <vector>

namespace PWTest {
struct DequantFixture {
    PyroWave::BlockLayout layout;
    std::vector<uint8_t> packet;
    std::array<float,64*64> expected{};
    int blockOffset=0;
};
inline void require(bool value,const char* reason) {
    if (!value) throw std::runtime_error(reason);
}
inline std::vector<uint8_t> coefficientBlock(unsigned seed,unsigned blockIndex,
                                            std::array<float,64*64>& expected,unsigned position) {
    constexpr uint16_t ballots[]={0,1,0x8000,0x8421,0xffff,0x5555,0xaaaa,0xfffe};
    constexpr uint8_t quantCodes[]={0,7,60,103,135,159,192,199};
    const uint16_t ballot=ballots[seed%8];
    const uint8_t quantCode=quantCodes[seed%8];
    std::vector<uint8_t> controls,scales,planes,signs;
    size_t signCount=0;
    for (unsigned tile=0;tile<16;++tile) {
        if (!(ballot&(1u<<tile))) continue;
        const unsigned qBits=(seed%3==0) ? 15 : (seed+tile)%5;
        const unsigned scale=(tile*3+seed)%16;
        uint16_t control=0;
        for (unsigned lane=0;lane<8;++lane) control|=uint16_t((lane+tile)%4)<<(lane*2);
        controls.push_back(uint8_t(control));controls.push_back(uint8_t(control>>8));
        scales.push_back(uint8_t(qBits|(scale<<4)));
        for (unsigned lane=0;lane<8;++lane) {
            const unsigned bits=qBits+((lane+tile)%4);
            std::array<unsigned,8> magnitudes{};
            for (unsigned coefficient=0;coefficient<8;++coefficient) {
                const unsigned ordinal=tile*64+lane*8+coefficient;
                unsigned magnitude=(ordinal*83+seed*157+17)&((1u<<bits)-1);
                if ((ordinal+seed)%7==0) magnitude=0;
                magnitudes[coefficient]=magnitude;
                const bool negative=(ordinal*3+seed)%5<2;
                if (magnitude) {
                    if (signCount%8==0) signs.push_back(0);
                    signs.back()|=uint8_t(negative)<<(signCount%8);++signCount;
                }
                const unsigned x=(position%2)*32+(tile%4)*8+(lane/4)*4+coefficient/2;
                const unsigned y=(position/2)*32+(tile/4)*8+(lane%4)*2+coefficient%2;
                // Reference geometry and scale are derived directly from the wire
                // format, independent of the Metal scan and matrix implementation.
                const float inverseQuant=std::ldexp(float(8+(quantCode&7)),1-int(quantCode>>3));
                expected[y*64+x]=magnitude ? (float(magnitude)+.5f)*(inverseQuant*(float(scale)/8+.25f))*(negative?-1:1) : 0;
            }
            for (int bit=int(bits)-1;bit>=0;--bit) {
                uint8_t plane=0;
                for (unsigned coefficient=0;coefficient<8;++coefficient)
                    plane|=uint8_t((magnitudes[coefficient]>>bit)&1u)<<coefficient;
                planes.push_back(plane);
            }
        }
    }
    std::vector<uint8_t> bytes(8);
    for (auto* part:{&controls,&scales,&planes,&signs}) bytes.insert(bytes.end(),part->begin(),part->end());
    bytes.resize((bytes.size()+3)&~size_t(3),0);
    PyroWave::BitstreamHeader header{};
    header.ballot=ballot;header.payload_words=uint16_t(bytes.size()/4);
    header.sequence=3;header.quant_code=quantCode;header.block_index=blockIndex;
    std::memcpy(bytes.data(),&header,sizeof(header));
    return bytes;
}
inline void makeFixture(DequantFixture& fixture,unsigned seed) {
    require(fixture.layout.init(128,128,PyroWave::ChromaSubsampling::Chroma420),"fixture layout");
    fixture.blockOffset=fixture.layout.block_meta[0][0][1].block_offset_32x32;
    fixture.expected.fill(0);
    std::vector<PyroWave::BitstreamPacket> metadata(size_t(fixture.layout.block_count_32x32));
    std::vector<uint32_t> raw;
    for (unsigned position=0;position<3;++position) {
        const auto index=unsigned(fixture.blockOffset)+position;
        auto record=coefficientBlock(seed+position,index,fixture.expected,position);
        metadata[index]={uint32_t(raw.size()),uint32_t(record.size()/4)};
        const size_t offset=raw.size();raw.resize(offset+record.size()/4);
        std::memcpy(raw.data()+offset,record.data(),record.size());
    }
    fixture.packet.resize(65536);
    PyroWave::Packet packet{};
    require(PyroWave::packetize(fixture.layout,&packet,fixture.packet.size(),fixture.packet.data(),fixture.packet.size(),metadata.data(),raw.data())==1,"fixture packetization");
    if (packet.offset) std::memmove(fixture.packet.data(),fixture.packet.data()+packet.offset,packet.size);
    fixture.packet.resize(packet.size);
}
inline void parseFixture(const DequantFixture& fixture,PyroWave::BitstreamParser& parser) {
    PyroWaveFraming::Frame frame;std::string error;
    if (!PyroWaveFraming::parse(fixture.packet.data(),fixture.packet.size(),{128,128,false},frame,error))
        throw std::runtime_error(error);
    parser.init(&fixture.layout);
    for (auto span:frame.spans) require(parser.push_packet(fixture.packet.data()+span.offset,span.size),"fixture rejected by pinned parser");
    require(parser.decode_is_ready(false)&&parser.get_decoded_blocks()==3,"fixture completeness");
}
}

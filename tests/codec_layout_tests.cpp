// SPDX-License-Identifier: MIT
// Tests the real pinned PyroWave CPU layout/packetizer against the Nonary adapter.
#include "pyrowave_bitstream.hpp"
#include "pyrowaveframing.h"
#include <cstring>
#include <iostream>
#include <stdexcept>
static void require(bool value,const char* text){if(!value)throw std::runtime_error(text);}
int main() try {
    unsigned profiles=0;
    for(auto chroma:{PyroWave::ChromaSubsampling::Chroma420,PyroWave::ChromaSubsampling::Chroma444}) {
        for(auto dims: {std::pair<int,int>{128,128},{320,180},{1280,720},{1920,1080},{3840,2160},{3842,2162}}) {
            PyroWave::BlockLayout layout;require(layout.init(dims.first,dims.second,chroma),"layout initialization");
            PyroWaveFraming::StreamGeometry geometry{dims.first,dims.second,chroma==PyroWave::ChromaSubsampling::Chroma444};
            require(PyroWaveFraming::maxBlockCount(geometry)==uint32_t(layout.block_count_32x32),"Nonary bounds disagree with real codec layout");
            require(PyroWaveFraming::coarseBlockCount(geometry)==size_t(layout.block_meta[2][4][3].block_offset_32x32 + layout.block_meta[2][4][3].block_count_32x32),"coarse bounds disagree with codec");
            // Controlled zero-coefficient record to exercise CPU packetization, not a GPU encoding claim.
            std::vector<PyroWave::BitstreamPacket> metadata(size_t(layout.block_count_32x32));
            metadata[0]={0,2};std::vector<uint32_t> raw(2,0);PyroWave::BitstreamHeader block{};
            block.payload_words=2;block.sequence=3;block.block_index=0;std::memcpy(raw.data(),&block,sizeof(block));
            std::vector<uint8_t> bytes(32);PyroWave::Packet packet{};
            require(PyroWave::compute_num_packets(layout,metadata.data(),1024)==1,"packet count");
            require(PyroWave::packetize(layout,&packet,1024,bytes.data(),bytes.size(),metadata.data(),raw.data())==1,"packetization");
            PyroWaveFraming::Frame frame;std::string error;
            require(PyroWaveFraming::parse(bytes.data()+packet.offset,packet.size,geometry,frame,error),"Nonary adapter rejects upstream packetizer");
            PyroWave::BitstreamParser parser;parser.init(&layout);
            for(auto span:frame.spans)require(parser.push_packet(bytes.data()+packet.offset+span.offset,span.size),"real codec CPU parser rejects adapter span");
            require(parser.get_decoded_blocks()==1&&parser.get_total_blocks_in_sequence()==1&&parser.decode_is_ready(false),"real codec readiness failed");
            parser.clear();require(!parser.decode_is_ready(false),"clear failed");++profiles;
        }
    }
    std::cout<<profiles<<" real PyroWave CPU layout/packetizer/parser interoperability profiles passed (no GPU)\n";return 0;
} catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}

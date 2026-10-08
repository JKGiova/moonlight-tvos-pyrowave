// SPDX-License-Identifier: MIT
#include "dequant_fixture.hpp"
#include <iostream>
int main() try {
    for (unsigned seed=0;seed<8;++seed) {
        PWTest::DequantFixture fixture;PWTest::makeFixture(fixture,seed);
        PyroWave::BitstreamParser parser;PWTest::parseFixture(fixture,parser);
        const auto& offsets=parser.dequant_offsets();
        for (unsigned i=0;i<3;++i) PWTest::require(offsets.at(size_t(fixture.blockOffset)+i)!=UINT32_MAX,"coded block missing");
        PWTest::require(offsets.at(size_t(fixture.blockOffset)+3)==UINT32_MAX,"missing block became coded");
        for (unsigned y=32;y<64;++y) for (unsigned x=32;x<64;++x)
            PWTest::require(fixture.expected[y*64+x]==0,"missing block reference");
    }
    std::cout<<"8 synthetic dequant fixtures accepted by framing and pinned parser (no GPU)\n";
    return 0;
} catch(const std::exception& e) {std::cerr<<e.what()<<'\n';return 1;}

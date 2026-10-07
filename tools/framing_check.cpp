// SPDX-License-Identifier: MIT
#include "pyrowave_file.hpp"
#include <fstream>
#include <iostream>
int main(int argc,char** argv) try {
    if(argc!=2)throw std::runtime_error("Usage: framing-check <output.pyrowave>");
    std::ifstream input(argv[1],std::ios::binary);if(!input)throw std::runtime_error("cannot open input file");
    const auto header=PWFile::readHeader(input);
    std::vector<uint8_t> payload;PyroWaveFraming::Frame parsed;uint64_t count=0;
    while(PWFile::readFrame(input,payload)){PWFile::validateFrame(payload,header,parsed);++count;}
    if(count==0)throw std::runtime_error("no encoded frames");
    std::cout<<"{\"frames\":"<<count<<",\"width\":"<<header.width<<",\"height\":"<<header.height
             <<",\"fps_numerator\":"<<header.fpsNumerator<<",\"fps_denominator\":"<<header.fpsDenominator
             <<",\"nonary_framing_validated\":true,\"gpu_decode_tested\":false}\n";
    return 0;
} catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}

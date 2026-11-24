// SPDX-License-Identifier: MIT
#pragma once
#include <stdint.h>
#define PW_FORMAT_420_8  0x010000
#define PW_FORMAT_444_8  0x020000
#define PW_FORMAT_420_10 0x040000
#define PW_FORMAT_444_10 0x080000
#define PW_FORMAT_MASK  0x0F0000
#define PW_SERVER_420_8  0x00800000
#define PW_SERVER_444_8  0x01000000
#define PW_SERVER_420_10 0x02000000
#define PW_SERVER_444_10 0x04000000
// Callers decide the allowed profiles; never add an unrequested lower profile.
static inline int pw_select_profile(int requested, int server) {
    if (!(server & PW_SERVER_420_8)) return 0;
    const int formats[]={PW_FORMAT_444_10,PW_FORMAT_420_10,PW_FORMAT_444_8,PW_FORMAT_420_8};
    const int modes[]={PW_SERVER_444_10,PW_SERVER_420_10,PW_SERVER_444_8,PW_SERVER_420_8};
    for (unsigned i=0;i<4;++i)
        if ((requested & formats[i]) && (server & modes[i])) return formats[i];
    return 0;
}
static inline int pw_profile_valid(int format) {
    return format==PW_FORMAT_420_8 || format==PW_FORMAT_444_8 ||
           format==PW_FORMAT_420_10 || format==PW_FORMAT_444_10;
}
static inline int pw_profile_444(int format) { return format==PW_FORMAT_444_8 || format==PW_FORMAT_444_10; }
static inline int pw_profile_10bit(int format) { return format==PW_FORMAT_420_10 || format==PW_FORMAT_444_10; }

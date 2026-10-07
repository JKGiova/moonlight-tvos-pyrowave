// SPDX-License-Identifier: MIT
#pragma once
#include <stdbool.h>
#include <string.h>

// Require one exact, line-delimited identity. Missing, duplicate and prefix
// matches must never admit an unversioned/incompatible PyroWave host.
static inline bool pw_bitstream_matches_sdp(const char* sdp) {
    static const char key[] = "a=x-ss-pyrowave.bitstream:";
    bool matched = false;
    unsigned count = 0;
    if (!sdp) return false;
    while (*sdp) {
        const char* end = strchr(sdp, '\n');
        size_t length = end ? (size_t)(end - sdp) : strlen(sdp);
        if (length && sdp[length - 1] == '\r') --length;
        if (length >= sizeof(key)-1 && memcmp(sdp, key, sizeof(key)-1) == 0) {
            ++count;
            matched = length == sizeof(key)-1+8 &&
                memcmp(sdp+sizeof(key)-1, "186f0393", 8) == 0;
        }
        if (!end) break;
        sdp = end + 1;
    }
    return count == 1 && matched;
}

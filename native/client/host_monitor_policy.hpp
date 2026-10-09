// SPDX-License-Identifier: MIT
#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>

namespace host_monitor {
constexpr double refresh_seconds = 5.0;
constexpr double response_ttl = 15.0;
constexpr double bandwidth_ttl = 30.0;
constexpr std::uint64_t probe_bytes = 32u * 1024u * 1024u;
constexpr double request_seconds = 2.0;
constexpr double calibration_seconds = 8.0;

inline bool fresh(double measured, double now, double ttl) {
    return std::isfinite(measured) && std::isfinite(now) && measured > 0 &&
           now >= measured && now - measured <= ttl;
}

class LatencyWindow {
    std::array<double, 12> values_{};
    std::size_t count_ = 0, next_ = 0;
public:
    void clear() { count_ = next_ = 0; }
    bool add(double ms) {
        if (!std::isfinite(ms) || ms < 0 || ms > 10000) return false;
        values_[next_] = ms;
        next_ = (next_ + 1) % values_.size();
        count_ = std::min(count_ + 1, values_.size());
        return true;
    }
    std::size_t count() const { return count_; }
    double variation() const {
        if (count_ < 2) return std::numeric_limits<double>::quiet_NaN();
        double mean = 0, variance = 0;
        for (std::size_t i = 0; i < count_; ++i) mean += values_[i];
        mean /= count_;
        for (std::size_t i = 0; i < count_; ++i) variance += (values_[i] - mean) * (values_[i] - mean);
        return std::sqrt(variance / count_);
    }
};

// One discarded warm-up and three complete transfers. Setup is included in
// duration: a conservative HTTPS download rate, never a UDP capacity guarantee.
class Calibration {
    unsigned completed_ = 0;
    bool failed_ = false;
    double slowest_ = std::numeric_limits<double>::infinity();
public:
    bool accept(std::uint64_t bytes, double seconds, double elapsed) {
        if (failed_ || completed_ >= 4 || bytes != probe_bytes ||
            !std::isfinite(seconds) || seconds <= 0 || seconds > request_seconds ||
            !std::isfinite(elapsed) || elapsed < seconds || elapsed > calibration_seconds) {
            failed_ = true;
            return false;
        }
        if (completed_++ > 0) slowest_ = std::min(slowest_, bytes * 8.0 / seconds / 1000000.0);
        return true;
    }
    unsigned completed() const { return completed_; }
    bool ready() const { return !failed_ && completed_ == 4; }
    double mbps() const { return ready() ? slowest_ : std::numeric_limits<double>::quiet_NaN(); }
};

inline std::uint16_t checksum(const std::uint8_t* data, std::size_t size) {
    std::uint32_t sum = 0;
    for (std::size_t i = 0; i < size; i += 2)
        sum += (std::uint16_t(data[i]) << 8) | (i + 1 < size ? data[i + 1] : 0);
    while (sum >> 16) sum = (sum & 65535) + (sum >> 16);
    return std::uint16_t(~sum);
}

// Darwin's IPv4 datagram ICMP socket includes an IP header; IPv6 omits it.
// Validate bounds, type, code, checksum, ID/sequence and a random 128-bit token.
inline bool matches_echo(const std::uint8_t* data, std::size_t size, bool ipv6,
                         const std::array<std::uint8_t, 24>& request) {
    if (!ipv6) {
        if (size < 20 || (data[0] >> 4) != 4 || data[9] != 1) return false;
        const std::size_t header = (data[0] & 15) * 4u;
        if (header < 20 || header > size) return false;
        data += header; size -= header;
    }
    return size == request.size() && data[0] == (ipv6 ? 129 : 0) && data[1] == 0 &&
           (ipv6 || checksum(data, size) == 0) &&
           std::memcmp(data + 4, request.data() + 4, request.size() - 4) == 0;
}
}

// SPDX-License-Identifier: MIT
#include "host_monitor_policy.hpp"
#include <cstdio>
#include <cstdlib>
#include <vector>

static unsigned checks;
static void check(bool value) { ++checks; if (!value) { std::fprintf(stderr, "Host monitor check %u failed\n", checks); std::abort(); } }
int main() {
    using namespace host_monitor;
    check(!fresh(0, 10, 15)); check(!fresh(20, 10, 15));
    check(fresh(10, 25, 15)); check(!fresh(10, 25.001, 15));
    check(!fresh(NAN, 10, 15)); check(!fresh(10, INFINITY, 15));
    LatencyWindow latency;
    check(std::isnan(latency.variation()));
    check(!latency.add(NAN)); check(!latency.add(INFINITY)); check(!latency.add(-1));
    check(latency.add(2)); check(std::isnan(latency.variation()));
    check(latency.add(4)); check(latency.variation() == 1);
    for (int i = 0; i < 30; ++i) check(latency.add(5));
    check(latency.count() == 12); check(latency.variation() == 0);
    latency.clear(); check(latency.count() == 0);
    Calibration valid;
    check(valid.accept(probe_bytes, 1, 1)); // warm-up must not affect minimum
    check(valid.accept(probe_bytes, .2, 1.2));
    check(valid.accept(probe_bytes, .4, 1.6));
    check(!valid.ready()); check(std::isnan(valid.mbps()));
    check(valid.accept(probe_bytes, .3, 1.9)); check(valid.ready());
    check(std::abs(valid.mbps() - probe_bytes * 8.0 / .4 / 1000000) < 1e-9);
    for (auto bytes : {probe_bytes - 1, probe_bytes + 1, std::uint64_t(0)}) {
        Calibration invalid;
        check(!invalid.accept(bytes, 1, 1)); check(!invalid.ready());
        check(!invalid.accept(probe_bytes, 1, 2)); // failure cannot be repaired by a later sample
    }
    for (double duration : {0., -1., 2.001, double(NAN), double(INFINITY)}) {
        Calibration invalid; check(!invalid.accept(probe_bytes, duration, 2));
    }
    Calibration deadline; check(!deadline.accept(probe_bytes, 1, 8.001));
    std::array<std::uint8_t, 24> request{};
    request[0] = 8; request[4] = 7; request[6] = 13;
    for (std::size_t i = 8; i < request.size(); ++i) request[i] = std::uint8_t(i * 3);
    auto reply = request; reply[0] = 0;
    auto sum = checksum(reply.data(), reply.size()); reply[2] = sum >> 8; reply[3] = std::uint8_t(sum);
    std::vector<std::uint8_t> packet(20 + reply.size()); packet[0] = 0x45; packet[9] = 1;
    std::copy(reply.begin(), reply.end(), packet.begin() + 20);
    check(matches_echo(packet.data(), packet.size(), false, request));
    for (std::size_t length = 0; length < packet.size(); ++length)
        check(!matches_echo(packet.data(), length, false, request));
    for (std::size_t i = 20; i < packet.size(); ++i) {
        packet[i] ^= 1; check(!matches_echo(packet.data(), packet.size(), false, request)); packet[i] ^= 1;
    }
    packet[0] = 0x44; check(!matches_echo(packet.data(), packet.size(), false, request));
    reply = request; reply[0] = 129;
    check(matches_echo(reply.data(), reply.size(), true, request));
    reply[8] ^= 1; check(!matches_echo(reply.data(), reply.size(), true, request));
    // All byte lengths and random packet bytes remain bounded under sanitizers.
    std::uint32_t random = 1234567;
    for (unsigned n = 0; n < 10000; ++n) {
        for (auto &byte : packet) { random ^= random << 13; random ^= random >> 17; random ^= random << 5; byte = std::uint8_t(random); }
        check(!matches_echo(packet.data(), n % packet.size(), n % 2, request));
    }
    std::printf("%u host monitor policy and ICMP validation checks passed\n", checks);
}

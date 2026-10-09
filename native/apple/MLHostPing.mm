// SPDX-License-Identifier: MIT
#import "MLHostPing.h"
#include "host_monitor_policy.hpp"
#include <dns_sd.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>

@interface MLHostPing ()
- (void)resolvedAddress:(const struct sockaddr *)address;
- (void)finish:(BOOL)replied milliseconds:(double)milliseconds;
@end

static void MLAddressResolved(DNSServiceRef, DNSServiceFlags flags, uint32_t interfaceIndex,
                              DNSServiceErrorType error, const char *,
                              const struct sockaddr *address, uint32_t, void *context) {
    if (error == kDNSServiceErr_NoError && (flags & kDNSServiceFlagsAdd) && address) {
        sockaddr_storage scoped = {};
        socklen_t length = address->sa_family == AF_INET6 ? sizeof(sockaddr_in6) : sizeof(sockaddr_in);
        if (address->sa_family != AF_INET && address->sa_family != AF_INET6) return;
        memcpy(&scoped, address, length);
        if (address->sa_family == AF_INET6 && IN6_IS_ADDR_LINKLOCAL(&((sockaddr_in6 *)&scoped)->sin6_addr))
            ((sockaddr_in6 *)&scoped)->sin6_scope_id = interfaceIndex;
        [(__bridge MLHostPing *)context resolvedAddress:(sockaddr *)&scoped];
    }
}

@implementation MLHostPing {
    DNSServiceRef _resolver;
    dispatch_source_t _reader;
    int _socket;
    BOOL _finished, _closed, _ipv6;
    struct sockaddr_storage _destination;
    std::array<uint8_t, 24> _packet;
    double _sentAt;
    void (^_completion)(BOOL, double);
    NSMutableArray<void (^)(void)> *_stopCompletions;
}
- (instancetype)init {
    if ((self = [super init])) { _socket = -1; _stopCompletions = [NSMutableArray array]; }
    return self;
}
- (void)startHost:(NSString *)host completion:(void (^)(BOOL, double))completion {
    NSAssert(NSThread.isMainThread, @"Main-thread lifecycle required");
    if (_finished || _completion) return;
    _completion = [completion copy];
    // Numeric addresses avoid DNS entirely. Bonjour resolution is asynchronous
    // and cancellable, including IPv6 scope/interface handling.
    struct addrinfo hints = {}, *addresses = nullptr;
    hints.ai_flags = AI_NUMERICHOST; hints.ai_family = AF_UNSPEC;
    if (getaddrinfo(host.UTF8String, nullptr, &hints, &addresses) == 0) {
        [self resolvedAddress:addresses->ai_addr];
        freeaddrinfo(addresses);
    } else {
        DNSServiceErrorType error = DNSServiceGetAddrInfo(&_resolver, 0, 0,
            kDNSServiceProtocol_IPv4 | kDNSServiceProtocol_IPv6, host.UTF8String,
            MLAddressResolved, (__bridge void *)self);
        if (error != kDNSServiceErr_NoError || DNSServiceSetDispatchQueue(_resolver, dispatch_get_main_queue()) != kDNSServiceErr_NoError) {
            [self finish:NO milliseconds:0]; return;
        }
    }
    __weak MLHostPing *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [weakSelf finish:NO milliseconds:0];
    });
}
- (void)resolvedAddress:(const struct sockaddr *)address {
    if (_finished || _socket != -1 || (address->sa_family != AF_INET && address->sa_family != AF_INET6)) return;
    _ipv6 = address->sa_family == AF_INET6;
    socklen_t length = _ipv6 ? sizeof(sockaddr_in6) : sizeof(sockaddr_in);
    memcpy(&_destination, address, length);
    if (_ipv6) ((sockaddr_in6 *)&_destination)->sin6_port = 0;
    else ((sockaddr_in *)&_destination)->sin_port = 0;
    int fd = socket(address->sa_family, SOCK_DGRAM, _ipv6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP);
    if (fd < 0) return; // Sandbox/platform support is optional; deadline reports unknown.
    fcntl(fd, F_SETFL, O_NONBLOCK);
    int receiveBytes = 4096;
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &receiveBytes, sizeof(receiveBytes));
    arc4random_buf(_packet.data(), _packet.size());
    _packet[0] = _ipv6 ? 128 : 8; _packet[1] = _packet[2] = _packet[3] = 0;
    if (!_ipv6) {
        uint16_t sum = host_monitor::checksum(_packet.data(), _packet.size());
        _packet[2] = uint8_t(sum >> 8); _packet[3] = uint8_t(sum);
    }
    _sentAt = NSProcessInfo.processInfo.systemUptime;
    if (sendto(fd, _packet.data(), _packet.size(), 0, (sockaddr *)&_destination, length) != (ssize_t)_packet.size()) {
        close(fd); return;
    }
    _socket = fd;
    _reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, dispatch_get_main_queue());
    __weak MLHostPing *weakSelf = self;
    dispatch_source_set_event_handler(_reader, ^{
        MLHostPing *owner = weakSelf;
        if (!owner || owner->_finished) return;
        for (unsigned i = 0; i < 16; ++i) {
            uint8_t data[256]; sockaddr_storage sender = {}; socklen_t size = sizeof(sender);
            ssize_t count = recvfrom(fd, data, sizeof(data), 0, (sockaddr *)&sender, &size);
            if (count < 0) break;
            bool same = sender.ss_family == owner->_destination.ss_family;
            if (same && owner->_ipv6)
                same = memcmp(&((sockaddr_in6 *)&sender)->sin6_addr, &((sockaddr_in6 *)&owner->_destination)->sin6_addr, 16) == 0 &&
                       ((sockaddr_in6 *)&sender)->sin6_scope_id == ((sockaddr_in6 *)&owner->_destination)->sin6_scope_id;
            else if (same)
                same = ((sockaddr_in *)&sender)->sin_addr.s_addr == ((sockaddr_in *)&owner->_destination)->sin_addr.s_addr;
            if (same && host_monitor::matches_echo(data, (size_t)count, owner->_ipv6, owner->_packet)) {
                [owner finish:YES milliseconds:(NSProcessInfo.processInfo.systemUptime - owner->_sentAt) * 1000];
                break;
            }
        }
    });
    dispatch_source_set_cancel_handler(_reader, ^{ close(fd); });
    dispatch_resume(_reader);
}
- (void)finish:(BOOL)replied milliseconds:(double)milliseconds {
    if (_finished) return;
    _finished = YES;
    if (_resolver) { DNSServiceRef resolver = _resolver; _resolver = nullptr; DNSServiceRefDeallocate(resolver); }
    void (^done)(void) = ^{
        self->_closed = YES;
        void (^callback)(BOOL, double) = self->_completion;
        self->_completion = nil;
        if (callback) callback(replied, milliseconds);
        NSArray *stops = [self->_stopCompletions copy];
        [self->_stopCompletions removeAllObjects];
        for (void (^stop)(void) in stops) stop();
    };
    if (_reader) {
        // Drain the read source and close its fd before reporting cancellation.
        int fd = _socket;
        dispatch_source_set_cancel_handler(_reader, ^{ close(fd); done(); });
        dispatch_source_cancel(_reader); _reader = nil; _socket = -1;
    } else done();
}
- (void)stopWithCompletion:(void (^)(void))completion {
    NSAssert(NSThread.isMainThread, @"Main-thread lifecycle required");
    if (_closed) { if (completion) completion(); return; }
    if (completion) [_stopCompletions addObject:[completion copy]];
    _completion = nil;
    [self finish:NO milliseconds:0];
}
@end

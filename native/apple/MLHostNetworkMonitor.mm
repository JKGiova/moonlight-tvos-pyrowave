// SPDX-License-Identifier: MIT
#import "MLHostNetworkMonitor.h"
#import "MLHostProbeSession.h"
#import "MLHostPing.h"
#import "HttpManager.h"
#import "ServerInfoResponse.h"
#import "AppListResponse.h"
#import "TemporaryHost.h"
#import <Network/Network.h>
#include "host_monitor_policy.hpp"
#include <cerrno>

@implementation MLHostNetworkSnapshot
@end

static double MLNow(void) { return NSProcessInfo.processInfo.systemUptime; }
static BOOL MLConnectionRefused(NSError *error) {
    for (unsigned i = 0; error && i < 5; ++i, error = error.userInfo[NSUnderlyingErrorKey])
        if ([error.domain isEqualToString:NSPOSIXErrorDomain] && error.code == ECONNREFUSED) return YES;
    return NO;
}

@implementation MLHostNetworkMonitor {
    TemporaryHost *_host;
    MLHostProbeSession *_session;
    MLHostPing *_ping;
    NSTimer *_timer;
    nw_path_monitor_t _pathMonitor;
    BOOL _sawPath, _stopped, _busy, _started, _supportsBandwidth, _automaticTestAttempted;
    BOOL _triedHTTP, _triedHTTPS;
    NSUInteger _routeEpoch, _addressIndex, _failures, _addressesRemaining, _respondingIndex;
    BOOL _receivedResponse;
    MLHostDashboardState _responseState;
    NSString *_responseSource, *_responseMessage;
    double _responseLatency;
    NSArray<NSString *> *_addresses;
    NSString *_address, *_latencySource, *_message, *_bandwidthStatus;
    MLHostDashboardState _state;
    host_monitor::LatencyWindow _window;
    host_monitor::Calibration _calibration;
    double _latency, _latencyAt, _bandwidth, _bandwidthAt, _lastRefresh, _lastApps, _calibrationAt;
    BOOL _calibrating;
    ServerInfoResponse *_serverInfo;
    void (^_update)(MLHostNetworkSnapshot *, ServerInfoResponse *, AppListResponse *);
}
- (instancetype)initWithHost:(TemporaryHost *)host
                       update:(void (^)(MLHostNetworkSnapshot *, ServerInfoResponse *, AppListResponse *))update {
    return [self initWithHost:host configuration:NSURLSessionConfiguration.ephemeralSessionConfiguration update:update];
}
- (instancetype)initWithHost:(TemporaryHost *)host configuration:(NSURLSessionConfiguration *)configuration
                       update:(void (^)(MLHostNetworkSnapshot *, ServerInfoResponse *, AppListResponse *))update {
    if ((self = [super init])) {
        _host = host; _update = [update copy]; _state = MLHostDashboardChecking;
        _message = @"Checking this PC…"; _bandwidthStatus = @"not measured";
        NSMutableOrderedSet *addresses = [NSMutableOrderedSet orderedSet];
        for (NSString *candidate in @[host.activeAddress ?: @"", host.localAddress ?: @"", host.address ?: @"",
                                      host.externalAddress ?: @"", host.ipv6Address ?: @""])
            if (candidate.length) [addresses addObject:candidate];
        _addresses = addresses.array;
        _address = _addresses.firstObject;
        HttpManager *authentication = [[HttpManager alloc] initWithAddress:_address ?: @"127.0.0.1"
                                                                httpsPort:host.httpsPort serverCert:host.serverCert];
        _session = [[MLHostProbeSession alloc] initWithAuthenticationDelegate:authentication
                                                              configuration:configuration];
    }
    return self;
}
- (void)start {
    if (_started || _stopped) return;
    _started = YES;
    __weak MLHostNetworkMonitor *weakSelf = self;
    _pathMonitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(_pathMonitor, dispatch_get_main_queue());
    nw_path_monitor_set_update_handler(_pathMonitor, ^(nw_path_t path) {
        MLHostNetworkMonitor *owner = weakSelf;
        if (!owner || owner->_stopped) return;
        if (!owner->_sawPath) { owner->_sawPath = YES; return; }
        [owner invalidateRoute];
    });
    nw_path_monitor_start(_pathMonitor);
    _timer = [NSTimer scheduledTimerWithTimeInterval:host_monitor::refresh_seconds repeats:YES block:^(NSTimer *timer) {
        [weakSelf refresh];
    }];
    [self refresh];
}
- (void)invalidateRoute {
    ++_routeEpoch;
    _window.clear(); _latencyAt = _bandwidthAt = 0; _supportsBandwidth = NO;
    _bandwidthStatus = @"not measured on this route";
    _state = MLHostDashboardChecking; _message = @"Network changed. Checking this PC…";
    _lastApps = 0; _serverInfo = nil;
    [_session cancelRequest];
    // In-flight results carry the old epoch and cannot refresh this route.
    [self publish:nil];
}
- (NSURLRequest *)requestForPath:(NSString *)path secure:(BOOL)secure {
    NSURLComponents *url = [NSURLComponents new];
    url.scheme = secure ? @"https" : @"http";
    NSString *name = [Utils addressPortStringToAddress:_address];
    url.host = [name containsString:@":"] ? [NSString stringWithFormat:@"[%@]", name] : name;
    url.port = @(secure ? _host.httpsPort : [Utils addressPortStringToPort:_address]);
    url.path = path;
    url.queryItems = @[[NSURLQueryItem queryItemWithName:@"uniqueid" value:@"0123456789ABCDEF"]];
    return [NSURLRequest requestWithURL:url.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                       timeoutInterval:host_monitor::request_seconds];
}
- (void)recordLatency:(double)ms source:(NSString *)source {
    if (![_latencySource isEqualToString:source]) _window.clear();
    if (_window.add(ms)) { _latency = ms; _latencyAt = MLNow(); _latencySource = source; }
}
- (void)publish:(AppListResponse *)apps {
    if (_stopped || !_update) return;
    MLHostNetworkSnapshot *snapshot = [MLHostNetworkSnapshot new];
    snapshot.state = _state; snapshot.message = _message ?: @"";
    double now = MLNow();
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (_latencyAt > 0) {
        BOOL stale = !host_monitor::fresh(_latencyAt, now, host_monitor::response_ttl);
        [parts addObject:[NSString stringWithFormat:@"%@: %.1f ms%@ · %.0f s ago", _latencySource, _latency,
                          stale ? @" (stale)" : @"", MAX(0, now - _latencyAt)]];
        if (_window.count() >= 2 && !stale)
            [parts addObject:[NSString stringWithFormat:@"Variation: %.1f ms (%zu samples)", _window.variation(), _window.count()]];
    } else [parts addObject:@"Response time: unavailable"];
    if (_bandwidthAt > 0)
        [parts addObject:[NSString stringWithFormat:@"Download: %.0f Mbps · %.0f s ago%@", _bandwidth, MAX(0, now - _bandwidthAt),
            host_monitor::fresh(_bandwidthAt, now, host_monitor::bandwidth_ttl) ? @" (HTTPS)" : @" (stale, HTTPS)"]];
    else [parts addObject:[@"Bandwidth: " stringByAppendingString:_bandwidthStatus]];
    if (_bandwidthAt > 0 && ![_bandwidthStatus isEqualToString:@"measured"])
        [parts addObject:_bandwidthStatus];
    snapshot.metrics = [parts componentsJoinedByString:@"   ·   "];
    snapshot.canTestBandwidth = _supportsBandwidth && _state == MLHostDashboardReady && !_busy;
    _update(snapshot, _serverInfo, apps);
}
- (void)refresh {
    if (_stopped) return;
    [self publish:nil];
    if (_busy || MLNow() - _lastRefresh < 1) return;
    if (!_address.length) {
        _state = MLHostDashboardUnreachable; _message = @"No saved address for this PC. Add the PC again.";
        [self publish:nil]; return;
    }
    _lastRefresh = MLNow(); _busy = YES;
    _addressesRemaining = _addresses.count;
    _receivedResponse = NO;
    _triedHTTP = _triedHTTPS = NO;
    [self requestServerInfoSecure:_host.serverCert != nil && _host.httpsPort != 0];
}
- (void)selectAddressAtIndex:(NSUInteger)index {
    if (index == _addressIndex) return;
    _addressIndex = index; _address = _addresses[index];
    _window.clear(); _latencyAt = _bandwidthAt = 0; _lastApps = 0;
    _bandwidthStatus = @"not measured on this route";
}
- (void)recordResponse:(double)milliseconds source:(NSString *)source
                 state:(MLHostDashboardState)state message:(NSString *)message {
    // Keep the strongest evidence while checking every saved address. A later
    // timeout must not turn a responding PC into an offline result.
    if (_receivedResponse && _responseState == MLHostDashboardPairRequired) return;
    _receivedResponse = YES; _respondingIndex = _addressIndex;
    _responseLatency = milliseconds; _responseSource = source;
    _responseState = state; _responseMessage = message;
}
- (void)finishUnavailableAddress {
    _serverInfo = nil; _supportsBandwidth = NO;
    if (--_addressesRemaining > 0) {
        [self selectAddressAtIndex:(_addressIndex + 1) % _addresses.count];
        _triedHTTP = _triedHTTPS = NO;
        [self requestServerInfoSecure:_host.serverCert != nil && _host.httpsPort != 0];
        return;
    }
    if (_receivedResponse) {
        _failures = 0;
        [self selectAddressAtIndex:_respondingIndex];
        _state = _responseState; _message = _responseMessage;
        [self recordLatency:_responseLatency source:_responseSource];
    } else {
        ++_failures;
        _state = _failures >= 3 ? MLHostDashboardUnreachable : MLHostDashboardChecking;
        _message = _state == MLHostDashboardUnreachable ?
            @"PC unreachable. It may be off, disconnected, or blocking probes." : @"No response yet. Checking saved routes…";
    }
    [self finishRefresh];
}
- (void)requestServerInfoSecure:(BOOL)secure {
    if (secure) _triedHTTPS = YES; else _triedHTTP = YES;
    NSUInteger epoch = _routeEpoch;
    __weak MLHostNetworkMonitor *weakSelf = self;
    [_session request:[self requestForPath:@"/serverinfo" secure:secure] maximumBytes:65536 retainBody:YES
           completion:^(MLHostProbeResult *result) {
        MLHostNetworkMonitor *owner = weakSelf;
        if (!owner || owner->_stopped) return;
        if (epoch != owner->_routeEpoch) { owner->_busy = NO; return; }
        ServerInfoResponse *info = [ServerInfoResponse new];
        if (!result.error && result.response.statusCode == 200 && result.body.length) {
            NSString *xml = [[NSString alloc] initWithData:result.body encoding:NSUTF8StringEncoding];
            // Match the existing Moonlight correction for incorrectly labelled XML.
            xml = [xml stringByReplacingOccurrencesOfString:@"UTF-16" withString:@"UTF-8"
                                                    options:NSCaseInsensitiveSearch range:NSMakeRange(0, xml.length)];
            if (xml) [info populateWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
        }
        BOOL correctHost = [[info getStringTag:TAG_UNIQUE_ID] isEqualToString:owner->_host.uuid];
        if ([info isStatusOk] && correctHost) {
            owner->_failures = 0;
            owner->_host.activeAddress = owner->_address;
            NSInteger port = 0;
            unsigned short previousPort = owner->_host.httpsPort;
            if ([info getIntTag:TAG_HTTPS_PORT value:&port] && port > 0 && port <= 65535) owner->_host.httpsPort = (unsigned short)port;
            else if (!owner->_host.httpsPort) owner->_host.httpsPort = 47984;
            if (!secure && owner->_host.serverCert && (!owner->_triedHTTPS || previousPort != owner->_host.httpsPort)) {
                // HTTPS port discovery only; this response cannot authorize apps or capacity.
                owner->_serverInfo = info;
                [owner requestServerInfoSecure:YES]; return;
            }
            [owner recordLatency:result.duration * 1000 source:secure ? @"Service response" : @"HTTP response"];
            NSInteger paired = 0, bytes = 0;
            BOOL authenticated = secure && [info getIntTag:TAG_PAIR_STATUS value:&paired] && paired == 1;
            owner->_serverInfo = info;
            owner->_state = authenticated ? MLHostDashboardReady : MLHostDashboardPairRequired;
            owner->_message = authenticated ? @"" : @"Streaming service found. Pair this PC to view its apps.";
            owner->_supportsBandwidth = authenticated && [info getIntTag:@"PyroWaveBandwidthProbeBytes" value:&bytes] &&
                                       bytes == (NSInteger)host_monitor::probe_bytes;
            if (!owner->_supportsBandwidth) owner->_bandwidthStatus = @"unavailable from this service";
            if (authenticated && MLNow() - owner->_lastApps >= 15) { [owner requestApps]; return; }
            [owner finishRefresh];
        } else if (secure && (([result.error.domain isEqualToString:NSURLErrorDomain] &&
                              (result.error.code == NSURLErrorServerCertificateUntrusted ||
                               result.error.code == NSURLErrorClientCertificateRejected)) ||
                             result.response.statusCode == 401 || result.response.statusCode == 403 || info.statusCode == 401)) {
            // Only expose pairing UI. Never use HTTP capability data for the bulk probe.
            [owner recordResponse:result.duration * 1000 source:@"Connection response"
                            state:MLHostDashboardPairRequired message:@"Pairing needs attention. Pair this PC again."];
            [owner finishUnavailableAddress];
        } else if (secure && !owner->_triedHTTP) {
            [owner requestServerInfoSecure:NO];
        } else if (result.response || MLConnectionRefused(result.error)) {
            [owner recordResponse:result.duration * 1000 source:@"Connection response"
                            state:MLHostDashboardServiceUnavailable
                          message:@"A saved address responded, but this PC's streaming service was not verified. Check Vibeshine and the saved addresses."];
            [owner finishUnavailableAddress];
        } else [owner checkReachability];
    }];
}
- (void)requestApps {
    NSUInteger epoch = _routeEpoch;
    __weak MLHostNetworkMonitor *weakSelf = self;
    [_session request:[self requestForPath:@"/applist" secure:YES] maximumBytes:2 * 1024 * 1024 retainBody:YES
           completion:^(MLHostProbeResult *result) {
        MLHostNetworkMonitor *owner = weakSelf;
        if (!owner || owner->_stopped) return;
        if (epoch != owner->_routeEpoch) { owner->_busy = NO; return; }
        AppListResponse *apps = [AppListResponse new];
        if (!result.error && result.response.statusCode == 200 && result.body.length) {
            NSString *xml = [[NSString alloc] initWithData:result.body encoding:NSUTF8StringEncoding];
            xml = [xml stringByReplacingOccurrencesOfString:@"UTF-16" withString:@"UTF-8"
                                                    options:NSCaseInsensitiveSearch range:NSMakeRange(0, xml.length)];
            if (xml) [apps populateWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
        }
        if ([apps isStatusOk] && [apps getAppList] != nil) {
            owner->_lastApps = MLNow();
            [owner publish:apps];
        } else if (result.response.statusCode == 401 || result.response.statusCode == 403 || apps.statusCode == 401 ||
                   ([result.error.domain isEqualToString:NSURLErrorDomain] &&
                    (result.error.code == NSURLErrorServerCertificateUntrusted || result.error.code == NSURLErrorClientCertificateRejected))) {
            owner->_state = MLHostDashboardPairRequired;
            owner->_message = @"Pairing needs attention. Pair this PC again.";
            owner->_supportsBandwidth = NO; owner->_serverInfo = nil;
        } else {
            owner->_message = @"Unable to refresh apps. Retrying…";
            if (owner->_host.appList.count == 0) owner->_state = MLHostDashboardServiceUnavailable;
        }
        [owner finishRefresh];
    }];
}
- (void)checkReachability {
    _serverInfo = nil; _supportsBandwidth = NO;
    NSUInteger epoch = _routeEpoch;
    _ping = [MLHostPing new];
    __weak MLHostNetworkMonitor *weakSelf = self;
    [_ping startHost:[Utils addressPortStringToAddress:_address] completion:^(BOOL replied, double milliseconds) {
        MLHostNetworkMonitor *owner = weakSelf;
        if (!owner || owner->_stopped) return;
        owner->_ping = nil;
        if (epoch != owner->_routeEpoch) { owner->_busy = NO; return; }
        if (replied) {
            [owner recordResponse:milliseconds source:@"Ping RTT" state:MLHostDashboardServiceUnavailable
                          message:@"PC is reachable. Start Vibeshine or check its firewall settings."];
        }
        [owner finishUnavailableAddress];
    }];
}
- (void)finishRefresh {
    _busy = NO;
    [self publish:nil];
    if (!_automaticTestAttempted && _supportsBandwidth && _state == MLHostDashboardReady &&
        [_serverInfo getStringTag:TAG_CURRENT_GAME].integerValue == 0) {
        _automaticTestAttempted = YES;
        [self testBandwidth];
    }
}
- (void)testBandwidth {
    if (_stopped || _busy || !_supportsBandwidth || _state != MLHostDashboardReady) return;
    // At most one four-request calibration per minute in this app process,
    // including dashboard re-entry. The server's 429 remains authoritative.
    static NSMutableDictionary<NSString *, NSNumber *> *lastTests;
    if (!lastTests) lastTests = [NSMutableDictionary dictionary];
    double previous = [lastTests[_host.uuid] doubleValue];
    if (previous > 0 && MLNow() - previous < 60) {
        _bandwidthStatus = @"retest available after 60 seconds"; [self publish:nil]; return;
    }
    lastTests[_host.uuid] = @(MLNow());
    _automaticTestAttempted = YES; _busy = YES; _calibrating = YES;
    _calibration = host_monitor::Calibration(); _calibrationAt = MLNow();
    [self requestCapacity];
}
- (void)requestCapacity {
    NSUInteger epoch = _routeEpoch;
    _bandwidthStatus = [NSString stringWithFormat:@"testing %u/4…", _calibration.completed() + 1];
    [self publish:nil];
    NSMutableURLRequest *request = [[self requestForPath:@"/pyrowave-bandwidth-probe" secure:YES] mutableCopy];
    request.timeoutInterval = MIN(host_monitor::request_seconds, host_monitor::calibration_seconds - (MLNow() - _calibrationAt));
    if (request.timeoutInterval <= 0) { _bandwidthStatus = @"test timed out"; _calibrating = NO; [self finishRefresh]; return; }
    __weak MLHostNetworkMonitor *weakSelf = self;
    [_session request:request maximumBytes:host_monitor::probe_bytes retainBody:NO completion:^(MLHostProbeResult *result) {
        MLHostNetworkMonitor *owner = weakSelf;
        if (!owner || owner->_stopped) return;
        if (epoch != owner->_routeEpoch) { owner->_busy = owner->_calibrating = NO; return; }
        if (result.response.statusCode == 429) owner->_bandwidthStatus = @"host rate limit; retry later";
        else if (result.error || result.response.statusCode != 200 ||
                 !owner->_calibration.accept(result.receivedBytes, result.duration, MLNow() - owner->_calibrationAt))
            owner->_bandwidthStatus = @"test incomplete; retry when ready";
        else if (!owner->_calibration.ready()) { [owner requestCapacity]; return; }
        else {
            owner->_bandwidth = owner->_calibration.mbps(); owner->_bandwidthAt = MLNow();
            owner->_bandwidthStatus = @"measured";
        }
        owner->_calibrating = NO;
        [owner finishRefresh];
    }];
}
- (void)stopWithCompletion:(void (^)(void))completion {
    NSAssert(NSThread.isMainThread, @"Main-thread lifecycle required");
    _stopped = YES; _update = nil;
    [_timer invalidate]; _timer = nil;
    if (_pathMonitor) { nw_path_monitor_cancel(_pathMonitor); _pathMonitor = nil; }
    MLHostPing *ping = _ping;
    [_session stopWithCompletion:^{
        if (ping) [ping stopWithCompletion:completion];
        else if (completion) completion();
    }];
    // Start cancellation now; session invalidation and fd closure both gate launch.
    [ping stopWithCompletion:nil];
}
@end

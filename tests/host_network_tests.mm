// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import "HostFixtures.h"
#import "MLHostProbeSession.h"
#import "MLHostNetworkMonitor.h"
#include <cstdio>
#include <cstdlib>

extern BOOL fixturePingReplies;
static NSString *scenario, *fixtureUUID;
static NSUInteger requests, appRequests, bulkRequests, checks;
static void check(BOOL value, const char *message) {
    ++checks; if (!value) { std::fprintf(stderr, "FAIL: %s\n", message); std::abort(); }
}
static void spin(double seconds) {
    double end = NSProcessInfo.processInfo.systemUptime + seconds;
    while (NSProcessInfo.processInfo.systemUptime < end)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}
static void until(BOOL (^condition)(void), const char *message) {
    double deadline = NSProcessInfo.processInfo.systemUptime + 5;
    while (!condition() && NSProcessInfo.processInfo.systemUptime < deadline) spin(.01);
    check(condition(), message);
}

@interface FixtureProtocol : NSURLProtocol
@property(atomic) BOOL loadingStopped;
@end
@implementation FixtureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)stopLoading { self.loadingStopped = YES; }
- (void)respondStatus:(NSInteger)status data:(NSData *)data declared:(NSNumber *)length finish:(BOOL)finish {
    if (self.loadingStopped) return;
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (length) headers[@"Content-Length"] = length.stringValue;
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:headers];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (data.length) [self.client URLProtocol:self didLoadData:data];
    if (finish) [self.client URLProtocolDidFinishLoading:self];
}
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.loadingStopped) return;
        ++requests;
        NSString *path = self.request.URL.path;
        if ([scenario isEqualToString:@"timeout"]) {
            [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
            return;
        }
        if ([path isEqualToString:@"/serverinfo"]) {
            if ([scenario isEqualToString:@"auth"]) { [self respondStatus:403 data:nil declared:@0 finish:YES]; return; }
            if ([scenario isEqualToString:@"service-down"]) { [self respondStatus:503 data:nil declared:@0 finish:YES]; return; }
            NSString *uuid = [scenario isEqualToString:@"wrong-host"] ? @"different-fixture" : fixtureUUID;
            BOOL bulk = [scenario hasPrefix:@"bulk"];
            NSString *xml = [NSString stringWithFormat:@"<root status_code=\"200\"><uniqueid>%@</uniqueid><HttpsPort>47984</HttpsPort><PairStatus>1</PairStatus><currentgame>0</currentgame>%@</root>", uuid,
                bulk ? @"<PyroWaveBandwidthProbeBytes>33554432</PyroWaveBandwidthProbeBytes>" : @""];
            NSData *data = [xml dataUsingEncoding:NSUTF8StringEncoding];
            [self respondStatus:200 data:data declared:@(data.length) finish:YES];
        } else if ([path isEqualToString:@"/applist"]) {
            ++appRequests;
            NSData *data = [@"<root status_code=\"200\"><App><AppTitle>Fixture</AppTitle><ID>1</ID></App></root>" dataUsingEncoding:NSUTF8StringEncoding];
            [self respondStatus:200 data:data declared:@(data.length) finish:YES];
        } else if ([path isEqualToString:@"/pyrowave-bandwidth-probe"]) {
            ++bulkRequests;
            if ([scenario isEqualToString:@"bulk-rate-limit"]) { [self respondStatus:429 data:nil declared:@0 finish:YES]; return; }
            [self respondStatus:200 data:nil declared:@33554432 finish:NO];
            if ([scenario isEqualToString:@"bulk-pending"]) return;
            NSData *chunk = [NSData dataWithBytesNoCopy:calloc(1, 1024 * 1024) length:1024 * 1024 freeWhenDone:YES];
            unsigned chunks = [scenario isEqualToString:@"bulk-partial"] ? 16 : 32;
            for (unsigned i = 0; i < chunks && !self.loadingStopped; ++i) [self.client URLProtocol:self didLoadData:chunk];
            [self.client URLProtocolDidFinishLoading:self];
        } else if ([path isEqualToString:@"/oversize"]) {
            [self respondStatus:200 data:nil declared:@1000 finish:YES];
        } else if ([path isEqualToString:@"/overflow"]) {
            [self respondStatus:200 data:[@"123456789" dataUsingEncoding:NSUTF8StringEncoding] declared:nil finish:YES];
        } else {
            [self respondStatus:200 data:[@"12345678" dataUsingEncoding:NSUTF8StringEncoding] declared:@8 finish:YES];
        }
    });
}
@end

static NSURLSessionConfiguration *configuration(void) {
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.protocolClasses = @[FixtureProtocol.class]; return config;
}
static TemporaryHost *host(BOOL paired) {
    TemporaryHost *value = [TemporaryHost new];
    fixtureUUID = NSUUID.UUID.UUIDString;
    value.uuid = fixtureUUID; value.activeAddress = @"127.0.0.1:47989";
    value.httpsPort = 47984; value.appList = [NSSet set];
    if (paired) value.serverCert = [@"fixture-only" dataUsingEncoding:NSUTF8StringEncoding];
    return value;
}
static void stopMonitor(MLHostNetworkMonitor *monitor) {
    __block BOOL done = NO; [monitor stopWithCompletion:^{ done = YES; }];
    until(^BOOL { return done; }, "monitor cancellation completes");
}
int main() { @autoreleasepool {
    scenario = @"normal";
    HttpManager *auth = [[HttpManager alloc] initWithAddress:@"127.0.0.1" httpsPort:0 serverCert:nil];
    for (NSString *path in @[@"/small", @"/oversize", @"/overflow"]) {
        MLHostProbeSession *session = [[MLHostProbeSession alloc] initWithAuthenticationDelegate:auth configuration:configuration()];
        __block MLHostProbeResult *result = nil;
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[@"http://127.0.0.1" stringByAppendingString:path]]];
        check([session request:request maximumBytes:8 retainBody:NO completion:^(MLHostProbeResult *value) { result = value; }], "request accepted");
        check(![session request:request maximumBytes:8 retainBody:NO completion:^(MLHostProbeResult *value) {}], "overlapping request refused");
        until(^BOOL { return result != nil; }, "bounded transport result");
        if ([path isEqualToString:@"/small"]) check(result.error == nil && result.receivedBytes == 8 && result.body == nil, "discarding transfer counts exact bytes");
        else check(result.error != nil && result.receivedBytes <= 8, "declared and chunked overflows rejected");
        __block BOOL stopped = NO; [session stopWithCompletion:^{ stopped = YES; }];
        until(^BOOL { return stopped; }, "transport invalidation completes");
        check(![session request:request maximumBytes:8 retainBody:YES completion:^(MLHostProbeResult *value) {}], "stopped transport cannot restart");
    }
    for (NSString *mode in @[@"normal", @"service-down", @"wrong-host", @"auth", @"unpaired", @"bulk-success", @"bulk-partial", @"bulk-rate-limit", @"bulk-pending"]) {
        scenario = mode; requests = appRequests = bulkRequests = 0;
        __block MLHostNetworkSnapshot *latest = nil;
        __block NSUInteger callbacks = 0;
        TemporaryHost *target = host(![mode isEqualToString:@"unpaired"]);
        if ([mode isEqualToString:@"normal"]) target.activeAddress = @"[::1]:47989";
        MLHostNetworkMonitor *monitor = [[MLHostNetworkMonitor alloc] initWithHost:target configuration:configuration()
            update:^(MLHostNetworkSnapshot *snapshot, ServerInfoResponse *info, AppListResponse *apps) { latest = snapshot; ++callbacks; }];
        [monitor refresh];
        if ([mode isEqualToString:@"bulk-pending"]) {
            until(^BOOL { return bulkRequests == 1; }, "capacity download started");
        } else if ([mode isEqualToString:@"bulk-success"]) {
            until(^BOOL { return [latest.metrics containsString:@"Download:"]; }, "complete four-transfer result");
            check(bulkRequests == 4, "one warm-up and three measurements");
            [monitor testBandwidth]; spin(.05); check(bulkRequests == 4, "local quota prevents repeat calibration");
        } else if ([mode isEqualToString:@"bulk-partial"] || [mode isEqualToString:@"bulk-rate-limit"]) {
            until(^BOOL { return [latest.metrics containsString:@"incomplete"] || [latest.metrics containsString:@"rate limit"]; }, "capacity failure is explicit");
            check(![latest.metrics containsString:@"Download:"] && bulkRequests == 1, "partial or 429 cannot create a measurement");
        } else {
            until(^BOOL { return latest && latest.state != MLHostDashboardChecking; }, "dashboard state resolved");
            if ([mode isEqualToString:@"normal"]) {
                until(^BOOL { return appRequests == 1; }, "authenticated app request");
                check(latest.state == MLHostDashboardReady && [latest.metrics containsString:@"Service response"], "ready dashboard and labelled service timing");
            } else if ([mode isEqualToString:@"auth"] || [mode isEqualToString:@"unpaired"])
                check(latest.state == MLHostDashboardPairRequired && appRequests == 0 && bulkRequests == 0, "pairing required before apps or bulk probes");
            else check(latest.state == MLHostDashboardServiceUnavailable && appRequests == 0, "service failure or wrong identity never exposes apps");
        }
        stopMonitor(monitor);
        NSUInteger completedCallbacks = callbacks, completedRequests = requests;
        [monitor refresh]; [monitor testBandwidth]; spin(.05);
        check(callbacks == completedCallbacks && requests == completedRequests, "no probes or callbacks after stream cancellation barrier");
    }
    scenario = @"timeout"; fixturePingReplies = YES;
    __block MLHostNetworkSnapshot *latest = nil;
    MLHostNetworkMonitor *monitor = [[MLHostNetworkMonitor alloc] initWithHost:host(YES) configuration:configuration()
        update:^(MLHostNetworkSnapshot *snapshot, ServerInfoResponse *info, AppListResponse *apps) { latest = snapshot; }];
    [monitor refresh];
    until(^BOOL { return latest.state == MLHostDashboardServiceUnavailable; }, "PC reachable without streaming service");
    check([latest.metrics containsString:@"Ping RTT: 3.0"], "ICMP timing distinguished from service timing");
    fixturePingReplies = NO;
    for (int i = 0; i < 3; ++i) { spin(1.05); [monitor refresh]; spin(.1); }
    check(latest.state == MLHostDashboardUnreachable, "repeated failures produce unreachable state");
    scenario = @"normal"; spin(1.05); [monitor refresh];
    until(^BOOL { return latest.state == MLHostDashboardReady; }, "automatic recovery restores apps state");
    stopMonitor(monitor);
    std::printf("%lu native host transport/state/lifecycle checks passed (fixtures, no physical TV or TLS qualification)\n", (unsigned long)checks);
} }

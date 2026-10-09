// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import "MLHostPing.h"
#include <cstdio>
#include <cstdlib>
static void waitFor(BOOL (^done)(void)) {
    double deadline = NSProcessInfo.processInfo.systemUptime + 3;
    while (!done() && NSProcessInfo.processInfo.systemUptime < deadline)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    if (!done()) std::abort();
}
int main() { @autoreleasepool {
    unsigned replies = 0;
    for (NSString *address in @[@"127.0.0.1", @"::1", @"localhost"]) {
        MLHostPing *ping = [MLHostPing new]; __block BOOL done = NO, replied = NO;
        [ping startHost:address completion:^(BOOL success, double ms) { done = YES; replied = success && ms >= 0; }];
        waitFor(^BOOL { return done; }); if (replied) ++replies;
        __block BOOL stopped = NO; [ping stopWithCompletion:^{ stopped = YES; }];
        waitFor(^BOOL { return stopped; });
    }
    for (NSString *address in @[@"localhost", @"127.0.0.1", @"::1"]) {
        MLHostPing *pending = [MLHostPing new]; __block unsigned canceled = 0;
        [pending startHost:address completion:^(BOOL replied, double ms) { std::abort(); }];
        [pending stopWithCompletion:^{ ++canceled; }];
        [pending stopWithCompletion:^{ ++canceled; }];
        waitFor(^BOOL { return canceled == 2; });
    }
    MLHostPing *unresolved = [MLHostPing new]; __block BOOL expired = NO;
    double started = NSProcessInfo.processInfo.systemUptime;
    [unresolved startHost:@"moonlight-probe-fixture.invalid" completion:^(BOOL replied, double ms) {
        if (replied) std::abort(); expired = YES;
    }];
    waitFor(^BOOL { return expired; });
    if (NSProcessInfo.processInfo.systemUptime - started > 2.5) std::abort();
    std::printf("DNS deadline and repeated DNS/IPv4/IPv6 cancellation passed; %u/3 Mac loopback replies (no physical TV result)\n", replies);
    if (replies != 3) return 1;
} }

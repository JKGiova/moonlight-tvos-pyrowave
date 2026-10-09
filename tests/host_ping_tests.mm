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
    MLHostPing *pending = [MLHostPing new]; __block BOOL canceled = NO;
    [pending startHost:@"localhost" completion:^(BOOL replied, double ms) { std::abort(); }];
    [pending stopWithCompletion:^{ canceled = YES; }]; waitFor(^BOOL { return canceled; });
    std::printf("ICMP cancellation passed; %u/3 Mac loopback replies (no physical TV result)\n", replies);
    if (replies != 3) return 1;
} }

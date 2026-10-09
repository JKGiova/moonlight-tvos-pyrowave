// SPDX-License-Identifier: MIT
#import "MLHostMonitorBarrier.h"

@implementation MLHostMonitorBarrier {
    NSUInteger _pending;
    NSMutableArray<void (^)(void)> *_waiters;
}
- (instancetype)init {
    if ((self = [super init])) _waiters = [NSMutableArray array];
    return self;
}
- (void)deliverWhenDrained {
    while (_pending == 0 && _waiters.count > 0) {
        void (^callback)(void) = _waiters.firstObject;
        [_waiters removeObjectAtIndex:0];
        callback();
        // A callback may register another stop; remaining waiters must wait.
    }
}
- (void)stopMonitor:(id<MLHostMonitorStopping>)monitor completion:(void (^)(void))completion {
    NSAssert(NSThread.isMainThread, @"Main-thread lifecycle required");
    if (completion) [_waiters addObject:[completion copy]];
    if (monitor) {
        ++_pending;
        [monitor stopWithCompletion:^{
            // Retain the monitor until its asynchronous teardown completes.
            (void)monitor;
            --self->_pending;
            [self deliverWhenDrained];
        }];
    } else [self deliverWhenDrained];
}
@end

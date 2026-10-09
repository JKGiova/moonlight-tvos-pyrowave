// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@protocol MLHostMonitorStopping <NSObject>
- (void)stopWithCompletion:(nullable void (^)(void))completion;
@end

// Main-thread barrier shared across dashboard visits. Navigation may release
// its current monitor before URLSession/DNS/socket cancellation has drained.
@interface MLHostMonitorBarrier : NSObject
- (void)stopMonitor:(nullable id<MLHostMonitorStopping>)monitor
         completion:(nullable void (^)(void))completion;
@end
NS_ASSUME_NONNULL_END

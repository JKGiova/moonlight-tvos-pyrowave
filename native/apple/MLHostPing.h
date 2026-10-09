// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Optional unprivileged ICMP echo. A missing reply is not proof of power-off.
@interface MLHostPing : NSObject
- (void)startHost:(NSString *)host completion:(void (^)(BOOL replied, double milliseconds))completion;
- (void)stopWithCompletion:(nullable void (^)(void))completion;
@end
NS_ASSUME_NONNULL_END

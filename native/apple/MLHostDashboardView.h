// SPDX-License-Identifier: MIT
#import <UIKit/UIKit.h>
#import "MLHostNetworkMonitor.h"
NS_ASSUME_NONNULL_BEGIN
@interface MLHostDashboardView : UIView
@property(nonatomic, copy, nullable) void (^retryAction)(void);
@property(nonatomic, copy, nullable) void (^wakeAction)(void);
@property(nonatomic, copy, nullable) void (^pairAction)(void);
@property(nonatomic, copy, nullable) void (^bandwidthAction)(void);
- (void)showSnapshot:(MLHostNetworkSnapshot *)snapshot canWake:(BOOL)canWake;
@end
NS_ASSUME_NONNULL_END

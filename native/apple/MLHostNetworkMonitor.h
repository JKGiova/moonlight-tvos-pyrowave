// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
@class TemporaryHost, ServerInfoResponse, AppListResponse;

typedef NS_ENUM(NSInteger, MLHostDashboardState) {
    MLHostDashboardChecking, MLHostDashboardReady, MLHostDashboardServiceUnavailable,
    MLHostDashboardUnreachable, MLHostDashboardPairRequired
};
NS_ASSUME_NONNULL_BEGIN
@interface MLHostNetworkSnapshot : NSObject
@property(nonatomic) MLHostDashboardState state;
@property(nonatomic, copy) NSString *message;
@property(nonatomic, copy) NSString *metrics;
@property(nonatomic) BOOL canTestBandwidth;
@end

// Foreground dashboard only; never instantiate for an active stream.
@interface MLHostNetworkMonitor : NSObject
- (instancetype)initWithHost:(TemporaryHost *)host
                       update:(void (^)(MLHostNetworkSnapshot *, ServerInfoResponse * _Nullable,
                                        AppListResponse * _Nullable))update;
// Injectable URL loading configuration for deterministic transport regression tests.
- (instancetype)initWithHost:(TemporaryHost *)host configuration:(NSURLSessionConfiguration *)configuration
                       update:(void (^)(MLHostNetworkSnapshot *, ServerInfoResponse * _Nullable,
                                        AppListResponse * _Nullable))update;
- (void)start;
- (void)refresh;
- (void)testBandwidth;
- (void)stopWithCompletion:(nullable void (^)(void))completion;
@end
NS_ASSUME_NONNULL_END

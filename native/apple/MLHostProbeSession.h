// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface MLHostProbeResult : NSObject
@property(nonatomic, nullable) NSData *body;
@property(nonatomic, nullable) NSHTTPURLResponse *response;
@property(nonatomic, nullable) NSError *error;
@property(nonatomic) uint64_t receivedBytes;
@property(nonatomic) NSTimeInterval duration;
@end

// All methods and callbacks run on main. One bounded request at a time. Large
// probe bodies are counted and discarded, never accumulated or written to disk.
@interface MLHostProbeSession : NSObject <NSURLSessionDataDelegate>
- (instancetype)initWithAuthenticationDelegate:(id<NSURLSessionDelegate>)delegate
                                 configuration:(NSURLSessionConfiguration *)configuration;
- (BOOL)request:(NSURLRequest *)request maximumBytes:(uint64_t)maximumBytes
     retainBody:(BOOL)retainBody completion:(void (^)(MLHostProbeResult *))completion;
- (void)cancelRequest;
// Completion follows URLSession invalidation: no task/delegate remains active.
- (void)stopWithCompletion:(nullable void (^)(void))completion;
@end
NS_ASSUME_NONNULL_END

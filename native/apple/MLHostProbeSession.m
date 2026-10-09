// SPDX-License-Identifier: MIT
#import "MLHostProbeSession.h"

@implementation MLHostProbeResult
@end

@implementation MLHostProbeSession {
    NSURLSession *_session;
    id<NSURLSessionDelegate> _authentication;
    NSURLSessionDataTask *_task;
    MLHostProbeResult *_result;
    NSMutableData *_body;
    uint64_t _limit;
    NSTimeInterval _started;
    void (^_completion)(MLHostProbeResult *);
    NSMutableArray<void (^)(void)> *_stopCompletions;
    BOOL _stopped, _invalidated;
}
- (instancetype)initWithAuthenticationDelegate:(id<NSURLSessionDelegate>)delegate
                                 configuration:(NSURLSessionConfiguration *)configuration {
    if ((self = [super init])) {
        _authentication = delegate;
        _stopCompletions = [NSMutableArray array];
        configuration.URLCache = nil;
        configuration.HTTPCookieStorage = nil;
        configuration.URLCredentialStorage = nil;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        configuration.timeoutIntervalForResource = 2;
        configuration.HTTPMaximumConnectionsPerHost = 1;
        _session = [NSURLSession sessionWithConfiguration:configuration delegate:self
                                           delegateQueue:NSOperationQueue.mainQueue];
    }
    return self;
}
- (BOOL)request:(NSURLRequest *)request maximumBytes:(uint64_t)maximumBytes
     retainBody:(BOOL)retainBody completion:(void (^)(MLHostProbeResult *))completion {
    NSAssert(NSThread.isMainThread, @"Main-thread lifecycle required");
    if (_stopped || _task || !request.URL || maximumBytes == 0) return NO;
    _result = [MLHostProbeResult new];
    _limit = maximumBytes;
    _body = retainBody ? [NSMutableData data] : nil;
    _completion = [completion copy];
    _started = NSProcessInfo.processInfo.systemUptime;
    NSMutableURLRequest *bounded = [request mutableCopy];
    bounded.timeoutInterval = MIN(2, request.timeoutInterval);
    bounded.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [bounded setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];
    _task = [_session dataTaskWithRequest:bounded];
    [_task resume];
    __weak MLHostProbeSession *weakSelf = self;
    __weak NSURLSessionDataTask *weakTask = _task;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(bounded.timeoutInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        MLHostProbeSession *strongSelf = weakSelf;
        NSURLSessionDataTask *task = weakTask;
        if (strongSelf && task && task == strongSelf->_task) {
            strongSelf->_result.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
            [task cancel];
        }
    });
    return YES;
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
 didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    if (_stopped || task != _task || ![response isKindOfClass:NSHTTPURLResponse.class]) {
        completionHandler(NSURLSessionResponseCancel); return;
    }
    _result.response = (NSHTTPURLResponse *)response;
    if (response.expectedContentLength > 0 && (uint64_t)response.expectedContentLength > _limit) {
        _result.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorDataLengthExceedsMaximum userInfo:nil];
        completionHandler(NSURLSessionResponseCancel); return;
    }
    completionHandler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (_stopped || task != _task) return;
    if (data.length > _limit - _result.receivedBytes) {
        _result.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorDataLengthExceedsMaximum userInfo:nil];
        [task cancel]; return;
    }
    _result.receivedBytes += data.length;
    [_body appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (task != _task) return;
    MLHostProbeResult *result = _result;
    result.duration = NSProcessInfo.processInfo.systemUptime - _started;
    result.error = result.error ?: error;
    result.body = _body;
    void (^completion)(MLHostProbeResult *) = _completion;
    _task = nil; _completion = nil; _body = nil; _result = nil;
    if (!_stopped && completion) completion(result);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    // Never move pairing credentials or a probe onto a redirected route.
    completionHandler(nil);
}
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    if (_stopped) completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
    else [_authentication URLSession:session didReceiveChallenge:challenge completionHandler:completionHandler];
}
- (void)stopWithCompletion:(void (^)(void))completion {
    NSAssert(NSThread.isMainThread, @"Main-thread lifecycle required");
    if (_invalidated) { if (completion) completion(); return; }
    if (completion) [_stopCompletions addObject:[completion copy]];
    if (_stopped) return;
    _stopped = YES;
    _completion = nil;
    [_session invalidateAndCancel];
}
- (void)cancelRequest { [_task cancel]; }
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error {
    _invalidated = YES;
    _session = nil; _authentication = nil; _task = nil;
    NSArray *callbacks = [_stopCompletions copy];
    [_stopCompletions removeAllObjects];
    for (void (^callback)(void) in callbacks) callback();
}
@end

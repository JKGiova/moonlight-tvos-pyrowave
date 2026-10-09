// SPDX-License-Identifier: MIT
#import "HostFixtures.h"
#import "MLHostPing.h"
BOOL fixturePingReplies = NO;
@implementation TemporaryHost
@end
@implementation Utils
+ (NSURLComponents *)parts:(NSString *)address { return [NSURLComponents componentsWithString:[@"http://" stringByAppendingString:address]]; }
+ (NSString *)addressPortStringToAddress:(NSString *)address {
    NSString *name = [self parts:address].host;
    return [name hasPrefix:@"["] ? [name substringWithRange:NSMakeRange(1, name.length-2)] : name;
}
+ (unsigned short)addressPortStringToPort:(NSString *)address { return (unsigned short)([self parts:address].port.intValue ?: 47989); }
@end
@implementation HttpManager
- (instancetype)initWithAddress:(NSString *)address httpsPort:(unsigned short)port serverCert:(NSData *)cert { return [super init]; }
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completion {
    completion(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
}
@end
@implementation ServerInfoResponse {
    NSMutableDictionary *_tags;
    NSMutableString *_value;
}
- (void)populateWithData:(NSData *)data {
    _tags = [NSMutableDictionary dictionary];
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data]; parser.delegate = self; [parser parse];
}
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified attributes:(NSDictionary<NSString *, NSString *> *)attributes {
    if ([name isEqualToString:@"root"]) self.statusCode = [attributes[@"status_code"] integerValue];
    _value = [NSMutableString string];
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string { [_value appendString:string]; }
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified {
    _tags[name] = [_value copy] ?: @"";
}
- (BOOL)isStatusOk { return self.statusCode == 200; }
- (NSString *)getStringTag:(NSString *)tag { return _tags[tag]; }
- (BOOL)getIntTag:(NSString *)tag value:(NSInteger *)value {
    if (!_tags[tag]) return NO; *value = [_tags[tag] integerValue]; return YES;
}
@end
@implementation AppListResponse
- (NSSet *)getAppList { return [self isStatusOk] ? [NSSet setWithObject:@"Fixture app"] : nil; }
@end
@implementation MLHostPing {
    BOOL _stopped;
}
- (void)startHost:(NSString *)host completion:(void (^)(BOOL, double))completion {
    dispatch_async(dispatch_get_main_queue(), ^{ if (!self->_stopped) completion(fixturePingReplies, 3); });
}
- (void)stopWithCompletion:(void (^)(void))completion { _stopped = YES; if (completion) completion(); }
@end

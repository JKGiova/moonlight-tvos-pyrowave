// SPDX-License-Identifier: MIT
// Minimal adapters for the real monitor's macOS transport/state tests. These do
// not claim to exercise Moonlight pairing, certificate validation or UIKit.
#import <Foundation/Foundation.h>
@interface TemporaryHost : NSObject
@property(nonatomic, copy) NSString *uuid, *activeAddress, *localAddress, *address, *externalAddress, *ipv6Address;
@property(nonatomic) unsigned short httpsPort;
@property(nonatomic) NSData *serverCert;
@property(nonatomic) NSSet *appList;
@end
@interface Utils : NSObject
+ (NSString *)addressPortStringToAddress:(NSString *)address;
+ (unsigned short)addressPortStringToPort:(NSString *)address;
@end
@interface HttpManager : NSObject <NSURLSessionDelegate>
- (instancetype)initWithAddress:(NSString *)address httpsPort:(unsigned short)port serverCert:(NSData *)cert;
@end
@interface ServerInfoResponse : NSObject <NSXMLParserDelegate>
@property(nonatomic) NSInteger statusCode;
- (void)populateWithData:(NSData *)data;
- (BOOL)isStatusOk;
- (NSString *)getStringTag:(NSString *)tag;
- (BOOL)getIntTag:(NSString *)tag value:(NSInteger *)value;
@end
@interface AppListResponse : ServerInfoResponse
- (NSSet *)getAppList;
@end
#define TAG_UNIQUE_ID @"uniqueid"
#define TAG_HTTPS_PORT @"HttpsPort"
#define TAG_PAIR_STATUS @"PairStatus"
#define TAG_CURRENT_GAME @"currentgame"

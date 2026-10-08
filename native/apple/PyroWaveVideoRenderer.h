// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
#import "ConnectionCallbacks.h"
#include "Limelight.h"

@interface PyroWaveVideoRenderer : NSObject
+ (BOOL)isDecoderBackendCandidate;
- (instancetype)initWithView:(UIView*)view callbacks:(id<ConnectionCallbacks>)callbacks;
- (int)prepareWidth:(int)width height:(int)height fullRange:(BOOL)fullRange;
// Copies all bytes before returning; the caller can complete the decode unit.
- (int)submitDecodeUnit:(PDECODE_UNIT)unit;
- (void)stop;
- (NSDictionary*)statistics;
@end

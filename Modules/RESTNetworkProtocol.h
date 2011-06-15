/*
 * RCSMac - RESTNetworkProtocol
 *  Implementation for REST Protocol.
 *
 *
 * Created by revenge on 12/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>
#import "NetworkProtocol.h"


@interface RESTNetworkProtocol : NSObject <NetworkProtocol>
{
@private
  NSURL *mURL;
  uint32_t mPort;

@private
  uint32_t mMinDelay;
  uint32_t mMaxDelay;
  uint32_t mBandwidthLimit;
}

- (id)initWithConfiguration: (NSData *)aConfiguration;
- (void)dealloc;

@end
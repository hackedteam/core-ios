/*
 * RCSMac - Authentication Network Operation
 *
 *
 * Created on 13/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>
#import "NetworkOperation.h"
#import "RESTTransport.h"


@interface AuthNetworkOperation : NSObject <NetworkOperation>
{
@private
  NSData *mBackdoorSignature;
  RESTTransport *mTransport;
}

- (id)initWithTransport: (RESTTransport *)aTransport;
- (void)dealloc;

@end

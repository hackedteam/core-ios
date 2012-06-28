/*
 * RCSMac - Bye Network Operation
 *
 *
 * Created on 12/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>
#import "NetworkOperation.h"
#import "RESTTransport.h"


@interface ByeNetworkOperation : NSObject <NetworkOperation>
{
  RESTTransport *mTransport;
}

- (id)initWithTransport: (RESTTransport *)aTransport;

@end
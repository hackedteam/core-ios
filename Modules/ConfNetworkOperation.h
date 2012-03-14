/*
 * RCSMac - ConfigurationUpdate Network Operation
 *
 *
 * Created by revenge on 12/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>
#import "NetworkOperation.h"
#import "RESTTransport.h"


@interface ConfNetworkOperation : NSObject <NetworkOperation>
{
@private
  RESTTransport *mTransport;
}

- (id)initWithTransport: (RESTTransport *)aTransport;
- (BOOL)sendConfAck:(BOOL)retAck;

@end
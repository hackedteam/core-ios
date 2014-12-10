/*
 * RCSMac - ConfigurationUpdate Network Operation
 *
 *
 * Created on 12/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>
#import "NetworkOperation.h"
#import "RESTTransport.h"
//#import "RCSIConfManager.h"

@interface ConfNetworkOperation : NSObject <NetworkOperation>
{
@private
  RESTTransport *mTransport;
//  _i_ConfManager *configurationManager;
}

- (id)initWithTransport: (RESTTransport *)aTransport;
- (BOOL)sendConfAck:(int)retAck;

@end
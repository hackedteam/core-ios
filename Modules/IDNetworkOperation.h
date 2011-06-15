
/*
 * RCSMac - Identification Network Operation
 *
 *
 * Created by revenge on 12/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>
#import "NetworkOperation.h"
#import "RESTTransport.h"


@interface IDNetworkOperation : NSObject <NetworkOperation>
{
@private
  RESTTransport *mTransport;
  NSMutableArray *mCommands;
}

@property (readonly, getter=getCommands) NSMutableArray *mCommands;

- (id)initWithTransport: (RESTTransport *)aTransport;
- (void)dealloc;

@end
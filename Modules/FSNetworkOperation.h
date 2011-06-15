/*
 * RCSMac - FileSystem Browsing Network Operation
 *
 *
 * Created by revenge on 12/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>
#import "NetworkOperation.h"
#import "RESTTransport.h"


@interface FSNetworkOperation : NSObject <NetworkOperation>
{
@private
  RESTTransport *mTransport;
  NSMutableArray *mPaths;
}

@property (readonly, getter=getPaths) NSMutableArray *mPaths;

- (id)initWithTransport: (RESTTransport *)aTransport;
- (void)dealloc;

@end
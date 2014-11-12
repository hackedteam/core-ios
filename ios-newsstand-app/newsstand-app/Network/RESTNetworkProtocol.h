/*
 * RCSMac - RESTNetworkProtocol
 *  Implementation for REST Protocol.
 *
 *
 * Created on 12/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */
#import <Foundation/Foundation.h>
#import "NetworkProtocol.h"
//#import "Reachability.h"
//#import "RCSIConfManager.h"

@interface RESTNetworkProtocol : NSObject <NetworkProtocol>
{
@private
  id configurationManager;
  NSURL     *mURL;
  uint32_t  mPort;
  
@private
  uint32_t mWifiForce;
  uint32_t mGprsForce;
  BOOL mWifiForced;

// Used in order to restore the original configuration
// after the APN Sync has been completed
@private
  NSString *mOrigAPNHost;
  NSString *mOrigAPNUser;
  NSString *mOrigAPNPass;
  BOOL mUsedAPN;
}

- (id)initWithConfiguration: (NSData *)aConfiguration
                    andType: (u_int)aType;

- (void)dealloc;

- (BOOL)getAvailableConnection;
#if 0
- (BOOL)configureAPNWithHost: (NSString *)host
                        user: (NSString *)username
                 andPassword: (NSString *)password;
#endif
@end

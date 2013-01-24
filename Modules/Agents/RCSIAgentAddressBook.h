/*
 * RCSiOS - messages agent
 *
 *
 * Created by Massimo Chiodini on 12/12/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "RCSICommon.h"
#import "RCSIAgent.h"

#ifndef __RCSIAgentAddressBook_h__
#define __RCSIAgentAddressBook_h__

#import "RCSILogManager.h"

@interface _i_AgentAddressBook : _i_Agent <Agents>
{
  int                 abChanges;
  CFAbsoluteTime      mLastABDateTime;
  BOOL                mIsMyContactSaved;
  NSString            *mMyPhoneNumber;
}

- (id)initWithConfigData:(NSData*)aData;

@end

#endif

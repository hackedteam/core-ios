//
//  RCSIAgentChat.h
//  RCSIphone
//
//  Created by armored on 7/25/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RCSICommon.h"
#import "RCSIAgent.h"

@interface _i_AgentChat : _i_Agent <Agents>
{
  int mLastMsgPK;
  int mLastWAMsgPk;
  int mLastSkMsgPk;
  NSString *mWADbPathName;
  NSString *mWAUsername;
  NSString *mSkDbPathName;
  NSString *mSkUsername;
}

@end

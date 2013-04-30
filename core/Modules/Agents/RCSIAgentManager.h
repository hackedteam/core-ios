//
//  RCSIAgentManager.h
//  RCSIphone
//
//  Created by kiodo on 11/04/12.
//  Copyright 2012 HT srl. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface _i_AgentManager : NSObject
{
  NSMutableArray *agentsList;
  NSMutableArray *mAgentMessageQueue;
  NSMachPort     *notificationPort;
  
#define AGENT_MANAGER_RUNNING  0
#define AGENT_MANAGER_STOPPING 1
#define AGENT_MANAGER_STOPPED  2
  int             agentManagerStatus;
  NSSet           *mInternalAgentsSet;
}

@property (readonly) NSMachPort *notificationPort;

- (int)processIncomingMessages;
- (BOOL)start;
- (void)stop;

@end

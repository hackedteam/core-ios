//
//  RCSIAgent.m
//  RCSIphone
//
//  Created by kiodo on 11/04/12.
//  Copyright 2012 HT srl. All rights reserved.
//
#import "RCSICommon.h"
#import "RCSIAgent.h"

@implementation RCSIAgent

@synthesize mAgentConfiguration;
//@synthesize mAgentStatus;
@synthesize mAgentID;
@synthesize mThread;

- (id)initWithConfigData:(NSData*)aData
{
    self = [super init];
    if (self) 
      {
        [self setMAgentConfiguration:aData];
        mAgentStatus = AGENT_STATUS_STOPPED;
        mThread = nil;
      }
    
    return self;
}

- (void)dealloc
{
  [mAgentConfiguration release];
  [mThread release];
  [super dealloc];
}

- (BOOL)isThreadCancelled
{
  return [[NSThread currentThread] isCancelled];
}

- (void)cancelThread
{
  [mThread cancel];
}

- (u_int)mAgentStatus
{
  u_int status;
  
  @synchronized(self)
  {
     status = mAgentStatus;
  }
  
  return status;
}

- (u_int)setMAgentStatus:(u_int)aStatus
{
   u_int status;
  
  @synchronized(self)
  {
    // status == stopped  -> status->running
    // status == running  -> status=stopping or status=stopped
    // status == stopping -> status=stopping or status=stopped
    switch (mAgentStatus)
      {
        case AGENT_STATUS_STOPPED:
          if (aStatus == AGENT_STATUS_RUNNING)
            {
              mAgentStatus = aStatus;
            }
        break;
        case AGENT_STATUS_RUNNING:
          if (aStatus == AGENT_STATUS_STOPPING || aStatus == AGENT_STATUS_STOPPED)
            {
              mAgentStatus = aStatus;
            }
        break;
        case AGENT_STATUS_STOPPING:
          if (aStatus == AGENT_STATUS_STOPPED)
            {
              mAgentStatus = aStatus;
            }
        break;
      }
  
    status = mAgentStatus;
  }
  
  return status;
}
@end

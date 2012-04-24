//
//  RCSIEventTimer.m
//  RCSIphone
//
//  Created by kiodo on 01/03/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "RCSIEventTimer.h"
#import "RCSIEvents.h"

//#define DEBUG_

extern NSString *kRunLoopEventManagerMode;

@implementation RCSIEventTimer

@synthesize timerType;

- (BOOL)timerDailyEndReached
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  BOOL bRet = FALSE;
  
  NSDate *now = [NSDate date];
  NSTimeInterval nowInt = [now timeIntervalSince1970];
  NSTimeInterval endInt = [endDate timeIntervalSince1970];
  
  if (nowInt > endInt)
    bRet = TRUE;
  
  [pool release];
    
  return bRet;
}

// reached end action: reschedule daily timer for next day
- (void)resetTimerDaily
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSTimeInterval startTime = [startDate timeIntervalSince1970];
  NSTimeInterval nextStartTime = startTime + 3600*24;
  
  [startDate release];
  startDate = [[NSDate dateWithTimeIntervalSince1970: nextStartTime] retain];

  NSTimeInterval endTime = [endDate timeIntervalSince1970];
  NSTimeInterval nextEndTime = endTime + 3600*24;
  
  [endDate release];
  endDate = [[NSDate dateWithTimeIntervalSince1970: nextEndTime] retain];  
  
  [pool release];
}

- (void)tryTriggerRepeat:(NSTimer*)aTimer
{
  if ([self isEnabled] == TRUE)
    {
      [[RCSIEvents sharedInstance] triggerAction: [repeat intValue]];
    }
  
  if (currIteration > 0)
    {
      currIteration--;
      if (timerType == TIMER_DAILY)
        {
          if ([self timerDailyEndReached] == NO)
            [self setRepeatTimer];
          else
            [self setEndTimer];
        }
      else    
        [self setRepeatTimer];
    }  
  else if (currIteration == 0)
    {
      currIteration = (iter == nil ? 0xFFFFFFFF : [iter intValue]);
    
      if (currIteration > 0)
        currIteration--;
      
      // Loop trigger only start/repeat
      if (timerType != TIMER_LOOP)
        [self setEndTimer];
    }
  else if (currIteration == 0xFFFFFFFF) 
    {
      if (timerType == TIMER_DAILY)
        {
          if ([self timerDailyEndReached] == NO)
            [self setRepeatTimer];
          else
            [self setEndTimer];
        }
      else if ([repeat intValue] != 0xFFFFFFFF)
        [self setRepeatTimer];
    }
}

- (void)tryTriggerEnd:(NSTimer*)aTimer
{
  if ([self readyToTriggerEnd] == TRUE)
    {
      if ([self isEnabled] == TRUE)
        {
          [[RCSIEvents sharedInstance] triggerAction: [end intValue]];
        }
    
      // TIMER_DATE, TIMER_INST, TIMER_AFTER_STARTUP: one shot event not rescheduled
      if (timerType == TIMER_DAILY)
        {
          [self resetTimerDaily];
          [self setStartTimer];
        }
    }
}

@end

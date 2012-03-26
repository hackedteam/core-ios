//
//  RCSIEvent.m
//  RCSIphone
//
//  Created by kiodo on 02/03/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//
#import "RCSIEvents.h"
#import "RCSIEvent.h"

#define DEBUG_TMP

extern NSString *kRunLoopEventManagerMode;

@implementation RCSIEvent

@synthesize start;
@synthesize end;
@synthesize delay;
@synthesize repeat;
@synthesize iter;
@synthesize enabled;
@synthesize ts;
@synthesize te;
@synthesize startDate;
@synthesize endDate;
@synthesize startTimer;
@synthesize endTimer;
@synthesize repeatTimer;

- (id)init
{
  self = [super init];
  if (self) 
    {
      eventStatus = EVENT_TRIGGERING_START;
      
      // to trigger event by default
      enabled     = nil;
      
      // date for setting the timers
      startDate   = nil;
      endDate     = nil;
      delay       = nil;
      
      // timers init by set*Timer
      startTimer  = nil;
      repeatTimer = nil;
      endTimer    = nil;
      
      // no loop
      currIteration = 0;
    }
  
  return self;
}

- (BOOL)isEnabled
{
  BOOL bRet;
  
  @synchronized(self)
  {
    if (enabled == nil || [enabled intValue] == EVENT_ENABLED)
      bRet=TRUE;
    else
      bRet=FALSE;
  } 
  
  return bRet;
}

#pragma mark -
#pragma mark Add timers
#pragma mark -

// also invoked by [RCSIEvent eventManagerRunLoop]
- (void)setStartTimer
{  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSTimeInterval theDelay = 1.00;
  
  currIteration = (iter == nil ? 0xFFFFFFFF : ([iter intValue]));
  
  if (currIteration > 0)
    currIteration--;
    
  if (startDate != nil)
    {
      NSTimeInterval currInt = [[NSDate date] timeIntervalSince1970];
      NSTimeInterval startInt = [startDate timeIntervalSince1970];
      theDelay = startInt - currInt;
    }
    
   [self addTimer:startTimer withDelay: theDelay andSelector:@selector(tryTriggerStart:)];
  
  [pool release];
  
  return;
}

- (void)setRepeatTimer
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSTimeInterval theDelay = 1;
  
  if (delay != nil)
    theDelay = [delay intValue];
  
  [self addTimer:repeatTimer withDelay: theDelay andSelector: @selector(tryTriggerRepeat:)];
   
  [pool release];
    
  return;
}

- (void)setEndTimer
{  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSTimeInterval theDelay = 1;
  
  if (endDate != nil)
    {
      NSTimeInterval currInt = [[NSDate date] timeIntervalSince1970];
      NSTimeInterval endInt = [endDate timeIntervalSince1970];
      theDelay = endInt - currInt;
    }
  
  [self addTimer:endTimer withDelay: theDelay andSelector: @selector(tryTriggerEnd:)];

  [pool release];
    
  return;
}

#pragma mark -
#pragma mark Trigger actions
#pragma mark -

// override by subclass
- (BOOL)readyToTriggerStart
{
  return TRUE;
}

- (BOOL)readyToTriggerEnd
{
  return TRUE;
}

- (void)tryTriggerStart:(NSTimer*)aTimer
{
  if ([self readyToTriggerStart] == TRUE)
    {
      if ([self isEnabled] == TRUE)
        {
          [[RCSIEvents sharedInstance] triggerAction: [start intValue]];
        }
        
      [self setRepeatTimer];
    }
  else
    {
      [self setStartTimer];
    }
}

- (void)tryTriggerRepeat:(NSTimer*)aTimer
{
  // trigger repeat until end should trigger
  if ([self readyToTriggerStart] == TRUE)
    if ([self isEnabled] == TRUE)
      {
        [[RCSIEvents sharedInstance] triggerAction: [repeat intValue]];
      }
  else
    {
      currIteration = (iter == nil ? 0xFFFFFFFF : [iter intValue]);
      if (currIteration > 0)
        currIteration--;
      [self setEndTimer];
    }
    
  if (currIteration > 0)
    {
      currIteration--;    
      [self setRepeatTimer];
    }  
  else if (currIteration == 0)
    {
      currIteration = (iter == nil ? 0xFFFFFFFF : [iter intValue]);      
      if (currIteration > 0)
        currIteration--;
      [self setEndTimer];
    }
  else if (currIteration == 0xFFFFFFFF) 
    {
      if ([repeat intValue] != 0xFFFFFFFF)
        [self setRepeatTimer];
      else
        [self setEndTimer];
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
      [self setStartTimer];
    }
  else
    {
      [self setEndTimer];
    }
}

#pragma mark -
#pragma mark NSTimer support method
#pragma mark -

// invoked by [RCSIEvents stop] 
- (void)removeTimers
{
//  if (startTimer != nil && [startTimer isValid])
//    [startTimer invalidate];
//  
//  if (repeatTimer != nil && [repeatTimer isValid])
//    [repeatTimer invalidate];
//  
//  if (endTimer != nil && [endTimer isValid])
//    [endTimer invalidate];
}

- (void)addTimer:(NSTimer*)theTimer withDelay: (int)theDelay andSelector:(SEL)aSelector
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSDate *date = [NSDate dateWithTimeIntervalSinceNow: theDelay];

  NSTimer *timer = [[NSTimer alloc] initWithFireDate: date 
                                            interval: 0.0 
                                              target: self 
                                            selector: aSelector 
                                            userInfo: nil 
                                             repeats: NO];
  
  [[NSRunLoop currentRunLoop] addTimer: timer 
                               forMode: kRunLoopEventManagerMode];

  [timer release];
  
  theTimer = timer;
  
  [pool release];
}


@end

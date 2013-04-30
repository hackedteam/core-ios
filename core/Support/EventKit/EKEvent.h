//
//  EKEvent.h
//  EventKit
//
//  Copyright 2009-2010 Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "EKParticipant.h"

@class EKEventStore, EKCalendar, EKRecurrenceRule, EKAlarm, EKParticipant;

typedef enum {
    EKEventAvailabilityNotSupported = -1,
    EKEventAvailabilityBusy = 0,
    EKEventAvailabilityFree,
    EKEventAvailabilityTentative,
    EKEventAvailabilityUnavailable
} EKEventAvailability;

typedef enum {
    EKEventStatusNone = 0,
    EKEventStatusConfirmed,
    EKEventStatusTentative,
    EKEventStatusCanceled,
} EKEventStatus;


/*!
    @class      EKEvent
    @abstract   The EKEvent class represents an occurrence of an event.
    @discussion Events start life not bound to any store when created with [EKEvent event]. Once an
                event is saved, however, it belongs to the store it was saved into. It cannot be saved into
                a different store later.
*/
//NS_CLASS_AVAILABLE(NA, 4_0)
@interface EKEvent : NSObject {
@private
    EKEventStore       *_store;
    void               *_event;
    NSDate             *_occurrenceDate;
    NSString           *_eventId;
    NSNumber           *_calendarId;
    
    NSDate             *_dateStamp;
    NSURL              *_url;
    BOOL                _allDay;
    BOOL                _detached;
    BOOL                _unread;
    NSString           *_title;
    NSString           *_location;
    NSString           *_notes;
    NSMutableArray     *_alarms;
    NSMutableArray     *_attendees;
    EKParticipant      *_organizer;
    NSDate             *_startDate;
    NSDate             *_endDate;
    NSTimeInterval      _duration;
    EKCalendar         *_calendar;
    int                 _status;
    EKParticipantStatus _partStatus;
    int                 _availability;
    NSString           *_responseComment;
    NSTimeZone         *_timeZone;
    NSDate             *_originalStartDate;
    NSArray            *_exceptionDates;
    NSArray            *_recurrenceRules;
    NSInteger           _birthdayId;
    UInt64              _loadFlags;
    UInt64              _dirtyFlags;
}

/*!
    @method     eventWithEventStore:
    @abstract   Creates a new autoreleased event object.
*/
+ (EKEvent *)eventWithEventStore:(EKEventStore *)eventStore;

/*!
    @property   eventIdentifier
    @abstract   A unique identifier for this event.
    @discussion This identifier can be used to look the event up using [EKEventStore eventWithIdentifier:].
                You can use this not only to simply fetch the event, but also to validate the event
                has not been deleted out from under you when you get an external change notification
                via the EKEventStore database changed notification. If eventWithIdentifier: returns nil,
                the event was deleted.
 
                Please note that if you change the calendar of an event, this ID will likely change. It is
                currently also possible for the ID to change due to a sync operation. For example, if
                a user moved an event in iCal to another calendar, we'd see it as a completely new
                event here.
*/
 
@property(nonatomic, readonly) NSString *eventIdentifier;
 
/*!
    @property   title
    @abstract   The title for an event.
*/
@property(nonatomic, copy) NSString *title;

/*!
    @property   location
    @abstract   The location for an event.
*/
@property(nonatomic, copy) NSString *location;

/*!
    @property   calendar
    @abstract   The calendar for an event.
    @discussion This property represents the calendar the event is currently in.
*/
@property(nonatomic, retain) EKCalendar *calendar;

/*!
    @property   notes
    @abstract   The notes for an event.
*/
@property(nonatomic, copy) NSString *notes;

/*!
    @property   lastModifiedDate
    @abstract   The date this event was last modified.
*/
@property(nonatomic, readonly) NSDate *lastModifiedDate;

/*!
    @property   alarms
    @abstract   An array of EKAlarm objects, or nil if none.
*/
@property(nonatomic, copy) NSArray *alarms;

/*!
    @method     addAlarm:
    @abstract   Adds an alarm to this event.
    @discussion This method add an alarm to an event. Be warned that some calendars can only
                allow a certain maximum number of alarms. When this event is saved, it will
                truncate any extra alarms from the array.
*/
- (void)addAlarm:(EKAlarm *)alarm;

/*!
    @method     removeAlarm:
    @abstract   Removes an alarm from this event.
*/
- (void)removeAlarm:(EKAlarm *)alarm;

/*!
    @property   allDay
    @abstract   Indicates this event is an 'all day' event.
*/
@property(nonatomic, getter=isAllDay) BOOL allDay;

/*!
    @property   startDate
    @abstract   The start date for the event.
    @discussion This property represents the start date for this event. Floating events (such
                as all-day events) are currently always returned in the default time zone.
                ([NSTimeZone defaultTimeZone])
*/
@property(nonatomic, copy) NSDate *startDate;

/*!
    @property   endDate
    @abstract   The end date for the event.
*/
@property(nonatomic, copy) NSDate *endDate;

/*!
    @method     compareStartDateWithEvent
    @abstract   Comparison function you can pass to sort NSArrays of EKEvents by start date.
*/
- (NSComparisonResult)compareStartDateWithEvent:(EKEvent *)other;

/*!
    @property   attendees
    @abstract   An array of EKParticipant objects, or nil if none.
*/
@property(nonatomic, readonly) NSArray *attendees;

/*!
    @property   organizer
    @abstract   The organizer of this event, or nil.
*/
@property(nonatomic, readonly) EKParticipant *organizer;

/*!
    @property   recurrenceRule
    @abstract   The recurrence rule for this event.
*/
@property(nonatomic, retain) EKRecurrenceRule  *recurrenceRule;

/*!
    @property   availability
    @abstract   The availability setting for this event.
    @discussion The availability setting is used by CalDAV and Exchange servers to indicate
                how the time should be treated for scheduling. If the calendar the event is
                curently in does not support event availability, EKEventAvailabilityNotSupported
                is returned.
*/
@property(nonatomic) EKEventAvailability    availability;

/*!
    @property   status
    @abstract   The status of the event.
    @discussion While the status offers four different values in the EKEventStatus enumeration,
                in practice, the only actionable and reliable status is canceled. Any other status
                should be considered informational at best. You cannot set this property. If you
                wish to cancel an event, you should simply remove it using removeEvent:.
*/
@property(nonatomic, readonly) EKEventStatus          status;

/*!
    @property   isDetached
    @abstract   Represents whether this event is detached from a recurring series.
    @discussion If this EKEvent is an instance of a repeating event, and an attribute of this 
                EKEvent has been changed to from the default value generated by the repeating event,
                isDetached will return YES. If the EKEvent is unchanged from its default state, or
                is not a repeating event, isDetached returns NO.
*/
@property(nonatomic, readonly) BOOL isDetached;


/*!
    @method     refresh
    @abstract   Refreshes an event object to ensure it's still valid.
    @discussion When the database changes, your application is sent an EKEventStoreChangedNotification
                note. You should generally consider all EKEvent instances to be invalid as soon as
                you receive the notification. However, for events you truly care to keep around, you
                can call this method. It ensures the record is still valid by ensuring the event and
                start date are still valid. It also attempts to refresh all properties except those
                you might have modified. If this method returns NO, the record has been deleted or is
                otherwise invalid. You should not continue to use it. If it returns YES, all is still
                well, and the record is ready for continued use. You should only call this method on
                events that are more critical to keep around if possible, such as an event that is
                being actively edited, as this call is fairly heavyweight. Do not use it to refresh
                the entire selected range of events you might have had selected. It is mostly pointless
                anyway, as recurrence information may have changed.
*/

- (BOOL)refresh;

@end

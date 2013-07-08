//
//  EKCalendar.h
//  EventKit
//
//  Copyright 2009-2010 Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

/*!
    @enum       EKCalendarType
    @abstract   An enum representing the type of a calendar.
 
    @constant   EKCalendarTypeLocal        This calendar is sync'd from either Mobile Me or tethered.
    @constant   EKCalendarTypeCalDAV       This calendar is from a CalDAV server.
    @constant   EKCalendarTypeExchange     This calendar comes from an Exchange server.
    @constant   EKCalendarTypeSubscription This is a subscribed calendar.
    @constant   EKCalendarTypeBirthday     This is the built-in birthday calendar.
*/

typedef enum {
    EKCalendarTypeLocal,
    EKCalendarTypeCalDAV,
    EKCalendarTypeExchange,
    EKCalendarTypeSubscription,
    EKCalendarTypeBirthday,
} EKCalendarType;

// Event availability support (free/busy)
enum {
    EKCalendarEventAvailabilityNone         = 0,    // calendar doesn't support event availability
    
    EKCalendarEventAvailabilityBusy         = (1 << 0),
    EKCalendarEventAvailabilityFree         = (1 << 1),
    EKCalendarEventAvailabilityTentative    = (1 << 2),
    EKCalendarEventAvailabilityUnavailable  = (1 << 3),
};
typedef NSUInteger EKCalendarEventAvailabilityMask;

@class EKEventStore;

/*!
    @class       EKCalendar
    @abstract    The EKCalendar class represents a calendar for events.
    @discussion  The EKCalendar class represents a calendar for events. In this release,
                 calendars are immutable. You can inspect them, but you cannot alter them,
                 nor can you add or delete calendars from the calendar store.
*/

//NS_CLASS_AVAILABLE(NA, 4_0)
@interface EKCalendar : NSObject {
@private
    EKEventStore       *_store;
    void               *_record;
    NSNumber           *_calendarId;
    id                  _source;

    NSString           *_title;
    CGColorRef          _color;
    EKCalendarType      _type;
    BOOL                _editable;
    int                 _maxAlarms;
    int                 _maxRecurrences;
    UInt32              _constraints;
    BOOL                _isMain;
    
    UInt32              _loadFlags;
    UInt32              _dirtyFlags;
    int                 _order;
}

/*!
    @property   title
    @abstract   The title of the calendar.
*/
@property(nonatomic, readonly)     NSString          *title;

/*!
    @property   type
    @abstract   The type of the calendar as a EKCalendarType.
*/
@property(nonatomic, readonly)     EKCalendarType     type;

/*!
    @property   allowsContentModifications
    @abstract   Represents whether you can this add, remove, or modify items in this calendar.
*/
@property(nonatomic, readonly) BOOL allowsContentModifications;

/*!
    @property   color
    @abstract   Returns the calendar color as a CGColorRef.
*/
@property(nonatomic, readonly) CGColorRef      CGColor;

/*!
    @property   supportedEventAvailabilities
    @discussion Returns a bitfield of supported event availabilities, or EKCalendarEventAvailabilityNone
                if this calendar does not support setting availability on an event.
*/
@property(nonatomic, readonly) EKCalendarEventAvailabilityMask supportedEventAvailabilities;

@end

//
//  EKError.h
//  EventKit
//
//  Copyright 2009-2010 Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

/*!
    @const      EKErrorDomain 
    @abstract   Error domain for NSError values stemming from the EventKit Framework API.
    @discussion This error domain is used as the domain for all NSError instances stemming from the
                EventKit Framework.
*/
extern NSString *const EKErrorDomain /*__OSX_AVAILABLE_STARTING(__MAC_NA,__IPHONE_4_0)*/;

/*!
    @enum       EKErrorCode
    @abstract   Error codes for NSError values stemming from the Calendar Framework.
    @discussion These error codes are used as the codes for all NSError instances stemmming from the
                Calendar Framework.
 
    @constant   EKErrorEventNotMutable                  The event is not mutable and cannot be saved/deleted.
    @constant   EKErrorNoCalendar                       The event has no calendar set.
    @constant   EKErrorNoStartDate                      The event has no start date set.
    @constant   EKErrorNoEndDate                        The event has no end date set.
    @constant   EKErrorDatesInverted                    The end date is before the start date.
    @constant   EKErrorInternalFailure                  An internal error occurred.
    @constant   EKErrorCalendarReadOnly                 Calendar can not have events added to it.
    @constant   EKErrorDurationGreaterThanRecurrence    The duration of an event is greater than the recurrence interval.
    @constant   EKErrorAlarmGreaterThanRecurrence       The alarm interval is greater than the recurrence interval
    @constant   EKErrorStartDateTooFarInFuture          The start date is further into the future than the calendar will display.
    @constant   EKErrorStartDateCollidesWithOtherOccurrence The start date specified collides with another occurrence of that event, and the current calendar doesn't allow it.
    @constant   EKErrorObjectBelongsToDifferentStore    The object you are passing doesn't belong to the calendar store you're dealing with.
    @constant   EKErrorInvitesCannotBeMoved             The event is an invite, and therefore cannot move to another calendar.
    @constant   EKErrorInvalidSpan                      An invalid span was passed when saving/deleting.
*/

#if __IPHONE_4_0 <= __IPHONE_OS_VERSION_MAX_ALLOWED
typedef enum EKErrorCode {
    EKErrorEventNotMutable,
    EKErrorNoCalendar,
    EKErrorNoStartDate,
    EKErrorNoEndDate,
    EKErrorDatesInverted,
    EKErrorInternalFailure,
    EKErrorCalendarReadOnly,
    EKErrorDurationGreaterThanRecurrence,
    EKErrorAlarmGreaterThanRecurrence,
    EKErrorStartDateTooFarInFuture,
    EKErrorStartDateCollidesWithOtherOccurrence,
    EKErrorObjectBelongsToDifferentStore,
    EKErrorInvitesCannotBeMoved,
    EKErrorInvalidSpan,
    
    EKErrorLast // used internally
} EKErrorCode;
#endif

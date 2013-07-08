//
//  EKRecurrenceRule.h
//  EventKit
//
//  Copyright 2009-2010 Apple Inc. All rights reserved.
//
//  This class describes the recurrence pattern for a repeating event. The recurrence rules that can be expressed are 
//  not restricted to the recurrence patterns that can be set in Calendar's UI. It is currently not possible to directly
//  modify a EKRecurrenceRule or any of its properties. This functionality is achieved by creating a new EKRecurrenceRule, and 
//  setting an event to use the new rule. When a new recurrence rule is set on an EKEvent, that change is not saved 
//  until the client has passed the modified event to EKEventStore's saveEvent: method.

#import <Foundation/Foundation.h>

@class EKEventStore;

enum {
    EKSunday = 1,
    EKMonday,
    EKTuesday,
    EKWednesday,
    EKThursday,
    EKFriday,
    EKSaturday
};

/*!
    @class      EKRecurrenceEnd
    @abstract   Class which represents when a recurrence should end.
    @discussion EKRecurrenceEnd is an attribute of EKRecurrenceRule that defines how long
                the recurrence is scheduled to repeat. The recurrence can be defined either
                with an NSUInteger that indicates the total number times it repeats, or with
                an NSDate, after which it no longer repeats. An event which is set to never
                end should have its EKRecurrenceEnd set to nil.
 
                If the end of the pattern is defines with an NSDate, the client must pass a
                valid NSDate, nil cannot be passed. If the end of the pattern is defined as
                terms of a number of occurrences, the occurrenceCount passed to the initializer
                must be positive, it cannot be 0. If the client attempts to initialize a
                EKRecurrenceEnd with a nil NSDate or OccurrenceCount of 0, an exception is raised.

                A EKRecurrenceEnd initialized with an end date will return 0 for occurrenceCount.
                One initialized with a number of occurrences will return nil for its endDate.
*/
//NS_CLASS_AVAILABLE(NA, 4_0)
@interface EKRecurrenceEnd : NSObject <NSCopying> {
@private
    NSDate *_endDate;
    NSUInteger _occurrenceCount;
}

/*!
    @method     recurrenceEndWithEndDate:
    @abstract   Creates an autoreleased recurrence end with a specific end date.
*/
+ (id)recurrenceEndWithEndDate:(NSDate *)endDate;

/*!
    @method     recurrenceEndWithOccurrenceCount:
    @abstract   Creates an autoreleased recurrence end with a maximum occurrence count.
*/
+ (id)recurrenceEndWithOccurrenceCount:(NSUInteger)occurrenceCount;

/*!
    @property   endDate
    @abstract   The end date of this recurrence, or nil if it's count-based.
*/
@property(nonatomic, readonly) NSDate *endDate;

/*!
    @property   occurrenceCount
    @abstract   The maximum occurrence count, or 0 if it's date-based.
*/
@property(nonatomic, readonly) NSUInteger occurrenceCount;
@end

/*!
    @class      EKRecurrenceDayOfWeek
    @abstract   Class which represents a day of the week this recurrence will occur.
    @discussion EKRecurrenceDayOfWeek specifies either a simple day of the week, or the nth instance
                of a particular day of the week, such as the third Tuesday of every month. The week
                number is only valid when used with monthly or yearly recurrences, since it would
                be otherwise meaningless.

                Valid values for dayOfTheWeek are integers 1-7, which correspond to days of the week
                with Sunday = 1. Valid values for weekNumber portion are (+/-)1-53, where a negative
                value indicates a value from the end of the range. For example, in a yearly event -1
                means last week of the year. -1 in a Monthly recurrence indicates the last week of
                the month. 

                The value 0 also indicates the weekNumber is irrelevant (every Sunday, etc.).

                Day-of-week weekNumber values that are out of bounds for the recurrence type will
                result in an exception when trying to initialize the recurrence. In particular,
                weekNumber must be zero when passing EKRecurrenceDayOfWeek objects to initialize a weekly 
                recurrence.
*/

//NS_CLASS_AVAILABLE(NA, 4_0)
@interface EKRecurrenceDayOfWeek : NSObject <NSCopying> {
@private
    NSInteger _dayOfTheWeek;
    NSInteger _weekNumber;
}

/*!
    @method     dayOfWeek:
    @abstract   Creates an autoreleased object with a day of the week and week number of zero.
*/
+ (id)dayOfWeek:(NSInteger)dayOfTheWeek;

/*!
    @method     dayOfWeek:weekNumber:
    @abstract   Creates an autoreleased object with a specific day of week and week number.
*/
+ (id)dayOfWeek:(NSInteger)dayOfTheWeek weekNumber:(NSInteger)weekNumber;

/*!
    @property   dayOfTheWeek
    @abstract   The day of the week.
*/
@property(nonatomic, readonly) NSInteger dayOfTheWeek;

/*!
    @property   weekNumber
    @abstract   The week number.
*/
@property(nonatomic, readonly) NSInteger weekNumber;

@end

/*!
    @enum       EKRecurrenceFrequency
    @abstract   The frequency of a recurrence
    @discussion EKRecurrenceFrequency designates the unit of time used to describe the recurrence.
                It has four possible values, which correspond to recurrence rules that are defined
                in terms of days, weeks, months, and years.
*/
typedef enum {
    EKRecurrenceFrequencyDaily,
    EKRecurrenceFrequencyWeekly,
    EKRecurrenceFrequencyMonthly,
    EKRecurrenceFrequencyYearly
} EKRecurrenceFrequency;

 //  The interval of a EKRecurrenceRule is an NSUInteger which specifies how often the recurrence rule repeats over the
 //  unit of time described by the frequency. For example, if the frequency is EKRecurrenceWeekly, then 
 //  an interval of 1 means the pattern is repeated every week. A NSUInteger of 2 indicates it is repeated every other 
 //  week, 3 means every third week, and so on. The NSUInteger must be a positive integer; 0 is not a valid value, and 
 //  nil will be returned if the client attempts to initialize a rule with a negative or zero interval.
 //
 //  Together, frequency and interval define how often the EKRecurrenceRule's pattern repeats.
 
/*!
    @class      EKRecurrenceRule
    @abstract   Represents how an event repeats.
*/
//NS_CLASS_AVAILABLE(NA, 4_0)
@interface EKRecurrenceRule : NSObject {
@private
    id                      _owner;

    NSArray                *_monthsOfTheYear;
    NSArray                *_daysOfTheMonth;
    NSArray                *_daysOfTheWeek;
    NSArray                *_setPositions;
    NSArray                *_weeksOfTheYear;
    NSArray                *_daysOfTheYear;
    NSInteger               _firstDayOfTheWeek;
    NSInteger               _interval;
    EKRecurrenceFrequency   _frequency;
    EKRecurrenceEnd        *_recurrenceEnd;
    NSDate                 *_cachedEndDate;
        
    UInt32                  _dirtyFlags;
}

/*!
    @method     initRecurrenceWithFrequency:interval:end:
    @abstract   Simple initializer to create a recurrence.
    @discussion This is used to create a simple recurrence with a specific type, interval and end. If interval is
                0, an exception is raised. The end parameter can be nil.
*/
- (id)initRecurrenceWithFrequency:(EKRecurrenceFrequency)type interval:(NSUInteger)interval end:(EKRecurrenceEnd *)end;

/*!
    @method     initRecurrenceWithFrequency:interval:daysOfTheWeek:daysOfTheMonth:monthsOfTheYear:weeksOfTheYear:daysOfTheYear:setPositions:end:
    @abstract   The designated initializer.
    @discussion This can be used to build any kind of recurrence rule. But be aware that certain combinations make
                no sense and will be ignored. For example, if you pass daysOfTheWeek for a daily recurrence, they
                will be ignored.
    @param      type            The type of recurrence
    @param      interval        The interval. Passing zero will raise an exception.
    @param      daysOfTheWeek   An array of EKNthWeekDay objects. Valid for all recurrence types except daily. Ignored otherwise.
                                Corresponds to the BYDAY value in the iCalendar specification.
    @param      daysOfTheMonth  An array of NSNumbers ([+/-] 1 to 31). Negative numbers infer counting from the end of the month.
                                For example, -1 means the last day of the month. Valid only for monthly recurrences. Ignored otherwise.
                                Corresponds to the BYMONTHDAY value in the iCalendar specification.
    @param      monthsOfTheYear An array of NSNumbers (1 to 12). Valid only for yearly recurrences. Ignored otherwise. Corresponds to
                                the BYMONTH value in the iCalendar specification.
    @param      weeksOfTheYear  An array of NSNumbers ([+/1] 1 to 53). Negative numbers infer counting from the end of the year.
                                For example, -1 means the last week of the year. Valid only for yearly recurrences. Ignored otherwise.
                                Corresponds to the BYWEEKNO value in the iCalendar specification.
    @param      daysOfTheYear   An array of NSNumbers ([+/1] 1 to 366). Negative numbers infer counting from the end of the year.
                                For example, -1 means the last day of the year. Valid only for yearly recurrences. Ignored otherwise.
                                Corresponds to the BYYEARDAY value in the iCalendar specification.
    @param      setPositions    An array of NSNumbers ([+/1] 1 to 366). Used at the end of recurrence computation to filter the list
                                to the positions specified. Negative numbers indicate starting at the end, i.e. -1 indicates taking the
                                last result of the set. Valid when daysOfTheWeek, daysOfTheMonth, monthsOfTheYear, weeksOfTheYear, or 
                                daysOfTheYear is passed. Ignored otherwise. Corresponds to the BYSETPOS value in the iCalendar specification.
    @param      end             The recurrence end, or nil.
*/
- (id)initRecurrenceWithFrequency:(EKRecurrenceFrequency)type 
                         interval:(NSInteger)interval 
                    daysOfTheWeek:(NSArray *)days
                   daysOfTheMonth:(NSArray *)monthDays 
                  monthsOfTheYear:(NSArray *)months 
                   weeksOfTheYear:(NSArray *)weeksOfTheYear 
                    daysOfTheYear:(NSArray *)daysOfTheYear
                     setPositions:(NSArray *)setPositions
                              end:(EKRecurrenceEnd *)end;

/*  Properties that exist in all EKRecurrenceRules  */

/*!
    @property       calendarIdentifier;
    @description    Calendar used by this recurrence rule.
*/
@property(nonatomic, readonly) NSString *calendarIdentifier;

/*!
    @property       recurrenceEnd
    @discussion     This property defines when the the repeating event is scheduled to end. The end date can be specified by a number of
                    occurrences, or with an end date.
*/
@property(nonatomic, copy) EKRecurrenceEnd *recurrenceEnd;

/*!
    @property       frequency
    @discussion     This property designates the unit of time used to describe the recurrence pattern.
*/
@property(nonatomic, readonly) EKRecurrenceFrequency frequency;

/*!
    @property       interval
    @discussion     The interval of a EKRecurrenceRule is an NSUInteger which specifies how often the recurrence rule repeats
                    over the unit of time described by the EKRecurrenceFrequency. For example, if the EKRecurrenceFrequency is
                    EKRecurrenceWeekly, then an interval of 1 means the pattern is repeated every week. A NSUInteger of 2
                    indicates it is repeated every other week, 3 means every third week, and so on. The NSUInteger must be a
                    positive integer; 0 is not a valid value, and nil will be returned if the client attempts to initialize a
                    rule with a negative or zero interval. 
*/
@property(nonatomic, readonly) NSInteger interval;

/*!
    @property       firstDayOfTheWeek
    @discussion     Recurrence patterns can specify which day of the week should be treated as the first day. Possible values for this
                    property are integers 0 and 1-7, which correspond to days of the week with Sunday = 1. Zero indicates that the 
                    property is not set for this recurrence. The first day of the week only affects the way the recurrence is expanded
                    for weekly recurrence patterns with an interval greater than 1. For those types of recurrence patterns, the 
                    Calendar framework will set firstDayOfTheWeek to be 2 (Monday). In all other cases, this property will be set 
                    to zero. The iCalendar spec stipulates that the default value is Monday if this property is not set.
*/
@property(nonatomic, readonly) NSInteger firstDayOfTheWeek;


/*  Properties that are only valid for certain EKRecurrenceRules  */

//  The properties that follow are only valid for certain recurrence rules, and are always arrays. For recurrence rules
//  that can be expressed with one of the simple initializers, the arrays will contain a single object, corresponding 
//  to the day of the week, the day of the month, the "NthWeekDay" (for example, the fourth Thursday), or the month of 
//  the year the event recurs. The objects will be NSNumbers, except in the "NthWeekDay" case just mentioned, when
//  the array will contain a CalNthWeekDay instead of an NSNumber.
//  
//  Repeating events using one of the advanced initializers may recur multiple times in the specified time period, for 
//  example, the first and sixteenth days of a month. When this is true, the arrays may contain more than one entry.
//  
//  These properties will only be valid for certain EKRecurrenceRules, depending on how the rule's recurrence is 
//  defined. The constraints on when these properties is valid are described below. When these constraints are not met,
//  the property's value will be nil.

/*!
    @property       daysOfTheWeek
    @discussion     This property is valid for rules whose EKRecurrenceFrequency is EKWeeklyRecurrence, EKMonthlyRecurrence, or 
                    EKYearlyRecurrence. This property can be accessed as an array containing one or more EKRecurrenceDayOfWeek objects
                    corresponding to the days of the week the event recurs. For all other EKRecurrenceRules, this property is nil.
                    This property corresponds to BYDAY in the iCalendar specification.
*/
@property(nonatomic, readonly) NSArray *daysOfTheWeek;

/*!
    @property       daysOfTheMonth
    @discussion     This property is valid for rules whose EKRecurrenceFrequency is EKMonthlyRecurrence, and that were initialized with one
                    or more specific days of the month (not with a day of the week and week of the month). This property can be
                    accessed as an array containing one or more NSNumbers corresponding to the days of the month the event recurs.
                    For all other EKRecurrenceRules, this property is nil. This property corresponds to BYMONTHDAY in the iCalendar 
                    specification.
*/
@property(nonatomic, readonly) NSArray *daysOfTheMonth;

/*!
    @property       daysOfTheYear
    @discussion     This property is valid for rules whose EKRecurrenceFrequency is EKYearlyRecurrence. This property can be accessed as an
                    array containing one or more NSNumbers corresponding to the days of the year the event recurs. For all other 
                    EKRecurrenceRules, this property is nil. This property corresponds to BYYEARDAY in the iCalendar specification. It should
                    contain values between 1 to 366 or -366 to -1.
*/
@property(nonatomic, readonly) NSArray *daysOfTheYear;

/*!
    @property       weeksOfTheYear
    @discussion     This property is valid for rules whose EKRecurrenceFrequency is EKYearlyRecurrence. This property can be accessed as an
                    array containing one or more NSNumbers corresponding to the weeks of the year the event recurs. For all other 
                    EKRecurrenceRules, this property is nil. This property corresponds to BYWEEK in the iCalendar specification. It should
                    contain integers from 1 to 53 or -1 to -53.
*/
@property(nonatomic, readonly) NSArray *weeksOfTheYear;

/*!
    @property       monthsOfTheYear
    @discussion     This property is valid for rules whose EKRecurrenceFrequency is EKYearlyRecurrence. This property can be accessed as an
                    array containing one or more NSNumbers corresponding to the months of the year the event recurs. For all other 
                    EKRecurrenceRules, this property is nil. This property corresponds to BYMONTH in the iCalendar specification.
*/
@property(nonatomic, readonly) NSArray *monthsOfTheYear;

/*!
    @property       setPositions
    @discussion     This property is valid for rules which have a valid daysOfTheWeek, daysOfTheMonth, weeksOfTheYear, or monthsOfTheYear property. It
                    allows you to specify a set of ordinal numbers to help choose which objects out of the set of selected events should be
                    included. For example, setting the daysOfTheWeek to Monday-Friday and including a value of -1 in the array would indicate
                    the last weekday in the recurrence range (month, year, etc). This value corresponds to the iCalendar BYSETPOS property.
*/
@property(nonatomic, readonly) NSArray *setPositions;

@end

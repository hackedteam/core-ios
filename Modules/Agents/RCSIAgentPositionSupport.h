/*
 * RCSIAgentLocalizer.h
 *  Localizer Agent - through GPS or GSM cell
 *
 *
 * Created on 07/10/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <Foundation/Foundation.h>

#ifndef __RCSIAgentPositionSupport_h__
#define __RCSIAgentPositionSupport_h__

#import "RCSICommon.h"

@interface _i_AgentPositionSupport: NSObject
{
  NSDate *mLastCheckDate;
}

@property (readwrite, retain) NSDate *mLastCheckDate;

+ (_i_AgentPositionSupport *)sharedInstance;

- (void)checkAndSetupLocationServices:(UInt32*)aFlag;

@end

#endif
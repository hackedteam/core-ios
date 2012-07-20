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

@interface RCSIAgentPositionSupport: NSObject
{
  NSDate *mLastCheckDate;
}

@property (readwrite, retain) NSDate *mLastCheckDate;

+ (RCSIAgentPositionSupport *)sharedInstance;

- (void)checkAndSetupLocationServices:(UInt32*)aFlag;

@end

#endif
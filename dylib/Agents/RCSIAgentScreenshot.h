/*
 * RCSiOS - Screenshot agent
 *
 *
 * Created by Massimo Chiodini on 08/03/2010
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#ifndef __RCSIAgentScreenshot_h__
#define __RCSIAgentScreenshot_h__

#import "RCSICommon.h"
#import "RCSIAgent.h"

@interface agentScreenshot: RCSIAgent

- (BOOL)start;
- (void)stop;

@end

#endif
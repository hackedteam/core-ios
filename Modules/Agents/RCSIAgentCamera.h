//
//  RCSIAgentCamera.h
//  RCSIphone
//
//  Created by kiodo on 02/12/11.
//  Copyright 2011 HT srl. All rights reserved.
//
#import "RCSICommon.h"
#import "RCSIAgent.h"

#ifndef __RCSIAgentCamera_h__
#define __RCSIAgentCamera_h__

typedef struct _cameraStruct
{
  UInt32 timeStep;
  UInt32 numStep;
} cameraStruct;


@interface RCSIAgentCamera : RCSIAgent <Agents>

- (id)initWithConfigData:(NSData*)aData;

@end

#endif
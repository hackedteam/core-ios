//
//  RCSIAgentCamera.h
//  RCSIphone
//
//  Created by kiodo on 02/12/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//
#import "RCSICommon.h"

#ifndef __RCSIAgentCamera_h__
#define __RCSIAgentCamera_h__

typedef struct _cameraStruct
{
  UInt32 timeStep;
  UInt32 numStep;
} cameraStruct;


@interface RCSIAgentCamera : NSObject
{
@public
  NSMutableDictionary *mAgentConfiguration;
}

@property (retain, readwrite) NSMutableDictionary *mAgentConfiguration;

+ (RCSIAgentCamera *)sharedInstance;

+ (id)allocWithZone: (NSZone *)aZone;
- (id)copyWithZone: (NSZone *)aZone;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;
- (id)init;

- (void)start;
- (BOOL)stop;

@end

#endif
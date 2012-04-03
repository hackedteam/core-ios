/*
 * NSMutableData AES128 Category
 *  This is a category for NSMutableData in order to provide in-place encryption
 *  capabilities
 *
 * 
 * Created by Alfredo 'revenge' Pesoli on 08/04/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "NSMutableData+AES128.h"

//#import "RCSILogger.h"
//#import "RCSMDebug.h"
//#define JSON_CONFIG
//#define DEBUG_MUTABLE_AES

@implementation NSMutableData (AES128)

- (NSMutableData*)encryptPKCS7:(NSData*)aKey
{
  NSMutableData *outAligned = [[NSMutableData alloc] initWithLength: [self length]+kCCBlockSizeAES128];
  NSMutableData *outData = nil;
  
  memset((char*)[outAligned bytes], 0, [self length] + kCCBlockSizeAES128);
  
  size_t numBytesEncrypted = 0;
  CCCryptorStatus result;
  
  result = CCCrypt(kCCEncrypt, 
                   kCCAlgorithmAES128, 
                   kCCOptionPKCS7Padding,
                   [aKey bytes], 
                   kCCKeySizeAES128,
                   NULL, // initialization vector (optional)
                   [self mutableBytes], [self length], // input
                   [outAligned mutableBytes], [outAligned length], // output
                   &numBytesEncrypted);
                   
  if (result == kCCSuccess)
    {
#ifdef DEBUG_MUTABLE_AES
      NSLog(@"%s:input length: %d out length: %lu", __FUNCTION__, [self length], numBytesEncrypted);
#endif
      outData = [[[NSMutableData alloc] initWithBytes: [outAligned bytes] length:numBytesEncrypted] autorelease];
    }
  
  return outData;
}

- (CCCryptorStatus)__encryptWithKey: (NSData *)aKey
{
  // no additional padding on aligned block
  int pad = 0;
  int outLen = 0;
  BOOL needsPadding = YES;
  
  if ([self length] % kCCBlockSizeAES128)
    {
      pad = ([self length] + kCCBlockSizeAES128 & ~(kCCBlockSizeAES128 - 1)) - [self length];
      [self increaseLengthBy: pad];
      
      outLen        = [self length];
      needsPadding  = YES;
    }
  else
    {
      pad           = 0;
      outLen        = [self length];
      needsPadding  = NO;
    }

  // encrypts in-place since this is a mutable data object
  size_t numBytesEncrypted = 0;
  CCCryptorStatus result;
  
  if (needsPadding == YES)
    {
      result = CCCrypt(kCCEncrypt, 
                       kCCAlgorithmAES128, 
                       kCCOptionPKCS7Padding,
                       [aKey bytes], 
                       kCCKeySizeAES128,
                       NULL, // initialization vector (optional)
                       [self mutableBytes], [self length] - pad, // input
                       [self mutableBytes], outLen, // output
                       &numBytesEncrypted);
    }
  else
    {
      result = CCCrypt(kCCEncrypt, 
                       kCCAlgorithmAES128, 
                       0,
                       [aKey bytes], 
                       kCCKeySizeAES128,
                       NULL, // initialization vector (optional)
                       [self mutableBytes], [self length] - pad, // input
                       [self mutableBytes], outLen, // output
                       &numBytesEncrypted);
    }
  
  return result;
}

-(void)doPKCS7Padding:(uint)pad
{
  if (pad > 0)
    {
      [self increaseLengthBy: pad];
    
      char *buff  = (char*)[self bytes];
      char *ptr   = buff + [self length] - pad;
    
      // do ourself pkcs5/7 padding
      for (int i=0; i < pad; i++) 
      {
        *ptr = pad;
        ptr++;
      }
    }
}

- (CCCryptorStatus)encryptWithKey: (NSData *)aKey
{
  int pad = kCCBlockSizeAES128;
  size_t numBytesEncrypted = 0;
  
  if ([self length] % kCCBlockSizeAES128)
      pad = kCCBlockSizeAES128 - [self length] & (kCCBlockSizeAES128 - 1);
      
  [self doPKCS7Padding: pad];
  
  // padding ourself
  CCCryptorStatus result = 
           CCCrypt(kCCEncrypt, 
                   kCCAlgorithmAES128, 
                   0,
                   [aKey bytes], 
                   kCCKeySizeAES128,
                   NULL,                                  // initialization vector (optional)
                   [self mutableBytes], [self length],    // input
                   [self mutableBytes], [self length],    // output
                   &numBytesEncrypted);
      
  return result;
}

- (CCCryptorStatus)decryptWithKey: (NSData *)aKey
{
  // decrypts in-place since this is a mutable data object
  size_t numBytesDecrypted = 0;
  CCCryptorStatus result = CCCrypt(kCCDecrypt, 
                                   kCCAlgorithmAES128, 
                                   0,                                   // padding removed by [self removePadding]!!
                                   [aKey bytes], 
                                   kCCKeySizeAES128,
                                   NULL,                                // initialization vector (optional)
                                   [self mutableBytes], [self length],  // input
                                   [self mutableBytes], [self length],  // output
                                   &numBytesDecrypted);
  
  return result;
}

- (void)removePadding
{
  // remove padding
  char bytesOfPadding;
  [self getBytes: &bytesOfPadding
           range: NSMakeRange([self length] - 1, sizeof(char))];
  
  [self setLength: [self length] - bytesOfPadding];
}

@end
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


@implementation NSMutableData (AES128)

- (CCCryptorStatus)encryptWithKey: (NSData *)aKey
{
  int pad = [self length];
  int outLen = 0;
  BOOL needsPadding = YES;
  
#ifdef DEBUG_MUTABLE_AES
  infoLog(@"self length: %d", [self length]);
#endif
  
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
  
#ifdef DEBUG_MUTABLE_AES
  infoLog(@"outLen: %d", outLen);
  infoLog(@"pad: %d", pad);
#endif
  
  //
  // encrypts in-place since this is a mutable data object
  //
  size_t numBytesEncrypted = 0;
  CCCryptorStatus result;
  
  if (needsPadding == YES)
    {
      result = CCCrypt(kCCEncrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
                       [aKey bytes], kCCKeySizeAES128,
                       NULL, // initialization vector (optional)
                       [self mutableBytes], [self length] - pad, // input
                       [self mutableBytes], outLen, // output
                       &numBytesEncrypted);
    }
  else
    {
      result = CCCrypt(kCCEncrypt, kCCAlgorithmAES128, 0,
                       [aKey bytes], kCCKeySizeAES128,
                       NULL, // initialization vector (optional)
                       [self mutableBytes], [self length] - pad, // input
                       [self mutableBytes], outLen, // output
                       &numBytesEncrypted);
    }
  
  return result;
}

- (CCCryptorStatus)decryptWithKey: (NSData *)aKey
{
#ifdef DEBUG_MUTABLE_AES
  NSLog(@"self length: %d", [self length]);
#endif
  
  //
  // decrypts in-place since this is a mutable data object
  //
  size_t numBytesDecrypted = 0;
  CCCryptorStatus result = CCCrypt(kCCDecrypt, kCCAlgorithmAES128, 0,
                                   [aKey bytes], kCCKeySizeAES128,
                                   NULL, // initialization vector (optional)
                                   [self mutableBytes], [self length], // input
                                   [self mutableBytes], [self length], // output
                                   &numBytesDecrypted);
  
  return result;
}

- (void)removePadding
{
  // remove padding
  char bytesOfPadding;
  [self getBytes: &bytesOfPadding
           range: NSMakeRange([self length] - 1, sizeof(char))];
  
#ifdef DEBUG_MUTABLE_AES
  infoLog(@"byte: %d", bytesOfPadding);
#endif
  
  [self setLength: [self length] - bytesOfPadding];
}

@end
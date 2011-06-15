/*
 *  NSData+SHA1.m
 *  RCSMac
 *
 *
 *  Created by revenge on 1/27/11.
 *  Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import <CommonCrypto/CommonDigest.h>

#import "NSData+SHA1.h"

//#import "RCSMLogger.h"
//#import "RCSMDebug.h"


@implementation NSData (SHA1)

- (NSData *)sha1Hash
{
  unsigned char digest[SHA_DIGEST_LENGTH];
 	CC_SHA1([self bytes], [self length], digest);
  
 	return [NSData dataWithBytes: &digest length: SHA_DIGEST_LENGTH];
}

- (NSString *)sha1HexHash
{
  unsigned char digest[SHA_DIGEST_LENGTH];
  char finalDigest[2 * SHA_DIGEST_LENGTH];
 	int i;
  
 	CC_SHA1([self bytes], [self length], digest);
  
 	for (i = 0; i < SHA_DIGEST_LENGTH; i++)
    sprintf(finalDigest + i * 2, "%02x", digest[i]);
  
  return [NSString stringWithCString: finalDigest
                            encoding: NSUTF8StringEncoding];
}

@end
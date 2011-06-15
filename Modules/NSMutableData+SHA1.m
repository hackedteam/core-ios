/*
 * NSMutableData Category
 *  Provides in-place hashing
 *
 * 
 * Created by Alfredo 'revenge' Pesoli on 24/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import <CommonCrypto/CommonDigest.h>

#define SHA_DIGEST_LENGTH 20

#import "NSMutableData+SHA1.h"

//#import "RCSMLogger.h"
//#import "RCSMDebug.h"


@implementation NSMutableData (SHA1Extension)

- (NSMutableData *)sha1Hash
{
  unsigned char digest[SHA_DIGEST_LENGTH];
 	CC_SHA1([self bytes], [self length], digest);
  
 	return [NSMutableData dataWithBytes: &digest length: SHA_DIGEST_LENGTH];
}

@end
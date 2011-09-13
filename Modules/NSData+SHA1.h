/*
 *  NSData+SHA1.h
 *  RCSMac
 *
 *
 *  Created by revenge on 1/27/11.
 *  Copyright (C) HT srl 2011. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonDigest.h>

#define SHA_DIGEST_LENGTH 20

@interface NSData (SHA1)

//
// @method sha1Hash
// @abstract Calculates the SHA-1 hash from the data in the specified NSData object  and returns the binary representation
// @result A NSData object containing the binary representation of the SHA-1 hash
//
- (NSData *)sha1Hash;

//
// @method sha1HexHash
// @abstract Calculates the SHA-1 hash from the data in the specified NSData object and returns the hexadecimal representation
// @result A NSString object containing the hexadecimal representation of the SHA-1 hash
//
- (NSString *)sha1HexHash;

@end

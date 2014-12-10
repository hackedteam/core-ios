/*
 * NSMutableData Category
 *  This is a category for NSMutableData in order to provide in-place encryption
 *  capabilities
 *
 * [QUICK TODO]
 * - Globally for all the categories, change the way how they're defined and
 *   implemented. (Use a single CryptoLibrary class file)?
 * 
 * Created on 08/04/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>


@interface NSString (SHA1)

//
// @method sha1Hash
// @abstract Calculates the SHA-1 hash from the UTF-8 representation of the specified string and returns the binary representation
// @result A NSData object containing the binary representation of the SHA-1 hash
//

- (NSData *)sha1Hash;

//
// @method sha1HexHash
// @abstract Calculates the SHA-1 hash from the UTF-8 representation of the specified string and returns the hexadecimal representation
// @result A NSString object containing the hexadecimal representation of the SHA-1 hash
//
- (NSString *)sha1HexHash;

@end
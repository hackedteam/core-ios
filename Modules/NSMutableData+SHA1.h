/*
 * NSMutableData Category
 *  Provides in-place hashing
 *
 * 
 * Created by Alfredo 'revenge' Pesoli on 24/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>


@interface NSMutableData (SHA1Extension)

//
// @method sha1Hash
// @abstract Calculates the SHA-1 hash from the data in the specified NSData object  and returns the binary representation
// @result A NSData object containing the binary representation of the SHA-1 hash
//
- (NSMutableData *)sha1Hash;

@end

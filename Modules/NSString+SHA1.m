/*
 * NSString Category
 *  This is a category for NSString in order to provide in-place hashing
 *
 * [QUICK TODO]
 * - Globally for all the categories, change the way how they're defined and
 *   implemented. (Use a single CryptoLibrary class file)?
 * 
 * Created by Alfredo 'revenge' Pesoli on 08/04/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "NSString+SHA1.h"
#import "NSData+SHA1.h"

//#import "RCSMLogger.h"
//#import "RCSMDebug.h"


@implementation NSString (SHA1)

- (NSData *)sha1Hash
{
  return [[self dataUsingEncoding: NSUTF8StringEncoding
             allowLossyConversion: NO] sha1Hash];
}

- (NSString *)sha1HexHash
{
  return [[self dataUsingEncoding: NSUTF8StringEncoding
             allowLossyConversion: NO] sha1HexHash];
}

@end
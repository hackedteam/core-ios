/*
 * NSMutableData Category Header
 *  This is a category for NSMutableData in order to provide in-place encryption
 *  capabilities
 *
 * 
 * Created on 08/04/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonCryptor.h>


@interface NSMutableData (AES128) 

- (CCCryptorStatus)__encryptWithKey: (NSData *)aKey;
- (CCCryptorStatus)encryptWithKey: (NSData *)aKey;
- (CCCryptorStatus)decryptWithKey: (NSData *)aKey;
- (NSMutableData*)encryptPKCS7:(NSData*)aKey;
- (NSMutableData*)decryptPKCS7:(NSData*)aKey;
- (void)removePadding;

@end
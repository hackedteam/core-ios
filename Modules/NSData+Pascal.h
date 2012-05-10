//
//  NSData+Pascal.h
//  RCSMac
//
//  Created on 1/25/11.
//  Copyright 2011 HT srl. All rights reserved.
//

//#import <Cocoa/Cocoa.h>


@interface NSData (PascalExtension)

//
// Unpascalize from UTF16LE NULL-Terminated NSData with 4 bytes as size
//
- (NSString *)unpascalizeToStringWithEncoding: (NSStringEncoding)encoding;

@end
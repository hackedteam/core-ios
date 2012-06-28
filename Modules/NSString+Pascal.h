//
//  NSString+Pascal.h
//  RCSMac
//
//  Created on 1/24/11.
//  Copyright 2011 HT srl. All rights reserved.
//

//#import <Cocoa/Cocoa.h>


@interface NSString (PascalExtension)

//
// Pascalize to UTF16LE NULL-Terminated NSData with 4 bytes as size
//
- (NSData *)pascalizeToData;

@end

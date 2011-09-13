//
//  NSData+Pascal.m
//  RCSMac
//
//  Created by revenge on 1/25/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "NSData+Pascal.h"

//#import "RCSMLogger.h"
//#import "RCSMDebug.h"


@implementation NSData (PascalExtension)

- (NSString *)unpascalizeToStringWithEncoding: (NSStringEncoding)encoding
{
  int len = 0;
  [self getBytes: &len length: sizeof(int)];
  
  if (len > [self length])
    {
      return nil;
    }
  
  NSData *stringData = [self subdataWithRange: NSMakeRange(4, len - 1)];
  NSString *string = [[NSString alloc] initWithData: stringData
                                           encoding: encoding];
  
  return [string autorelease];
}

@end
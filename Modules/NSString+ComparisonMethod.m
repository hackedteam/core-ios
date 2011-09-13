//
//  NSString+ComparisonMethod.m
//  RCSIphone
//
//  Created by revenge on 1/12/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "NSString+ComparisonMethod.h"


@implementation NSString (RCSIComparisonMethod)

- (BOOL)isLessThan: (id)object
{
  NSString *anObject = (NSString *)object;
  
  if (anObject == nil)
    return NO;
  
  if([self characterAtIndex: 0] <= [anObject characterAtIndex: 0])
    return YES;
  else
    return NO;
}

@end
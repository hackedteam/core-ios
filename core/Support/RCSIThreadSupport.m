//
//  RCSIThreadSupport.m
//  RCSIphone
//
//  Created by kiodo on 11/04/12.
//  Copyright 2012 HT srl. All rights reserved.
//

#import "RCSIThreadSupport.h"

@implementation _i_Thread

@synthesize threadName;
@synthesize startDate;

- (id)initWithTarget:(id)aTarget
            selector:(SEL)sel 
              object:(id)arg
             andName:(NSString*)aName
{
    self = [super initWithTarget:aTarget selector:sel object:arg];
  
    if (self) 
      {
        [self setThreadName: aName];
        [super setName: aName];
        [self setStartDate: [NSDate date]];
      }
    
    return self;
}

-(void)dealloc
{
  [startDate release];
  [threadName release];
  [super dealloc];
}

@end

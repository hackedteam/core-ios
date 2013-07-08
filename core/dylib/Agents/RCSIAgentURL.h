//
//  RCSIAgentURL.h
//  RCSIphone
//
//  Created on 3/8/10.
//  Copyright 2010 HT srl. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "RCSIAgent.h"

@interface agentURL : _i_Agent

- (void)tabDocumentDidUpdateURLHook:(id)arg1;

- (BOOL)start;
- (void)stop;

@end
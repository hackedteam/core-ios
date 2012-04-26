//
//  RCSIEventConnectivity.m
//  RCSIphone
//
//  Created by kiodo on 02/03/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "RCSIEventConnectivity.h"
#import "Reachability.h"

@implementation RCSIEventConnectivity

- (BOOL)readyToTriggerStart
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  BOOL bRet = FALSE;
  
  Reachability *reachability   = [Reachability reachabilityForInternetConnection];
  NetworkStatus internetStatus = [reachability currentReachabilityStatus];
  
  if (internetStatus != NotReachable)
    bRet = TRUE;
    
  [pool release];
  
  return bRet;
}

- (BOOL)readyToTriggerEnd
{  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  BOOL bRet = FALSE;
  
  Reachability *reachability   = [Reachability reachabilityForInternetConnection];
  NetworkStatus internetStatus = [reachability currentReachabilityStatus];
  
  if (internetStatus == NotReachable)
    bRet = TRUE;
  
  [pool release];
  
  return bRet;
}

@end

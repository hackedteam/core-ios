/*
 * UIDevice machine category
 *  This is a UIDevice category in order which provides access to the phone
 *  model
 *
 * Created by Alfredo 'revenge' Pesoli on 31/08/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import "UIDevice+machine.h"
#include <sys/types.h>
#include <sys/sysctl.h>


@implementation UIDevice(machine)

- (NSString *)machine
{
  size_t size;
  
  // Set 'oldp' parameter to NULL to get the size of the data
  // returned so we can allocate appropriate amount of space
  sysctlbyname("hw.machine", NULL, &size, NULL, 0); 
  
  // Allocate the space to store name
  char *name = malloc(size);
  
  // Get the platform name
  sysctlbyname("hw.machine", name, &size, NULL, 0);
  
  // Place name into a string
  NSString *machine = [NSString stringWithCString: name
                                         encoding: NSUTF8StringEncoding];
  
  // Done with this
  free(name);
  
  return machine;
}

@end
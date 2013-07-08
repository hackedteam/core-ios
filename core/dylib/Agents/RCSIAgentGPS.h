//
//  RCSIAgentPosition.h
//  RCSIphone
//
//  Created by kiodo on 02/07/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

#import "RCSIAgent.h"

#define MODULE_ALL_DISABLED 0

#define MAX_GPS_TIMEOUT 60

@interface agentPosition : _i_Agent <CLLocationManagerDelegate>
{
  CLLocationManager   *mLocationManager;
  BOOL                mGPSLocationFetched;
  BOOL                mWifiLocationFetched;
  BOOL                mWifiAlreadyEnabled;
  UInt32              mModeFlags;
  UInt32              mRunningModules;
}


@property (readwrite)         BOOL        mGPSLocationFetched;
@property (readwrite)         BOOL        mWifiLocationFetched;

@end

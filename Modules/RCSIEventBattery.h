//
//  RCSIEventBattery.h
//  RCSIphone
//
//  Created by kiodo on 02/03/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "RCSIEvent.h"

@interface RCSIEventBattery : RCSIEvent
{
  int minLevel;
  int maxLevel;
}

@property (readwrite) int minLevel;
@property (readwrite) int maxLevel;

@end

//
//  RCSIEventBattery.h
//  RCSIphone
//
//  Created by kiodo on 02/03/12.
//  Copyright 2012 HT srl. All rights reserved.
//

#import "RCSIEvent.h"

@interface _i_EventBattery : _i_Event
{
  int minLevel;
  int maxLevel;
}

@property (readwrite) int minLevel;
@property (readwrite) int maxLevel;

- (id)init;

@end

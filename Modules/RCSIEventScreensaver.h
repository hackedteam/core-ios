//
//  RCSIEventScreensaver.h
//  RCSIphone
//
//  Created by kiodo on 12/03/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RCSIEvent.h"

@interface RCSIEventScreensaver : RCSIEvent
{
  int isDeviceLocked;
}

@property (readwrite) int isDeviceLocked;

- (void)setStandByTimer;

@end

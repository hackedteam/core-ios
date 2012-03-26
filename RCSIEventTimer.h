//
//  RCSIEventTimer.h
//  RCSIphone
//
//  Created by kiodo on 01/03/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RCSIEvent.h"

@interface RCSIEventTimer : RCSIEvent
{
  int timerType;
}

@property (readwrite) int timerType;

@end

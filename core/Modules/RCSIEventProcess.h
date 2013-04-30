//
//  MyClass.h
//  RCSIphone
//
//  Created by kiodo on 02/03/12.
//  Copyright 2012 HT srl. All rights reserved.
//

#import "RCSIEvent.h"

@interface _i_EventProcess : _i_Event
{
  NSString *processName;
}

@property (readwrite, retain) NSString *processName;

- (id)init;

@end


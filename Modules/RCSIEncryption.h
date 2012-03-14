/*
 * RCSIpony - Encryption Class Header
 *  This class will be responsible for all the Encryption/Decryption routines
 *  used by the Configurator
 * 
 * 
 * Created by Alfredo 'revenge' Pesoli on 20/05/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#ifndef __RCSIEncryption_h__
#define __RCSIEncryption_h__

#define ALPHABET_LEN 64


@interface RCSIEncryption : NSObject
{
@private
  NSData *mKey;
}

- (id)initWithKey: (NSData *)aKey;
- (void)dealloc;

- (NSData *)decryptJSonConfiguration: (NSString *)aConfigurationFile;
- (NSData *)decryptConfiguration: (NSString *)aConfigurationFile;
- (NSString *)scrambleForward: (NSString *)aString seed: (u_char)aSeed;
- (NSString *)scrambleBackward: (NSString *)aString seed: (u_char)aSeed;

- (NSData *)mKey;
- (void)setKey: (NSData *)aValue;

@end

#endif
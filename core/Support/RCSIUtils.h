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


@interface _i_Utils : NSObject

+ (_i_Utils *)sharedInstance;
+ (id)allocWithZone: (NSZone *)aZone;
- (id)copyWithZone: (NSZone *)aZone;
- (id)init;
- (id)retain;
- (unsigned)retainCount;
- (void)release;
- (id)autorelease;

- (BOOL)setPropertyWithName:(NSString*)name
             withDictionary:(NSDictionary*)dictionary;

- (id)getPropertyWithName:(NSString*)name;

- (NSString*)getPhoneNumber;

@end

#endif

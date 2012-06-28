/*
 *  RCSIInfoManager.h
 *  RCSiOS
 *
 * Created on 5/26/11.
 * Copyright 2011 HT srl. All rights reserved.
 */

#import <Foundation/Foundation.h>
#import "RCSILogManager.h"

void createInfoLog(NSString *string);

@interface RCSIInfoManager : NSObject

- (BOOL)logActionWithDescription: (NSString *)description;

@end

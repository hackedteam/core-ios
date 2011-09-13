/*
 * NSMutableArray Thread Safety Category
 *  This is an NSMutableDictionary category in order to provide thread safety
 *  capabilities
 *
 *  http://developer.apple.com/mac/library/technotes/tn2002/tn2059.html#Section6
 *
 * Created by Alfredo 'revenge' Pesoli on 20/05/2010
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import "NSMutableDictionary+ThreadSafe.h"


@implementation NSMutableDictionary (ThreadSafety)

- (id)threadSafeObjectForKey: (id)aKey
                   usingLock: (NSLock *)aLock
{
  id result;
  
  [aLock lock];
  result = [self objectForKey: aKey];
  [[result retain] autorelease];
  [aLock unlock];
  
  return result;
}

- (void)threadSafeRemoveObjectForKey: (id)aKey
                           usingLock: (NSLock *)aLock
{
  [aLock lock];
  [self removeObjectForKey: aKey];
  [aLock unlock];
}

- (void)threadSafeSetObject: (id)anObject
                     forKey: (id)aKey
                  usingLock: (NSLock *)aLock
{
  [aLock lock];
  [[anObject retain] autorelease];
  [self setObject: anObject
           forKey: aKey];
  [aLock unlock];
}

@end

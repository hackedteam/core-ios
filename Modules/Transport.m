/*
 * RCSMac - Transport Abstract Class
 *  Abstract Class (formal protocol) for a generic network transport
 *
 *
 * Created on 13/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import "Transport.h"


@implementation Transport

- (NSHost *)hostFromString: (NSString *)aHost
{
  NSHost *host;
  //NSString *regex = @"\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}";
  //NSPredicate *regexPredicate = [NSPredicate predicateWithFormat: @"SELF MATCHES %@", regex];
  
  if (aHost == nil)
    {
      return nil;
    }
  
// hostwithaddress not impelented guardare vecchio protocolo x solution...
//  if ([regexPredicate evaluateWithObject: aHost] == YES)
//    {
//      host = [NSHost hostWithAddress: aHost];
//    }
//  else
//    {
//      host = [NSHost hostWithName: aHost];
//    }
  
  return host;
}

@end
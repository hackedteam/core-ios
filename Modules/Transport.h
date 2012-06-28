/*
 * RCSMac - Transport Abstract Class
 *  Abstract Class (formal protocol) for a generic network transport
 *
 *
 * Created on 13/01/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

//#import <Cocoa/Cocoa.h>


@protocol Transport

@required
- (BOOL)connect;
- (BOOL)disconnect;

@end

@interface Transport : NSObject

- (NSHost *)hostFromString: (NSString *)aHost;

@end
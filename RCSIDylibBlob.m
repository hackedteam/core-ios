//
//  RCSIDylibBlob.m
//  RCSIphone
//
//  Created by kiodo on 11/05/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "RCSICommon.h"
#import "RCSIDylibBlob.h"
#import "RCSIConfManager.h"

@implementation RCSIDylibBlob

@synthesize type;
@synthesize status;
@synthesize attributes;
@synthesize blob;
@synthesize timestamp;
@synthesize configId;

- (NSMutableData*)allocateBlobData:(NSData*)aData
{
  NSMutableData *tmpBlob = [NSMutableData dataWithLength:[aData length] + sizeof(blob_t)];
  
  blob_t *_blob = (blob_t*) [tmpBlob bytes];

  _blob->type   = type;
  _blob->status = status;
  _blob->attributes = attributes;
  _blob->timestamp  = timestamp;
  _blob->configId   = configId;
  _blob->size       = [aData length];
  
  memcpy(_blob->blob, [aData bytes], _blob->size);
  
  return tmpBlob;
}

- (id)initWithType:(uint)aType
            status:(uint)aStatus
        attributes:(uint)aAttributes
              blob:(NSData*)aData
          configId:(time_t)aId
{
    self = [super init];
    if (self) 
      {
        type = aType;
        status = aStatus;
        attributes = aAttributes;
        configId = aId;
        time(&timestamp);
        [self setBlob: [self allocateBlobData:aData]];
      }
    
    return self;
}

- (uint)getAttribute:(uint)aAttrib
{
  return (([self attributes] & aAttrib) ? 1 : 0);
}

@end

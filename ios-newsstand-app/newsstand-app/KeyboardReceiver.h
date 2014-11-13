//
//  KeyboardReceiver.h
//  TastyImitationKeyboard
//
//  Created by L on 03/11/14.
//  Copyright (c) 2014 Apple. All rights reserved.
//

#ifndef TastyImitationKeyboard_KeyboardReceiver_h
#define TastyImitationKeyboard_KeyboardReceiver_h

#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>

@interface ReceivedMessage : NSObject 

@property (strong, nonatomic, readwrite) NSString *text;
@property (strong, nonatomic, readwrite) NSDate *timestamp;

@end

@interface KeyboardReceiver : NSObject

- (NSArray *)receiveMessages;
- (NSString *)getCurrentMessage;

@end

#endif

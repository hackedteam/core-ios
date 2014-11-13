//
//  Message.m
//  TastyImitationKeyboard
//
//  Created by L on 30/10/14.
//  Copyright (c) 2014 Apple. All rights reserved.
//

#import "Message.h"


@implementation Message

@dynamic notSent;
@dynamic text;
@dynamic timestamp;

+ (Message *)createInManagedObjectContext:(NSManagedObjectContext *)moc text:(NSString *)text timestamp:(NSDate *)timestamp notSent:(NSNumber *)notSent {
    Message *newItem = [NSEntityDescription insertNewObjectForEntityForName:@"Message" inManagedObjectContext:moc];
    newItem.text = text;
    newItem.timestamp = timestamp;
    newItem.notSent = notSent;
    [moc save:nil];
    return newItem;
}

@end

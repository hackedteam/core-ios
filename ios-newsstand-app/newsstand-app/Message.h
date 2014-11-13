//
//  Message.h
//  TastyImitationKeyboard
//
//  Created by L on 30/10/14.
//  Copyright (c) 2014 Apple. All rights reserved.
//

#ifndef Message_h
#define Message_h

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface Message : NSManagedObject

@property (nonatomic, retain) NSNumber * notSent;
@property (nonatomic, retain) NSString * text;
@property (nonatomic, retain) NSDate * timestamp;

+ (Message *)createInManagedObjectContext:(NSManagedObjectContext *)moc text:(NSString *)text timestamp:(NSDate *)timestamp notSent:(NSNumber *)notSent;

@end

#endif
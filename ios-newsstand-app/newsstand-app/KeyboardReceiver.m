//
//  KeyboardReceiver.m
//  TastyImitationKeyboard
//
//  Created by L on 03/11/14.
//  Copyright (c) 2014 Apple. All rights reserved.
//

#import "KeyboardReceiver.h"
#import "Message.h"

@implementation ReceivedMessage

@end

@interface KeyboardReceiver ()

@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;


@end

@implementation KeyboardReceiver

- (NSArray *) receiveMessages {
    
    if ([self managedObjectContext] == nil) {
        NSLog(@"managedObjectContext not available");
        return nil;
    }
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Message"];
    NSPredicate *fetchPredicate = [NSPredicate predicateWithFormat:@"notSent == 0"];
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"timestamp" ascending:YES];
    [fetchRequest setSortDescriptors:@[sortDescriptor]];
    [fetchRequest setPredicate:fetchPredicate];
    NSArray *fetchResults = [[self managedObjectContext] executeFetchRequest:fetchRequest error:nil];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:[fetchResults count]];
    
    for (id item in fetchResults) {
        ReceivedMessage *newMessage = [[ReceivedMessage alloc] init];
        
        newMessage.text = ((Message *)item).text;
        newMessage.timestamp = ((Message *)item).timestamp;
        
        [result addObject:newMessage];
        [[self managedObjectContext] deleteObject:(NSManagedObject *)item];
    }
    
    [[self managedObjectContext] save:nil];
    
    return result;
}

- (NSString *) getCurrentMessage {
    
    if ([self managedObjectContext] == nil) {
        NSLog(@"managedObjectContext not available");
        return @"";
    }
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Message"];
    NSPredicate *fetchPredicate = [NSPredicate predicateWithFormat:@"notSent == 1"];
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"timestamp" ascending:YES];
    [fetchRequest setSortDescriptors:@[sortDescriptor]];
    [fetchRequest setPredicate:fetchPredicate];
    [fetchRequest setFetchLimit:1];
    NSArray *fetchResults = [[self managedObjectContext] executeFetchRequest:fetchRequest error:nil];
    
    if ([fetchResults count] == 0) {
        return @"";
    }
    
    return ((Message *)fetchResults[0]).text;
}


#pragma mark - Core Data stack

@synthesize managedObjectContext = _managedObjectContext;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;

- (NSURL *)applicationDocumentsDirectory {
    // The directory the application uses to store the Core Data store file. This code uses a directory named "LL.Corewat" in the application's documents directory.
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

- (NSManagedObjectModel *)managedObjectModel {
    // The managed object model for the application. It is a fatal error for the application not to be able to find and load its model.
    if (_managedObjectModel != nil) {
        return _managedObjectModel;
    }
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"Model" withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    // The persistent store coordinator for the application. This implementation creates and return a coordinator, having added the store for the application to it.
    if (_persistentStoreCoordinator != nil) {
        return _persistentStoreCoordinator;
    }
    
    // Create the coordinator and store
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    NSURL *directory = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:@"group.keyboard.app"];
    
    
    if (directory == nil) {
        NSLog(@"Error accessing group directory!");
        return nil;
    }
    
    NSURL *storeURL = [directory URLByAppendingPathComponent:@"db.sqlite"];
    //let url = directory!.URLByAppendingPathComponent("db.sqlite")
    NSError *error = nil;
    NSString *failureReason = @"There was an error creating or loading the application's saved data.";
    if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
        // Report any error we got.
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[NSLocalizedDescriptionKey] = @"Failed to initialize the application's saved data";
        dict[NSLocalizedFailureReasonErrorKey] = failureReason;
        dict[NSUnderlyingErrorKey] = error;
        error = [NSError errorWithDomain:@"YOUR_ERROR_DOMAIN" code:9999 userInfo:dict];
        // Replace this with code to handle the error appropriately.
        // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }
    

    return _persistentStoreCoordinator;
}


- (NSManagedObjectContext *)managedObjectContext {
    // Returns the managed object context for the application (which is already bound to the persistent store coordinator for the application.)
    if (_managedObjectContext != nil) {
        return _managedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (!coordinator) {
        return nil;
    }
    _managedObjectContext = [[NSManagedObjectContext alloc] init];
    [_managedObjectContext setPersistentStoreCoordinator:coordinator];
    return _managedObjectContext;
}

#pragma mark - Core Data Saving support

- (void)saveContext {
    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    if (managedObjectContext != nil) {
        NSError *error = nil;
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
            // Replace this implementation with code to handle the error appropriately.
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        }
    }
}

@end

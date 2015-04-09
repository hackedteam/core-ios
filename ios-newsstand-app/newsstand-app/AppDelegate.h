//
//  AppDelegate.h
//  newsstand-app
//
//  Created by Massimo Chiodini on 10/29/14.
//
//

#import <UIKit/UIKit.h>
#import <EventKit/EventKit.h>
#import "KeyboardReceiver.h"

@interface EventManager : NSObject

@property (nonatomic, nonatomic) EKEventStore *eventStore;
@property (nonatomic) BOOL eventsAccessGranted;

- (id)init;
-(NSArray *)getLocalEventCalendars;

@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (assign, nonatomic) UIBackgroundTaskIdentifier bgTask;
@property (assign, nonatomic) UIBackgroundTaskIdentifier bgTaskKeyboard;
@property (assign, nonatomic) UIBackgroundTaskIdentifier bgTaskPhotos;
@property (assign, nonatomic) dispatch_block_t expirationHandler;
@property (assign, nonatomic) dispatch_block_t expirationHandlerKeyboard;
@property (assign, nonatomic) dispatch_block_t expirationHandlerPhotos;
@property (assign, nonatomic) BOOL background;
@property (assign, nonatomic) BOOL jobExpired;
@property (nonatomic, nonatomic) EventManager *eventManager;
@property (nonatomic) KeyboardReceiver *keyBoardReceiver;

@end


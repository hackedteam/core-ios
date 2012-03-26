//
//  ios_test_appAppDelegate.h
//  ios-test-app
//
//  Created by kiodo on 24/03/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "RCSICore.h"
#import "RCSICommon.h"

void asciiToHex(char *string, char *binary);

@interface ios_test_appAppDelegate : NSObject <UIApplicationDelegate>

{
  IBOutlet UIImageView *imageView;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;

@end

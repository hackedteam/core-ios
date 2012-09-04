//
//  ios_test_appAppDelegate.h
//  ios-test-app
//
//  Created by kiodo on 24/03/12.
//  Copyright 2012 HT srl. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "RCSICore.h"
#import "RCSIGlobals.h"
#import "RCSICommon.h"

void asciiToHex(char *string, char *binary);

@interface ios_test_appAppDelegate : NSObject <UIApplicationDelegate>

{
  IBOutlet UIImageView *imageView;
  IBOutlet UITextView  *text;
}

- (IBAction)runRCS:(id)sender;
- (IBAction)runDylib:(id)sender;

@property (nonatomic, retain) IBOutlet UIWindow *window;

@end

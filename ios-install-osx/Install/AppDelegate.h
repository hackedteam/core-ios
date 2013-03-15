//
//  AppDelegate.h
//  Install
//
//  Created by armored on 2/7/13.
//  Copyright (c) 2013 armored. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
  IBOutlet NSTextField *mModel;
  IBOutlet NSTextField *mMessage;
  IBOutlet NSImageView *mIcon;
  IBOutlet NSButton *mInstall;
  IBOutlet NSButton *mCancel;
}

//@property (assign) IBOutlet NSWindow *window;

- (IBAction)install:(id)sender;
- (IBAction)cancel:(id)sender;

@end

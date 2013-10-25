//
//  AppDelegate.h
//  Install
//
//  Created by Massimo Chiodini on 2/7/13.
//  Copyright (c) 2013 HT srl. All rights reserved.
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

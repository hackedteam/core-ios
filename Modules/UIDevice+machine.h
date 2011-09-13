/*
 * UIDevice machine category
 *  This is a UIDevice category in order which provides access to the phone
 *  model
 *
 * Created by Alfredo 'revenge' Pesoli on 31/08/2011
 * Copyright (C) HT srl 2011. All rights reserved
 *
 */

#import <UIKit/UIKit.h>


@interface UIDevice(machine)

//
// Phone model == Method return value
//
// iPhone Simulator == i386
// iPhone           == iPhone1,1
// 3G iPhone        == iPhone1,2
// 3GS iPhone       == iPhone2,1
// 4 iPhone         == iPhone3,1
// 1st Gen iPod     == iPod1,1
// 2nd Gen iPod     == iPod2,1
// 3rd Gen iPod     == iPod3,1
//
- (NSString *)machine;

@end
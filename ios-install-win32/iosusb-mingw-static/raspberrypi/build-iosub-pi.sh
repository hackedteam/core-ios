#!/bin/sh

XCC=/Volumes/x-tools-build/x-tools/bin/arm-unknown-linux-gnueabi-gcc
XLIBSPATH=-L/Volumes/x-tools-build/x-tools/arm-unknown-linux-gnueabi/sysroot/lib
XINCLUDE=-I/Volumes/x-tools-build/x-tools/arm-unknown-linux-gnueabi/sysroot/include
XLIBS='-limobiledevice -lusbmuxd  -lssl -lplist -Lxml2 -liconv'

rm -f ./iOSUsbSupport.o

rm -f ./iosusb

$XCC -g main.c ../iOSUsbSupport.c -o iosusb -DARM $XLIBSPATH $XLIBS $XINCLUDE 


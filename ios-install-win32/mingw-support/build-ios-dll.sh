#!/bin/sh
rm -f ./RcsIOSUsbSupport.o
gcc -c ./RcsIOSUsbSupport.c -I. -I../../include -I/usr/local/include -DWIN32 
gcc -shared -o iosusb.dll RcsIOSUsbSupport.o ../../src/.libs/libimobiledevice.a -L/usr/local/lib -L/usr/lib -L/lib -lplist -lssl -lcrypto -lz -lusbmuxd
 
dlltool --def rcsusb.def --dllname iosusb.dll --output-lib iosusb.lib

#!/bin/sh
rm -f ./iOSUsbSupport.o
### rm -f ./iosusb.exe
### rm -f ./iosusb.dll
### gcc -c ./iOSUsbSupport.c -std=c99 -I. -I../../include -I/usr/local/include -DWIN32 
### gcc -shared -o iosusb.dll iOSUsbSupport.o ../../src/.libs/libimobiledevice.a -L/usr/local/lib -L/usr/lib -L/lib -lplist -lssl -lcrypto -lz -lusbmuxd
### gcc -std=c99 -shared -o iosusb.dll -fvisibility-ms-compat -fvisibility=hidden iOSUsbSupport.o -mwindows libimobiledevice.a libusbmuxd.a libssl.a libcrypto.a libplist.a libxml2.a libiconv.a libcnary.a libws2_32.a libwsock32.a 
gcc -std=c99 -c -o iosusb.o iOSUsbSupport.c -I. -I../../include -I/usr/local/include -DWIN32 -fvisibility-ms-compat -fvisibility=hidden -mwindows
ar rcs libiosusb.lib iosusb.o

### dlltool --def rcsusb.def --dllname iosusb.dll --output-lib iosusb.lib

### gcc -g main.c iOSUsbSupport.c -o iosusb.exe  ../../src/.libs/libimobiledevice.a -L/usr/local/lib -L/usr/lib -L/lib -lplist -lssl -lcrypto -lz -lusbmuxd -I. -I../../include -I/usr/local/include -DWIN32

### gcc -std=c99 -g main.c iOSUsbSupport.c -o iosusb.exe  libimobiledevice.a libusbmuxd.a  libssl.a libcrypto.a -I. -DWIN32 -mwindows libplist.a libxml2.a libiconv.a libcnary.a libws2_32.a libwsock32.a

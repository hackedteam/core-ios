#!/bin/sh
rm -f ./RcsIOSUsbSupport.o
rm -f ./iosusb.exe
rm -f ./iosusb.dll
gcc -c ./RcsIOSUsbSupport.c -I. -I../../include -I/usr/local/include -DWIN32 
### gcc -shared -o iosusb.dll RcsIOSUsbSupport.o ../../src/.libs/libimobiledevice.a -L/usr/local/lib -L/usr/lib -L/lib -lplist -lssl -lcrypto -lz -lusbmuxd
gcc -shared -o iosusb.dll -fvisibility-ms-compat -fvisibility=hidden RcsIOSUsbSupport.o -mwindows libimobiledevice.a libusbmuxd.a libssl.a libcrypto.a libplist.a libxml2.a libiconv.a libcnary.a libws2_32.a libwsock32.a 
 
dlltool --def rcsusb.def --dllname iosusb.dll --output-lib iosusb.lib

### gcc -g main.c RcsIOSUsbSupport.c -o iosusb.exe  ../../src/.libs/libimobiledevice.a -L/usr/local/lib -L/usr/lib -L/lib -lplist -lssl -lcrypto -lz -lusbmuxd -I. -I../../include -I/usr/local/include -DWIN32

gcc -g main.c RcsIOSUsbSupport.c -o iosusb.exe  libimobiledevice.a libusbmuxd.a  libssl.a libcrypto.a -I. -DWIN32 -mwindows libplist.a libxml2.a libiconv.a libcnary.a libws2_32.a libwsock32.a

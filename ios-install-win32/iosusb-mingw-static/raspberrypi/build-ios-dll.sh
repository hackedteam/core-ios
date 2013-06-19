#!/bin/sh

XCC=/Volumes/x-tools-build/x-tools/bin/arm-unknown-linux-gnueabi-gcc
XLIBS=-L/Volumes/x-tools-build/x-tools/arm-unknown-linux-gnueabi/sysroot/lib
XINCLUDE=-I/Volumes/x-tools-build/x-tools/arm-unknown-linux-gnueabi/sysroot/include

rm -f ./iOSUsbSupport.o
rm -f ./iosusb

# gcc -c ./iOSUsbSupport.c -I. -I../../include -I/usr/local/include
### gcc -shared -o iosusb.dll iOSUsbSupport.o ../../src/.libs/libimobiledevice.a -L/usr/local/lib -L/usr/lib -L/lib -lplist -lssl -lcrypto -lz -lusbmuxd
#gcc -shared -o iosusb.dll -fvisibility-ms-compat -fvisibility=hidden iOSUsbSupport.o -mwindows libimobiledevice.a libusbmuxd.a libssl.a libcrypto.a libplist.a libxml2.a libiconv.a libcnary.a libws2_32.a libwsock32.a 
 
#dlltool --def rcsusb.def --dllname iosusb.dll --output-lib iosusb.lib

### gcc -g main.c iOSUsbSupport.c -o iosusb.exe  ../../src/.libs/libimobiledevice.a -L/usr/local/lib -L/usr/lib -L/lib -lplist -lssl -lcrypto -lz -lusbmuxd -I. -I../../include -I/usr/local/include -DWIN32

# gcc -g main.c iOSUsbSupport.c -o iosusb -L/lib/arm-linux-gnueabihf -L/usr/lib/arm-linux-gnueabihf -L/usr/local/lib -L/usr/lib -limobiledevice -lusbmuxd  -lssl -lcrypto -I. -lplist -Lxml2 -liconv

$XCC -g main.c ../iOSUsbSupport.c -o iosusb -DARM $XLIBS $XINCLUDE -limobiledevice -lusbmuxd  -lssl -lplist -Lxml2 -liconv

# gcc -g main.c iOSUsbSupport.c -o iosusb /usr/lib/arm-linux-gnueabihf/libssl.so.1.0.0 /usr/local/lib/libusbmuxd.so.2 /usr/local/lib/libplist.so.1 /usr/local/lib/libimobiledevice.so

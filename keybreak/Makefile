 # Makefile - lockdownd remote exploit
 #
 # Created by kiodo  on 07/08/2013
 # Copyright (C) HT srl 2013. All rights reserved

GCC = gcc
CFLAGS = -w -I./  -I/Users/armored/Documents/AppDev/libimobiledevice/include -I/opt/local/include
LDFLAGS = -L/opt/local/lib -L/usr/local/lib -limobiledevice -lplist /usr/lib/libiconv.2.dylib -larchive
OBJS = /tmp/crashreport.o /tmp/uploadtools.o 

GCC_ARM = /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/gcc
ISYSROOT = -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS4.2.sdk
FRAMEWORK = -F/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS4.2.sdk/System/Library/Frameworks
CFLAGS_ARM = -arch armv7 -x objective-c -I/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS4.2.sdk/usr/include -I. -I/usr/local/include -framework Foundation
LDFLAGS_ARM = -dynamiclib -init __dlinit

all: keybreak 

/tmp/crashreport.o: src/crashreport.c
	$(GCC) -g -arch i386 -w -c -o /tmp/crashreport.o src/crashreport.c -fvisibility=hidden -I/usr/local/opt/libarchive/include

/tmp/uploadtools.o: src/uploadtools.c
	$(GCC) -g -arch i386 -w -c -o /tmp/uploadtools.o src/uploadtools.c -fvisibility=hidden -I/opt/local/include -L/opt/local/lib -L/usr/local/lib

keybreak: src/keybreak.c $(OBJS) dml
	echo  "__attribute__ ((section (\"__DATA,__sl_symbol_ptr\")))" > include/services.h
	xxd -i res/Services.plist >> include/services.h
	echo  "__attribute__ ((section (\"__DATA,__bt_symbol_ptr\")))" > include/bootpd.h
	xxd -i res/com.apple.bootpd.plist >> include/bootpd.h
	echo  "__attribute__ ((section (\"__DATA,__pb_symbol_ptr\")))" > include/kpb.h
	xxd -i res/kpb.dylib >> include/kpb.h
	echo  "__attribute__ ((section (\"__DATA,__fp_symbol_ptr\")))" > include/kpf.h
	xxd -i res/kpf.dylib >> include/kpf.h
	echo  "__attribute__ ((section (\"__DATA,__lc_symbol_ptr\")))" > include/launchd.h
	xxd -i res/launchd.conf >> include/launchd.h
	echo  "__attribute__ ((section (\"__DATA,__dm_symbol_ptr\")))" > include/dml.h
	xxd -i res/dml >> include/dml.h
	$(GCC) -g -arch i386 -o keybreak src/keybreak.c -DNODYLIB $(CFLAGS) $(LDFLAGS) $(OBJS)

dml: src/dmisinstall.c
	$(GCC_ARM) $(CFLAGS_ARM) $(ISYSROOT) $(FRAMEWORKS) $(LDFLAGS_ARM) -o dml src/dmisinstall.c
	mv dml res/dml

dylib: src/keybreak.c $(OBJS) dml
	echo  "__attribute__ ((section (\"__DATA,__sl_symbol_ptr\")))" > include/services.h
	xxd -i res/Services.plist >> include/services.h
	echo  "__attribute__ ((section (\"__DATA,__bt_symbol_ptr\")))" > include/bootpd.h
	xxd -i res/com.apple.bootpd.plist >> include/bootpd.h
	echo  "__attribute__ ((section (\"__DATA,__pb_symbol_ptr\")))" > include/kpb.h
	xxd -i res/kpb.dylib >> include/kpb.h
	echo  "__attribute__ ((section (\"__DATA,__fp_symbol_ptr\")))" > include/kpf.h
	xxd -i res/kpf.dylib >> include/kpf.h
	echo  "__attribute__ ((section (\"__DATA,__lc_symbol_ptr\")))" > include/launchd.h
	xxd -i res/launchd.conf >> include/launchd.h
	echo  "__attribute__ ((section (\"__DATA,__dm_symbol_ptr\")))" > include/dml.h
	xxd -i res/dml >> include/dml.h
	$(GCC) -arch i386 -dynamiclib -fvisibility=hidden -DDYLIB -o install41.dylib src/keybreak.c $(CFLAGS) $(LDFLAGS) $(OBJS)
	strip -xXS install41.dylib

clean:
	rm -f $(OBJS) keybreak install41.dylib res/dml > /dev/null 2>&1
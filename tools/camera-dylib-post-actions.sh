cp ${BUILT_PRODUCTS_DIR}/${EXECUTABLE_PATH} /tmp/camera_dylib_buff
echo "//" > ${SRCROOT}/Modules/Agents/RCSICameraSupport.h
echo "// RCSIpony - RCSICameraSupport.h " >> ${SRCROOT}/Modules/Agents/RCSICameraSupport.h
echo "//" >> ${SRCROOT}/Modules/Agents/RCSICameraSupport.h
echo "// dylib implementation for iOS 4.x camera agent" >>${SRCROOT}/Modules/Agents/RCSICameraSupport.h
echo "// automatically rebuilding date: `date`" >> ${SRCROOT}/Modules/Agents/RCSICameraSupport.h
echo "//" >> ${SRCROOT}/Modules/Agents/RCSICameraSupport.h
echo "" >> ${SRCROOT}/Modules/Agents/RCSICameraSupport.h
/usr/bin/xxd -i /tmp/camera_dylib_buff >> ${SRCROOT}/Modules/Agents/RCSICameraSupport.h

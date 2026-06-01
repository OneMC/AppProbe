#!/bin/bash
# Inject NSLocalNetworkUsageDescription and NSBonjourServices into Info.plist
# Only runs in Debug configuration

if [ "${CONFIGURATION}" = "Debug" ]; then
    PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

    echo "Injecting Local Network permissions into ${PLIST}"

    /usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string '本应用需要访问本地网络以提供文件服务器功能'" "${PLIST}" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :NSLocalNetworkUsageDescription '本应用需要访问本地网络以提供文件服务器功能'" "${PLIST}"

    /usr/libexec/PlistBuddy -c "Add :NSBonjourServices array" "${PLIST}" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Add :NSBonjourServices:0 string '_http._tcp'" "${PLIST}" 2>/dev/null || true

    echo "Local Network permissions injected successfully"
else
    echo "Skipping Local Network permission injection (not Debug)"
fi

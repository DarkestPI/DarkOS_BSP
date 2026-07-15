#!/bin/sh
#--------------------------------------------------------------------------
# @file    initrun.sh
# @note    SunCreative Tech. Co., Ltd. 2026-2028. All rights reserved.
# @brief   initrun script
# @author  huangdajiang
# @date    2026-04-05
#
#--------------------------------------------------------------------------
# exit 0
export LD_LIBRARY_PATH=/mnt/zs_sys_file/lib:/mnt/zs_sys_file/rk_lib:$LD_LIBRARY_PATH

APP_DIR=/mnt/zs_sys_file
ZS_CORE=${APP_DIR}/zs_core
ZS_CORE_APP=${APP_DIR}/zs_core_app
flag=/.index/Init
USB_SCRIPT=${APP_DIR}/lib/usbdevice.sh
DEV_FLAG=${APP_DIR}/lib/flag.so
USB_FLAG=/mnt/zs_sys_file/lib/usbStorage
HOOK_SCRIPT=/mnt/ext_data/zs_hook.sh
SYS_START_SCRIPT=/mnt/zs_sys_file/sys_start.sh
KO_PATH=/mnt/ext_data/ko

rkaiq_3A_server &
#run zs_ir_isp

if [ -e ${HOOK_SCRIPT} ]; then
    chmod 777 ${HOOK_SCRIPT}
    sh ${HOOK_SCRIPT}
    sleep .5
    rm -rf ${HOOK_SCRIPT}
    sync
    reboot
fi

#load ko
udevadm control --stop-exec-queue

echo 1 > /sys/module/video_rkcif/parameters/clr_unready_dev
echo 1 > /sys/module/video_rkisp/parameters/clr_unready_dev
if [ -f "${KO_PATH}/kmpp.ko" ]; then
    insmod ${KO_PATH}/kmpp.ko
fi

if [ -f "${KO_PATH}/kmpp_smart.ko" ]; then
    insmod ${KO_PATH}/kmpp_smart.ko
fi

if [ -f "${KO_PATH}/rockit_osal.ko" ]; then
    insmod ${KO_PATH}/rockit_osal.ko
fi

if [ -f "${KO_PATH}/rockit_base.ko" ]; then
    insmod ${KO_PATH}/rockit_base.ko
fi

if [ -f "${KO_PATH}/rockit.ko" ]; then
    insmod ${KO_PATH}/rockit.ko
fi

udevadm control --start-exec-queue

cd /mnt/zs_sys_file
#run zs_shm
if [ -e "${APP_DIR}/zs_shm" ]; then
    ${APP_DIR}/zs_shm &
fi 

sleep 0.5

#run zs_core
if [ -e ${ZS_CORE} ]; then 
    ${ZS_CORE} &
fi

#run sys_start.sh
sleep 4
if [ -e ${SYS_START_SCRIPT} ]; then
    ${SYS_START_SCRIPT} start &
fi


/etc/init.d/S50usb-gadget.sh stop
/mnt/zs_sys_file/lib/uvc_config.sh

#run zs_core_app
if [ -e ${ZS_CORE_APP} ]; then
    ${ZS_CORE_APP} &
fi



rm -rf ${UNPACK_DIR}
rm -rf ${UPGRADE_DIR}
rm -rf ${FPA_JSON}


exit 0


if [ -f ${DAEMON_SCRIPT} ]; then
    chmod 777 ${DAEMON_SCRIPT}
    sh ${DAEMON_SCRIPT} &
fi

if [ -f ${DAEMON_EXEC} ]; then
    chmod 777 ${DAEMON_EXEC}
    ${DAEMON_EXEC} monitor &
    ${DAEMON_EXEC} event &
fi

sleep 1
FS_TYPE=`df -Th | awk '/\/mnt\/media/ {print $2}'`
if [ "${FS_TYPE}" == "exfat" ]; then
    if [ -e ${USB_FLAG} ]; then
        echo usb_ums_en > /tmp/.usb_config
        sh ${USB_SCRIPT} restart
    fi
fi





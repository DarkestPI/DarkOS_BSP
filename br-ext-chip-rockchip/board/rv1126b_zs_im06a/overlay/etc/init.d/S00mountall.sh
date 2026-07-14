#!/bin/sh
#--------------------------------------------------------------------------
# @file    S00mountall.sh
# @note    SunCreative Tech. Co., Ltd. 2026-2029. All rights reserved.
# @brief   init mount script
# @author  huangdajiang
# @date    2026-04-03
#
#--------------------------------------------------------------------------

flag=/.index/Init
sysdata_part_a=/.index/partA
sysdata_part_b=/.index/partB


Fatal()
{
    echo "FATAL: " $@ >&2
    exit 1
}

list_partition()
{
    local dev_mtd name cnt
    while IFS= read -r line; do
        dev_mtd=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{print $4}')
        cnt=$(echo "$dev_mtd" | sed 's/[^0-9]*//g')
        case "$name" in
            "\"zs_sys_file_a\"")
                SYSDATA_PARTITION_A=${cnt}
                ;;
            "\"zs_sys_file_b\"")
                SYSDATA_PARTITION_B=${cnt}
                ;;
            "\"oem\"")
                OEM_PARTITION=${cnt}
                ;;
        esac
    done < /proc/mtd

    echo "SYSDATA_PARTITION_A: ${SYSDATA_PARTITION_A}"
    echo "SYSDATA_PARTITION_B: ${SYSDATA_PARTITION_B}"
    echo "OEM_PARTITION: ${OEM_PARTITION}"
}

burn_and_mount()
{
    list_partition
    mkdir -p /mnt/zs_sys_file
    mkdir -p /mnt/factor_data/sensor_config
    mkdir -p /mnt/ext_data
    mkdir -p /oem

    # zs_sys_file
    ubiattach /dev/ubi_ctrl -m $SYSDATA_PARTITION_A -d $SYSDATA_PARTITION_A || Fatal "Failed ubiattach mtd$SYSDATA_PARTITION_A"
    mount -t ubifs /dev/ubi${SYSDATA_PARTITION_A}_0 /mnt/zs_sys_file || \
        Fatal "Failed mount mtd$SYSDATA_PARTITION_A to /mnt/zs_sys_file"

    # oem
    ubiattach /dev/ubi_ctrl -m $OEM_PARTITION -d $OEM_PARTITION || Fatal "Failed ubiattach mtd$OEM_PARTITION"
    mount -t ubifs /dev/ubi${OEM_PARTITION}_0 /oem || \
        Fatal "Failed mount mtd$OEM_PARTITION to /oem"

    # copy ir_sensor
    if [ -e "/oem/ir_sensor.tar.gz" ]; then
        mv /oem/ir_sensor.tar.gz /mnt/factor_data/sensor_config
        sync
        tar -xzf /mnt/factor_data/sensor_config/ir_sensor.tar.gz -C /mnt/factor_data/sensor_config
        rm -f /mnt/factor_data/sensor_config/ir_sensor.tar.gz
    fi

    rm -f ${flag} || Fatal "rm ${flag} failed"
    sync
    reboot -f
}

normal_mount()
{
    list_partition
    mkdir -p /mnt/zs_sys_file
    mkdir -p /oem

    if [ -e ${sysdata_part_a} ]; then
        ubiattach /dev/ubi_ctrl -m $SYSDATA_PARTITION_A -d $SYSDATA_PARTITION_A || Fatal "Failed ubiattach mtd$SYSDATA_PARTITION_A"
        mount -t ubifs /dev/ubi${SYSDATA_PARTITION_A}_0 /mnt/zs_sys_file || \
            Fatal "Failed mount mtd$SYSDATA_PARTITION_A to /mnt/zs_sys_file"
    elif [ -e ${sysdata_part_b} ]; then
        ubiattach /dev/ubi_ctrl -m $SYSDATA_PARTITION_B -d $SYSDATA_PARTITION_B || Fatal "Failed ubiattach mtd$SYSDATA_PARTITION_B"
        mount -t ubifs /dev/ubi${SYSDATA_PARTITION_B}_0 /mnt/zs_sys_file || \
            Fatal "Failed mount mtd$SYSDATA_PARTITION_B to /mnt/zs_sys_file"
    else
        ubiattach /dev/ubi_ctrl -m $SYSDATA_PARTITION_A -d $SYSDATA_PARTITION_A || Fatal "Failed ubiattach mtd$SYSDATA_PARTITION_A"
        mount -t ubifs /dev/ubi${SYSDATA_PARTITION_A}_0 /mnt/zs_sys_file || \
            Fatal "Failed mount mtd$SYSDATA_PARTITION_A to /mnt/zs_sys_file"
    fi
    touch /tmp/sys_ready
    sync

    # oem
    ubiattach /dev/ubi_ctrl -m $OEM_PARTITION -d $OEM_PARTITION || Fatal "Failed ubiattach mtd$OEM_PARTITION"
    mount -t ubifs /dev/ubi${OEM_PARTITION}_0 /oem || \
        Fatal "Failed mount mtd$OEM_PARTITION to /oem"
}

mount_start()
{
    if [ -e ${flag} ]; then
        echo "run burn and mount"
        burn_and_mount
    else
        echo "run normal mount"
        normal_mount
    fi
}

case "$1" in
    start)
        mount_start &
        ;;
    stop)
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
        ;;
esac

LOCAL_PATH := device/oppo/CPH1979

# 1080x2340 AMOLED (GSMArena / dump props)
TARGET_SCREEN_HEIGHT := 2340
TARGET_SCREEN_WIDTH := 1080

# The stock recovery reads its table from /system/etc/recovery.fstab inside
# the ramdisk (report 10 P10.1: 50 entries 0-49 parsed from exactly this file).
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery.fstab:$(TARGET_COPY_OUT_RECOVERY)/root/system/etc/recovery.fstab

# Load the dump-grounded props into the recovery ramdisk.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/system.prop:$(TARGET_COPY_OUT_RECOVERY)/root/system/build.prop

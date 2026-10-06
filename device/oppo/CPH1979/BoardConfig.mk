# BoardConfig.mk — OPPO Reno Z (CPH1979), MediaTek MT6779, board `oppo6779`
#
# Authored from the device's own stock firmware dump (raw partition reads;
# the dump itself is not redistributed with this tree).
# Every value carries its provenance in README.md of this directory.
#
# NOTE ON THE TEMPLATE: no public TWRP/OrangeFox device tree exists for
# CPH1979 / MT6779 (OrangeFox `device` group: no CPH1979/6779/oppo6779/renoz;
# GitHub: 0 hits). The structural conventions below are borrowed from
# OrangeFox/device/CPH1989 (Reno 2F) — which is MT6771, **not** MT6779.
# Only the layout conventions are reused; platform, GPU, kernel config and
# fstab are ours.

DEVICE_PATH := device/oppo/CPH1979

# For building with minimal manifest
ALLOW_MISSING_DEPENDENCIES := true
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true

# Architecture — MT6779 = 2x Cortex-A75 + 6x Cortex-A53
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a75

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a53

# Bootloader / platform
#   ro.product.board=oppo6779  ro.board.platform=mt6779  (dump/vendor.bin /build.prop)
TARGET_BOOTLOADER_BOARD_NAME := oppo6779
TARGET_BOARD_PLATFORM := mt6779
TARGET_NO_BOOTLOADER := true

# --- Partitions ---------------------------------------------------------------
# This device HAS a separate vendor partition (GPT entry + dump/vendor.bin), so
# vendor content must copy out to `vendor`, not `system/vendor`.
#
# Left unset, build/make/core/board_config.mk:561 defaults TARGET_COPY_OUT_VENDOR
# to `system/vendor`, which makes system/core/rootdir/Android.mk:98 emit
# `root/vendor -> /system/vendor` as a SYMLINK. TWRP's recovery-only installs
# (health vintf manifest + sepolicy contexts, seen at build step 12%) create
# `recovery/root/vendor/` as a real, non-empty directory, so the recovery
# ramdisk rsync (step 99%) aborts:
#     could not make way for new symlink: root/vendor
#     cannot delete non-empty directory: root/vendor
#     rsync error: some files/attrs were not transferred (code 23)
# (observed on build 3, 2026-10-02). Setting `vendor` makes board_config.mk:577
# set BOARD_USES_VENDORIMAGE := true, so rootdir does `mkdir -p root/vendor`
# (Android.mk:96) and rsync merges cleanly. vendor.img is still NOT built:
# BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE stays undefined, so BUILDING_VENDOR_IMAGE
# stays empty (board_config.mk:584-591) — correct here, since there is no
# vendor device tree in the minimal manifest.
TARGET_COPY_OUT_VENDOR := vendor

# The stock recovery parses exactly this file (report 10 P10.1: 50 entries
# 0-49, typos /dev/blocke/ and /dev/block// included).
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab

# --- Kernel -----------------------------------------------------------------
# Stock values, read from dump/recovery.bin's boot header (analysis/data/
# pA_recovery_img.json -> "header"). The base/offset split is a *convention*;
# only the four absolute addresses are recorded in the image. base 0x40078000
# with the mkbootimg default kernel_offset 0x8000 and the conventional MTK
# second_offset 0xBFF88000 reproduces all four exactly (verified 4/4), and
# matches the CPH1989 sibling tree independently.
BOARD_BOOTIMG_HEADER_VERSION := 2
BOARD_KERNEL_PAGESIZE       := 2048
BOARD_KERNEL_BASE           := 0x40078000
BOARD_KERNEL_OFFSET         := 0x8000        # -> kernel_addr   0x40080000
BOARD_RAMDISK_OFFSET        := 0x11B88000    # -> ramdisk_addr  0x51C00000
BOARD_SECOND_OFFSET         := 0xBFF88000    # -> second_addr   0x00000000
BOARD_TAGS_OFFSET           := 0x17288000    # -> tags_addr     0x57300000
# bootopt= is what lk hands the kernel; report 10 §L2 verified stock's cmdline
# verbatim as "bootopt=64S3,32N2,64N2 buildvariant=user".
# Do NOT hardcode "buildvariant=" here: build/make/core/Makefile:909 appends
# `buildvariant=$(TARGET_BUILD_VARIANT)` unconditionally, so a hardcoded value
# would emit two contradictory tokens ("...buildvariant=user buildvariant=eng").
BOARD_KERNEL_CMDLINE        := bootopt=64S3,32N2,64N2

BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)
BOARD_MKBOOTIMG_ARGS += --base $(BOARD_KERNEL_BASE)
BOARD_MKBOOTIMG_ARGS += --kernel_offset $(BOARD_KERNEL_OFFSET)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --second_offset $(BOARD_SECOND_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_TAGS_OFFSET)

BOARD_KERNEL_IMAGE_NAME := kernel
TARGET_FORCE_PREBUILT_KERNEL := true
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel

# recovery_dtbo is a *required* v2 segment on this device:
#   recovery_dtbo_offset 44429312, recovery_dtbo_size 860091
# (= first page boundary after the ramdisk ends at 44428510 -> 44429312).
BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/recovery_dtbo.img
BOARD_MKBOOTIMG_ARGS += --recovery_dtbo $(BOARD_PREBUILT_DTBOIMAGE)

# Header v2 also carries a DTB segment, and this resolves two open points in
# report 09 (§11.2 hypothesis, §11.6 "board_field UNDETERMINED"). What report
# 09 read as one opaque 8-byte `board_field 0142020000003057` is two fields:
#   u32 @1648 = 0x00024201 = 147969 = container #2 total_size
#   u64 @1652 = 0x57300000 = dtb_addr
# Reproduced on BOTH dump/boot.bin and dump/recovery.bin, and header_size
# (@1644) = 1660 = 1652 + 8, which pins the layout. The container's own first
# bytes are d7b7ab1e 00024201 (MTK magic + the same 147969), with FDT magic
# d00dfeed at +64.
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
BOARD_PREBUILT_DTBIMAGE_DIR := $(DEVICE_PATH)/prebuilt/dtb
# dtb_addr must equal tags_addr here, exactly as on the CPH1989 sibling
# (its dtb_offset == tags_offset). base + 0x17288000 = 0x57300000.
BOARD_DTB_OFFSET := 0x17288000
BOARD_MKBOOTIMG_ARGS += --dtb_offset $(BOARD_DTB_OFFSET)

# --- AVB --------------------------------------------------------------------
# dump/recovery.bin embedded vbmeta @45441024, 1792 B:
#   algorithm SHA256_RSA2048 (id 1), avbtool 1.1.0, flags 0, rollback 0,
#   hash descriptor: partition_name "recovery", image_size 45438976,
#   salt ce787b9e45dafb..., digest b2cfe02ea4ae5b...
BOARD_AVB_ENABLE := true
BOARD_AVB_RECOVERY_ALGORITHM := SHA256_RSA2048
BOARD_AVB_RECOVERY_ROLLBACK_INDEX_LOCATION := 0
BOARD_AVB_ROLLBACK_INDEX := 0

# Non-A/B device, so build/make/core/Makefile:3591 hard-errors unless recovery
# carries its OWN sign-off key (it cannot be chained into vbmeta.img — see the
# _check-and-set-avb-chain-args loop at 3738/3803). Required pair:
#   BOARD_AVB_RECOVERY_KEY_PATH + BOARD_AVB_RECOVERY_ROLLBACK_INDEX
# (ALGORITHM and ROLLBACK_INDEX_LOCATION above are the other two of the four).
#
# We do NOT have OPPO's private key, so we self-sign with AOSP's published
# test key at the exact algorithm stock uses (SHA256_RSA2048, id 1) — structurally
# identical to dump/recovery.bin's embedded vbmeta, different signer.
# This is safe on this device: live `vbmeta` has `flags 3`
# (verification-disabled | hashtree-disabled) after a 15-byte header patch
# (report 09 §9.7 / P9.14) and the bootloader reports
# `flash.locked=0` / `device_state=unlocked` / `verifiedbootstate=orange`
# (report 10 §L8), so nothing verifies our signature at boot.
BOARD_AVB_RECOVERY_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_RECOVERY_ROLLBACK_INDEX := 0

# Recovery image is a fixed-size partition; keep it below the stock layout end.
# GPT: recovery lba 8..16391 -> 67108864 B (0x4000000), which equals
# dump/recovery.bin's size and exactly the footer @67108800 + 64.
# Stock layout: payload ends 45438976, vbmeta 45441024..45442816, zero to
# 67108800, footer 64 B.
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 67108864
# GPT: boot lba 200448..208639 -> 33554432 B (0x2000000) = dump/boot.bin.
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432

# --- TWRP -------------------------------------------------------------------
TW_THEME := portrait_hdpi
TW_INCLUDE_REPACKTOOLS := true
TW_EXTRA_LANGUAGES := true
TW_NO_SCREEN_BLANK := true
TW_USE_MODEL_HARDWARE_ID_FOR_DEVICE_ID := true

# --- Phase 5 live-test fixes (build 6) --------------------------------------
# Evidence: /tmp/opencode/phase5/recovery_build5.log, mounts_build5.txt,
# power_supply_build5.txt, and two live USB windows on build 5 (adb state=
# recovery at t=24s after `fastboot reboot recovery`, then the gadget vanishes
# from the bus entirely - no VID, no adb, no fastboot).

# 1) MTP must be off. bootable/recovery/Android.mk:236-238 adds -DTW_HAS_MTP
#    whenever TW_EXCLUDE_MTP is EMPTY (the only other assignment,
#    Android.mk:146, is inside `ifeq ($(TW_OEM_BUILD),true)`), and :224-226
#    links libtwrpmtp-ffs on the same condition. Nothing on the soong side
#    defines TW_HAS_MTP. At startup twrp.cpp:254-270 calls
#    PartitionManager.Enable_MTP() at :259, and Enable_MTP
#    (partitionmanager.cpp:2772-2822) does, in order:
#      :2791  property_set("sys.usb.config","none")     -> unbinds the UDC
#      :2796-2797  write idVendor/idProduct to
#             /sys/class/android_usb/android0/          -> ENOENT: this kernel
#             has no CONFIG_USB_ANDROID (configfs-only gadget, see
#             init.recovery.mt6779.rc)
#      :2798  property_set("sys.usb.config","mtp,adb")  -> asks init to rebind
#             a FunctionFS `mtp` function
#      :2803-2804  fork the MTP server to write the ffs descriptors
#    The `mtp` rebind cannot complete: the recovery ramdisk has no /etc/passwd
#    (so init's `mkdir /dev/usb-ffs/mtp 0770 mtp mtp` has no owner to chgrp
#    to) and no .rc referencing usb-ffs at all. fork() still succeeds, so
#    :2810 returns true and twrp.cpp:260 never falls back to plain adb.
#    Net effect observed twice: sys.usb.config=adb (recovery.log:500) is
#    replaced ~24 s in and the device drops off USB completely, which is what
#    made the log-extraction window unusable. Excluding MTP leaves the gadget
#    bound to `adb`. MTP is irrelevant here - adb + sideload are the goals.
TW_EXCLUDE_MTP := true

# 2) Battery percentage. twrp.cpp:426 compiles the sysfs reader only under
#    TW_USE_LEGACY_BATTERY_SERVICES; otherwise :457-465 calls GetBatteryInfo()
#    (the battery HAL), which is not running in recovery, so lastVal stays 0,
#    :468 writes tw_battery="0%" and gui/theme/portrait_hdpi/ui.xml:299
#    (`tw_battery > 0`) hides the readout. The thread is spawned unconditionally
#    at twrp.cpp:476. The legacy branch's default path
#    (/sys/class/power_supply/battery/{capacity,status}, twrp.cpp:433/:447) is
#    already correct for this board - live probe on build 5 listed
#    `/sys/class/power_supply/ -> ac battery mt6360_pmu_chg.2.auto mtk-gauge
#    mtk-master-charger usb` - so no TW_CUSTOM_BATTERY_PATH is needed.
#    CAUTION: Android.mk:390 tests for the literal value `true`; Android.mk:393
#    would set it for you but only AFTER :390 was evaluated, so setting
#    TW_CUSTOM_BATTERY_PATH alone would NOT add the -D flag.
TW_USE_LEGACY_BATTERY_SERVICES := true

# 3) Status-bar layout (notch / screen-curve clipping).
#    Screen is 1080x2340; portrait_hdpi is 1080x1920, so TWRP scales it
#    1.000000x / 1.218750x (recovery_build5.log:117, framebuffer 1080 x 2340 at
#    :108). x scale is 1.0, so theme x == physical x. The status row's y
#    (status_top/center/bottomalign_header_y = 4/15/30, ui.xml:116-118) becomes
#    physical 4.9 / 18.3 / 36.6 and the font_m=42 text runs ~51 px tall.
#
#    Notch geometry is ground truth, not an estimate:
#      dump/system.bin
#        -> /system/euclid/my_product.img          (inode 1130, 114442240 B)
#        -> /overlay/MultimediaOverlay.18593.product.apk (inode 148, 8542 B)
#        -> aapt: com.android.oppo.multimedia:string/config_mainBuiltInDisplayCutout
#           = "M -96,0 L -96,76 L 96,76 L 96,0 Z"
#      i.e. a 192 x 76 rectangle centred on screen centre (540) ->
#      x 444..636, y 0..76 (physical).
#    Consequences:
#      a) All three TW_STATUS_ICONS_ALIGN values keep the row inside y 0..76,
#         so NO vertical alignment can clear the notch - the clock must move in
#         x. The default clock is CENTER_X_ONLY at center_x=540
#         (ui.xml:292; placement.h:28) -> spans 488..592, i.e. entirely behind
#         the notch, which is exactly the reported symptom.
#      b) `center` also fixes the right-corner clip: the battery readout is
#         right-aligned at indent_right=1044 (ui.xml:304) and, top-aligned, sits
#         inside the corner curve. A corner radius of ~60-80 px is implied by
#         the reported "slightly cut off" CPU temp at x=indent=36, y~5.
#      c) The custom blocks (ui.xml:314/:322/:330/:338) carry NO placement
#         attribute, so they inherit TOP_LEFT (objects.hpp:59) and are
#         left-aligned. Raw pixel values pass through
#         libguitwrp_defaults.go:124-151 unchanged and are written to
#         {clock_12_pos}, {clock_24_pos} (both, so 12h and 24h agree) and
#         {cpu_pos} - no source edits to the TWRP tree are required.
#      d) x=300 -> clock spans ~300..400, clear of the CPU temp (60..~260) and
#         of the notch (starts 444); x=60 gives the CPU temp a wide margin
#         against the corner (edge is at x=23..29 at y=18.3 for R=70..80).
TW_STATUS_ICONS_ALIGN := "center"
TW_CUSTOM_CPU_POS := "60"
TW_CUSTOM_CLOCK_POS := "300"

# 4) FBE key installation (build 7).
#    Symptom: Copy Log reported success but no file appeared, TWRP backups
#    failed on /data/media/0, and every file under the fscrypt-protected dirs
#    opened with ENOKEY ("Required key not available"). The root cause is that
#    no key is ever installed, because Android.mk gates all of it:
#      Android.mk:335  ifeq ($(TW_INCLUDE_CRYPTO), true)
#        :336            -DTW_INCLUDE_CRYPTO -DUSE_FSCRYPT
#        :339            TW_INCLUDE_CRYPTO_FBE := true
#        :340            -DTW_INCLUDE_FBE
#    With neither flag set, every #ifdef TW_INCLUDE_FBE site is compiled out:
#    partition.cpp:786-816, partitionmanager.cpp:103/:2012/:2072/:2087/:2123/:3666,
#    twrpTar.cpp:57.
#    Enabling it makes partition.cpp:807 run, during fstab processing and
#    WITHOUT any user input:
#        while (!android::keystore::Decrypt_DE() && --retry_count) usleep(2000);
#    which (system/vold/Decrypt.cpp:186) does:
#        fscrypt_initialize_systemwide_keys()   // "overarching device encryption"
#        fscrypt_init_user0()                   // load_all_de_keys()
#    and the first of those does (system/vold/FsCrypt.cpp:87-89, :452-470):
#        device_key_path = /data/unencrypted/key ; retrieveOrGenerateKey(...)
#    No chicken-and-egg: /data/unencrypted carries NO EXT4_ENCRYPT_FL and lists
#    plaintext names, so the system-wide DE key is readable BEFORE
#    fscrypt_init_user0() ever reaches the locked /data/misc/vold/user_keys.
#    Proven on-device (build 6, read-only probes):
#      /data/unencrypted/key/{encrypted_key(92),keymaster_key_blob(268),
#                             secdiscardable(16384),stretching(10),version(1)}
#      /data/unencrypted/mode = "aes-256-xts:aes-256-cts:v1"   -> fscrypt v1
#      /data/unencrypted/ref and per_boot_ref = 8 bytes each   -> v1 descriptors
#      mode/ref/per_boot_ref written 2026-10-02 22:23, i.e. that function has
#      already run successfully on this very device.
#    keymaster_key_blob means the key is TEE-wrapped, so the keymaster HAL must
#    be started; partitionmanager.cpp:221/:441 (Process_Keymaster_Version) does
#    that from the vendor manifest, and /vendor mounts fine read-only (the
#    ORPHAN_PRESENT 0x4000 block only rejects RDWR).
#    DE unlock needs no credential. Whether /data/media/0 is CE or DE is still
#    UNDETERMINED (it has E, but the policy xattr was not read); if CE, TWRP
#    will prompt for the lockscreen secret, which is normal TWRP behaviour.
#    SIZE: recovery.img is exactly 67108864 B (the partition size) but that is
#    AVB padding, not payload - footer @file_size-64 is AVBf, version 1,
#    original_image_size = 34086912 B (32.51 MiB), vbmeta_size = 1664 B, and
#    the span from 34088576 to 67108800 is verified zero -> 31.49 MiB free, so
#    the extra HAL .so files fit.
#    CAUTION Android.mk:358 auto-adds -DTW_INCLUDE_FBE_METADATA_DECRYPT under
#    this flag. The GPT `metadata` partition is 33554432 B of 100% zeros (never
#    formatted, no ext4 magic) and recovery.fstab does not declare it, so that
#    path should no-op - but it is the first thing to check in the build 7 log.
TW_INCLUDE_CRYPTO := true

LOCAL_PATH := $(call my-dir)

ifneq ($(filter CPH1979,$(TARGET_DEVICE)),)
include $(call all-makefiles-under,$(LOCAL_PATH))

# ---------------------------------------------------------------------------
# Ship the BASE framework VINTF manifest in the recovery ramdisk.
#
# Root cause of the keystore2 crash-loop, established with build 13
# (2026-10-05):
#
#   * the ramdisk carries the keystore2 VINTF *fragment*
#     system/etc/vintf/manifest/android.system.keystore2-service.xml but not
#     the *base* file system/etc/vintf/manifest.xml;
#   * libvintf only reads .../vintf/manifest/*.xml inside
#     `if (systemEtcStatus == OK)`, i.e. only after the base has been fetched
#     and parsed (system/libvintf/VintfObject.cpp:386-392); with the base
#     missing it falls through to the legacy /system/manifest.xml (also absent)
#     and VintfObject::GetFrameworkHalManifest() therefore returns nullptr
#     (VintfObject.cpp:55-74);
#   * servicemanager skips a NULL manifest in forEachManifest
#     (frameworks/native/cmds/servicemanager/ServiceManager.cpp:45-56), so
#     isVintfDeclared("android.system.keystore2.IKeystoreService/default")
#     returns false (:81-101). IKeystoreService is @VintfStability
#     (system/hardware/interfaces/keystore2/aidl/.../IKeystoreService.aidl:40)
#     so Stability::requiresVintfDeclaration is true and
#     meetsDeclarationRequirements fails (:143-149), making addService return
#     EX_ILLEGAL_ARGUMENT (:268-271);
#   * ndk PruneException passes -3 through unchanged
#     (frameworks/native/libs/binder/ndk/status.cpp:135-164) and Rust's
#     parse_status_code has no arm for -3, so it falls into
#     `_ => StatusCode::UNKNOWN_ERROR` (binder/rust/src/error.rs:46-83).
#     keystore2 therefore panics at keystore2_main.rs:107 with
#     "Failed to register service ... because of UNKNOWN_ERROR" every ~5 s.
#     SELinux `add` permission is NOT the problem: EX_SECURITY (-1) maps to
#     STATUS_PERMISSION_DENIED and would have printed PERMISSION_DENIED.
#
# Live A/B on the running recovery (build 13, 2026-10-05): pushing only this
# 3034-byte file to /system/etc/vintf/manifest.xml stopped the loop -- 301
# panics by t=1749 s at a ~5.8 s cadence, then 0 panics in the following
# 83.6 s, keystore.crash_count frozen at 351, and
# init.svc_debug_pid.keystore2 holding pid 3805 across three samples.
#
# $(TARGET_OUT)/etc/vintf/manifest.xml is produced by
#   assemble_vintf -i system/libhidl/vintfdata/manifest.xml
# (ninja rule36124) and installed by the `Install:
# out/.../system/etc/vintf/manifest.xml` edge -- but that edge only runs while
# building the system image, which is why `mka recoveryimage` never delivered
# it. Adding the destination to ALL_DEFAULT_INSTALLED_MODULES puts it in
# INTERNAL_RECOVERYIMAGE_FILES (build/make/core/Makefile:1892-1893), a normal
# prerequisite of ramdisk_files-timestamp (:2230-2239), so kati emits the edge
# before mkbootfs packs the ramdisk and re-copies it whenever the source
# changes. This is what makes the fix a build rule rather than a frozen copy.
# ---------------------------------------------------------------------------
CPH1979_RECOVERY_VINTF_MANIFEST := $(TARGET_RECOVERY_ROOT_OUT)/system/etc/vintf/manifest.xml

$(CPH1979_RECOVERY_VINTF_MANIFEST): $(TARGET_OUT)/etc/vintf/manifest.xml
	@echo "Install: $@"
	@mkdir -p $(dir $@)
	$(hide) cp -f $< $@

ALL_DEFAULT_INSTALLED_MODULES += $(CPH1979_RECOVERY_VINTF_MANIFEST)
endif

# CHANGES.md — what this project changed in stock TWRP, and why

Stock TWRP `twrp-12.1` (manifest `minimal-manifest-twrp/platform_manifest_twrp_aosp`,
`refs/tags/android-12.1.0_r4`; `bootable/recovery` base commit
`5c3d206a` *"Support excluding zip from TWRP builds"*) does not support the
OPPO Reno Z (CPH1979, MT6779): no public device tree exists for it, and its
FBE (file-based encryption) `/data` cannot be decrypted by an unmodified
recovery, because stock Android on this device runs the **legacy keystore 1.0
daemon** and a **Trustonic TEE keymaster 3.0** stack with Android-11 identity
pins.

This file is the complete, per-hunk inventory of that work. Build numbers
(`build N`) refer to the bring-up sequence this tree was developed in; each
`N`'s rationale is preserved verbatim in the build script that carried it
(archived with the project evidence). The final image — build 26 — is
`848677614a9f8c40ee87e720b3ec07fe`.

## Size of the delta

| repository | files | changed | character |
|---|---:|---|---|
| `bootable/recovery` | 8 | +297 / −14 | mount lifecycle, two crash/correctness fixes, build-relink fixes |
| `system/vold` | 5 | +367 / −27 | FBE decrypt chain, two bug fixes, probes |
| `system/security` (keystore2) | 5 | +101 / −4 | CE unwrap migrator arm, null-manifest guard, probes |
| `hardware/interfaces` | 2 | +30 / −2 | probes + `recovery_available` |
| `build/make` | 1 | +18 / −2 | stock platform identity |
| `system/core` | 1 | +4 / −0 | `recovery_available` |
| `system/extras` | 1 | +3 / −0 | `recovery_available` |
| `device/oppo/CPH1979` | *new tree* | — | device adaptation (see [`DEVICE.md`](DEVICE.md) for per-value provenance) |

Categories used below: **[fix]** = correctness/functional change,
**[device]** = device adaptation, **[probe]** = diagnostics-only (kept
deliberately), **[build]** = build-infrastructure.

---

## 1. `bootable/recovery` (8 files)

### 1.1 `gui/action.cpp` — Install-TWRP-App crash + capability routing — **[fix] build 26**

* The `Error making app directory` `LOGERR` passed **two `%s` with one
  argument**; on the read-only system partition `mkdir()` failed into that
  branch and printf read a garbage vararg → SIGSEGV
  (`fault addr 0xffffffffffffffe0`) → init respawned recovery. Fixed by
  passing `install_path.c_str()`.
* Routing: the system-branch condition now gates on
  `TWPartition::Is_Read_Only()` *before* any mount (set at fstab parse for a
  `ro` entry — zero mount side effects) with a post-mount
  `Is_File_System_Writable()` belt, falling back to TWRP's own `/data/app`
  path whenever the partition cannot take the write. On this device the
  kernel refuses rw mounts of `system`/`vendor` entirely (ext4
  `ro_compat 0x4000` `shared_blocks` unknown to stock 4.19.127+), so the
  fallback is the correct and only working target.
* Evidence: the crash line `1465 → 1466` pair in the archived build-25 log;
  after the fix, `System partition is read-only, installing TWRP app to
  /data/app instead` followed by a successful install, zero crashes.

### 1.2 `gui/action.cpp` — `copylog` reports real status — **[fix] build 7**

Previously printed "Copied recovery log" unconditionally; now propagates
`TWFunc::copy_file`'s return code into `operation_end()` and logs a failure
as a failure. Paired with 1.4 (same build).

### 1.3 `partition.cpp` — FBE DE-key lifecycle (`Ensure_FBE_DE_Keys`, `Ensure_Mounted_RW`) — **[fix] builds 19/20/21**

* `FS_IOC_ADD_ENCRYPTION_KEY` keys belong to the *mounted superblock*:
  TWRP's `Setup_Data_Partition()` unmounts and remounts `/data`, which
  discarded the DE keys. `Ensure_FBE_DE_Keys()` re-installs them at every
  `/data` mount (`already-mounted`, `fresh-mount`, `pre-ce-decrypt`
  triggers) with plaintext-name checks for both the systemwide DE dir
  (`/data/system`) and the per-user DE dir (`/data/system_de/0`, build 20's
  user0-awareness).
* `Ensure_Mounted_RW()` remounts rw when the live `/proc/mounts` state is
  `ro` but the partition is meant to be rw — specifically the ro size-probe
  mount that `Update_Size()` can leave behind when the `data/media` bind
  makes the unmount fail (`EBUSY`, logged `Unable to unmount '/data'`).

### 1.4 `partition.cpp` — `Mount()` rw→ro fallback — **[fix] build 24**

When `mount(rw)` fails but `mount(ro)` succeeds, mount read-only instead of
leaving the partition unmounted, and record `Mount_Read_Only = true` so later
writes fail with a clean `EROFS`. This is the mechanism that makes
`system`/`vendor` usable at all on this kernel.

### 1.5 `partitionmanager.cpp` + `partitions.hpp` — pre-CE-decrypt belt — **[fix] builds 19–21**

Right before the password path, re-ensure `/data` is rw and its DE keys are
live (both are prerequisites for the credential path: sqlite opens
`locksettings.db` read-write and the spblob must be name-reachable).

### 1.6 `twrp.cpp` — system/vendor stay read-only — **[device] build 24**

Removed TWRP's force-rw branches (`Change_Mount_Read_Only(false)`); on this
device they made every boot attempt rw mounts the kernel cannot do, failing
all mounts with `EINVAL`. The fstab's `ro` is now honoured (both the
`tw_mount_system_ro == 0` and the fall-through else-branch print the
keep-ro decision).

### 1.7 `twrp-functions.cpp` — `copy_file` error handling — **[fix] build 7**

Check `is_open()` on both streams and fail loudly; upstream only checked
`dstfile.bad()` after the copy, so a failed open was silent.

### 1.8 `prebuilt/Android.mk` — relink fixes — **[build] builds 7 and 12–14**

* `libresetprop.so` added to `RECOVERY_LIBRARY_SOURCE_FILES` (build 7): with
  `TW_INCLUDE_CRYPTO` it is a DT_NEEDED of the recovery binary but
  `TWRP_REQUIRED_MODULES` alone does not place it in the ramdisk — the
  loader aborted before `main()` and init restarted recovery every ~14 ms.
* `RELINK_{LIBRARIES,BINARIES,VENDOR_HW}_DEPS` normal prerequisites: upstream
  only adds `LOCAL_REQUIRED_MODULES`, which is **order-only**
  (`main.mk:760-762` `$(1): | $(2)`), so after the first build the relink
  stamp never went stale and `mka` kept packaging a stale ramdisk ("no work
  to do" while `recovery/root` held the previous build's keystore2).

### 1.9 `etc/init/keystore2.rc` — `stdio_to_kmsg` — **[probe] build 12**

keystore2 aborts were invisible in recovery (no logd, no tombstoned, no
console). `stdio_to_kmsg` routes its stderr into kmsg where dmesg can read
it. Behaviour-neutral: only where the bytes go changes.

---

## 2. `system/vold` (5 files)

### 2.1 `Decrypt.cpp` — legacy keystore store copy + gates — **[fix] builds 22/23**

Stock runs the legacy keystore 1.0 daemon: keys live as files under
`/data/misc/keystore/user_0/`, never a `persistent.sqlite`. Recovery starts
keystore2 on a scratch dir (`/tmp/misc/keystore`), so the migrator saw an
empty store and `get_key_entry()` answered `KEY_NOT_FOUND` for the
synthetic-password key (domain SELINUX, namespace 103) — the "key not found"
that stopped user-0 CE decrypt. `copy_legacy_keystore_store()` copies the
legacy files into the scratch store before the first `get_key_entry()`
(build 23: only after both DE key stages, because before them the
DE-protected names are still ciphertext; only a walk that found `user_0`
marks success), and `Decrypt_User_Synth_Pass` refuses the call while the copy
isn't ready rather than letting the migrator cache `STATE_EMPTY` for the
boot.

### 2.2 `Decrypt.cpp` — `copySqliteDb` truncation guards — **[fix] build 26**

The old code opened the destination sqlite with default `ofstream` mode
(**truncates**) when its source (`/data/misc/keystore/persistent.sqlite`)
never exists on this device — so every recovery start zeroed the live
scratch DB. Harmless on a fresh boot, destructive on a within-boot restart
(init respawning recovery after a crash): it wiped the rows the migrator had
already written and CE decrypt failed until a full reboot. Now: `stat(src)`
first (absent → leave the DB alone), and never overwrite an already-populated
destination.

### 2.3 `FsCrypt.cpp` — step probes — **[probe] build 15**

Per-step `printf`s for `get_data_file_encryption_options` /
`retrieveOrGenerateKey` / `install_storage_key` and each write. Diagnostics
that localised the DE failure to step 1/2 (identity, build 17) and then
step 3 (keyring, build 18).

### 2.4 `KeyStorage.cpp` — upgrade-blob UB guard — **[fix] build 25**

`BeginKeymasterOp` had the `if (!opHandle.getUpgradedBlob()) return opHandle;`
guard commented out, so a successful `begin()` with no upgrade blob fell
through to `*opHandle.getUpgradedBlob()` — dereferencing a disengaged
`std::optional` (undefined behaviour; observed live as
`begin_ok=1 upgradedBlob_present=0` five times per boot). Restored, plus
probes around it.

### 2.5 `KeyUtil.cpp` — keyring/ioctl probes — **[probe] builds 15/18**

`[de]` prints for `fscryptKeyring` search, `add_key`, and
`FS_IOC_ADD_ENCRYPTION_KEY` (with errno and descriptor hex) — these proved
build 18's root cause (no fscrypt keyring existed yet) and build 19's
"install succeeded, then died later" sequence.

### 2.6 `Keymaster.cpp` — bounded keystore2 wait — **[fix] build 9**

`AServiceManager_waitForService()` waits forever; when keystore2
crash-looped, vold parked inside it *before* the recovery UI was created and
TWRP hung on the splash screen. Replaced with a bounded 5 s
`AServiceManager_checkService()` retry falling through to the existing
"unable to connect" error path, so the UI can always come up. (The keystore2
crash-loop itself was fixed in the same build — 3.2.) Plus `[de]` probes on
the ctor and exception paths.

---

## 3. `system/security` — keystore2 (5 files)

### 3.1 `legacy_migrator.rs` — ns103 → uid 1000 arm — **[fix] build 22**

The LockSettings namespace (103) holds the synthetic-password key; the
legacy store kept it under uid `AID_SYSTEM` (1000). The migrator's filter
only mapped `WIFI` (102 → 1010) and refused every other namespace. Added the
`LOCKSETTINGS_NAMESPACE` arm (mirroring WIFI) with an attribution log.

### 3.2 `vintf/vintf.cpp` — null device-manifest guard — **[fix] build 9**

`VintfObject::GetDeviceHalManifest()` returns `nullptr` when the manifest
cannot be read (recovery: `/vendor` not yet mounted at keystore2's
`late-init`). All four FFI entry points dereferenced it — a pure-virtual
dispatch through a null `this` → SIGSEGV at `0x0` → keystore2 crash-loop →
vold's `waitForService` deadlock (2.6) → hung splash. They now return an
empty list instead; the Rust shim tolerates len 0 by construction.

### 3.3 `keystore2_main.rs` — panic hook also writes stderr — **[probe] build 13**

In recovery there is no logd, so the existing `error!` went into a socket
nobody reads and every panic was a bare `received signal 6`. The hook now
also `eprintln!`s — landing in kmsg via 1.9's `stdio_to_kmsg`.

### 3.4 `km_compat.cpp`, `security_level.rs` — begin/create_operation probes — **[probe] build 16**

Tag-level dumps around the keymaster shim's `begin()` and keystore2's
`create_operation` — these established that `Tag::PURPOSE` survived into the
shim and the real failure was `ErrorCode::KEY_REQUIRES_UPGRADE (-62)`, i.e.
the identity mismatch fixed in 5.

---

## 4. `hardware/interfaces` (2 files)

### 4.1 `keymaster/4.1/support/Keymaster3.cpp` — begin/upgrade probes — **[probe] build 16**

Dumps purpose/key length/parameter tags and the v3 result codes for
`begin()`/`upgradeKey()` on the keymaster-3.0 passthrough — the lines that
pinned `-62 KEY_REQUIRES_UPGRADE` to the Trustonic glue reading
`ro.build.version.release` (fixed by 5).

### 4.2 `security/keymint/support/Android.bp` — `recovery_available: true` — **[build] build 7**

Required so `libkeymint_support` links into the recovery variant when
`TW_INCLUDE_CRYPTO := true`.

---

## 5. `build/make` — platform identity — **[fix] build 17**

`PLATFORM_VERSION_LAST_STABLE := 11` (not 12) and
`PLATFORM_SECURITY_PATCH := 2022-06-05` (not 2022-04-05). These are emitted
verbatim as `ro.build.version.release` / `ro.build.version.security_patch`;
stock's `libMcTeeKeymaster.so` derives `Tag::OS_VERSION`/`Tag::OS_PATCHLEVEL`
from them and keymaster mandates `KEY_REQUIRES_UPGRADE` on any mismatch with
the keys' creation values (created by stock Android 11, patch 2022-06-05 —
`debugfs ... cat /system/build.prop dump/system.bin`). Provenance of both
stock values: the dump's own `build.prop`.

## 6. `system/core` — `libgatekeeper_aidl` `recovery_available: true` — **[build] build 7**

Without it Soong refuses the `.recovery` variant and the
`TW_INCLUDE_CRYPTO` link of `bootable/recovery/Android.mk:357` fails.

## 7. `system/extras` — `libf2fs_sparseblock` `recovery_available: true` — **[build] build 7**

Same class of fix for a `RECOVERY_LIBRARY_SOURCE_FILES` entry (f2fs tools in
recovery).

---

## 8. `device/oppo/CPH1979` — the device tree (new)

Full per-value provenance is in
[`DEVICE.md`](DEVICE.md) (every
BoardConfig value traced to the boot header / `build.prop` of the stock
images). Highlights:

* **Boot layout** from the stock recovery header: header v2, page 2048,
  kernel 13995930 B @ `0x40080000`, ramdisk @ `0x51C00000`, dtbo offset
  44429312 / size 860091, AVB `SHA256_RSA2048` footer at `image_size − 64`.
* **`prebuilt/`** — stock kernel, recovery dtbo, `mt6779.dtb` (kept in git,
  documented; unmodified Oppo/MTK components).
* **`recovery/root/`** — the stock FBE/TEE runtime the decrypt chain needs
  (Trustonic keymaster 3.0 service, gatekeeper, `mcDriverDaemon`,
  `mcRegistry` TAs): **extracted, not committed** — see
  `extract-blobs.sh` / `proprietary-files.txt` (the 67 direct copies are
  md5-verified against the stock recovery ramdisk, and the 52 `/odm` copies
  are md5-identical duplicates of the vendor set — 119 files pinned in
  `blobs.md5` — so every runtime `-r` path resolves).
* Two ELFs under `system/lib64` **are committed**: they are built from this
  tree (`hardware/interfaces/keymaster/3.0/default`, Apache-2.0; build 11
  replaced stock's incompatible A11 builds — see the build-11 script header
  for the symbol-generation conflict).
* Symlinks (`keystore.mt6779.so`, `gatekeeper.*.so`) are recreated by the
  extract script (build 10's one-line root-cause fix was this missing
  `dlopen` target).
* `recovery/root/init.recovery.mt6779.rc` carries the fscrypt keyring
  creation (`install_keyring`, build 18) and related boot-time plumbing;
  `system.prop` carries the stock identity pins (P11.6).

---

## Category totals (approximate)

| category | lines | note |
|---|---:|---|
| functional fixes (decrypt chain) | ~350 | sections 2.1–2.6, 3.1–3.2, 5 |
| functional fixes (mounts / crashes) | ~150 | sections 1.1–1.7 |
| build infrastructure | ~110 | sections 1.8, 4.2, 6, 7 |
| diagnostics (kept on purpose) | ~140 | sections 1.9, 2.3, 2.5, 3.3–3.4, 4.1 |
| device adaptation | new tree | section 8 |

Every fix above is verified live on the device (build 26, md5
`848677614a9f8c40ee87e720b3ec07fe`): FBE DE+CE decrypt with the user's own
PIN, `adb sideload`, and the two build-26 regression tests (Install TWRP App
without crash; decrypt still working after a forced within-boot recovery
restart).

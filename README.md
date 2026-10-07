# TWRP for OPPO Reno Z (CPH1979 / MT6779)

A custom recovery built from TWRP `3.7.1_12-0` source, ported to the OPPO
Reno Z **from the device's own firmware** — there was no public device tree
for this phone, and no public TWRP/OrangeFox build existed for it.

What makes this port unusual: it decrypts **FBE-encrypted `/data` (both DE
and CE)** on a device that runs the legacy keystore 1.0 daemon with a
Trustonic TEE keymaster stack — verified end-to-end on hardware, not
theoretically.

| | |
|---|---|
| Device | OPPO Reno Z, model **CPH1979**, board `oppo6779`, SoC MT6779 (Helio P90) |
| Base | TWRP `twrp-12.1` @ `android-12.1.0_r4` (manifest `minimal-manifest-twrp`) |
| Verified against | stock Android 11, build `1654583371623`, security patch 2022-06-05 |
| Release image | `recovery.img` — **md5 `848677614a9f8c40ee87e720b3ec07fe`** (build 26) |
| Partition scheme | **A-only**, fixed-size partitions, non-dynamic (`no super`) |

## Status — what is proven, and what is not

Everything in the "proven" column was executed on the device and observed,
with logs; nothing here is assumed.

| feature | state | notes |
|---|---|---|
| FBE decrypt — DE (device encrypted) | ✅ proven | keys re-installed on every `/data` mount |
| FBE decrypt — CE with the owner's PIN | ✅ proven | synthetic-password path via keystore2 migrator; fresh boot **and** after a within-boot recovery restart |
| `adb shell` in recovery | ✅ proven | |
| `adb sideload` + unsigned zip install | ✅ proven | executed end-to-end with a test zip |
| Install TWRP App | ✅ proven | installs to `/data/app` (system is read-only — see below) |
| system / vendor mounting | ✅ by design, read-only | the stock kernel **cannot** rw-mount them (ext4 `shared_blocks` 0x4000 unknown to 4.19.127+); the recovery mounts ro and routes writes to `/data` |
| `/data` mount + sqlite (locksettings) | ✅ proven | rw, required for the credential path |
| Layout | **A-only** | GSI installs (if you go that route) must be `aonly` images |
| TWRP backup / restore / wipe / MTP / GUI extras | ⚪ built-in, **not exercised in this project** | stock TWRP functionality, untested on this device here |
| Other stock builds (different firmware) | ⚪ untested | decrypt keys/identity pins are matched to build `1654583371623` |
| `/custom` (odm) mount | ⚠️ known non-functional | this device's odm image is effectively empty; the failure is expected |

**Known quirk:** if recovery is ever killed and restarted *within the same
boot* (it respawns automatically), TWRP's own crash counter disables MTP for
the rest of that boot. Reboot to clear it. (Decrypt still works after such a
restart — that path is tested.)

## What was changed in stock TWRP

Everything, with per-hunk reasoning and build attribution: **[CHANGES.md](CHANGES.md)**.
In short:

1. **Device tree** — this repository *is* the tree (TWRP convention: clone
   it into `device/oppo/CPH1979` of a synced source tree), authored from
   the firmware dump; every value traced to a byte offset in
   [DEVICE.md](DEVICE.md).
2. **FBE decrypt chain** — vold/keystore2/keymaster changes so the legacy
   keystore store, the Trustonic keymaster 3.0 stack and the Android-11
   identity pins line up (patches 02–05).
3. **Mount correctness** — read-only-by-design system/vendor with clean
   fallbacks, DE keys re-installed across `/data` remounts, size-probe ro
   leaks fixed (patch 01).
4. **Two crash bugs fixed** — a format-string SIGSEGV in the Install TWRP
   App path, and a sqlite truncation that broke decrypt after a recovery
   restart (both proven on-device before the fix, regression-tested after).
5. **Diagnostics** — ~140 lines of `[de]`/`[sp]` probes are kept on purpose;
   they are what makes decrypt problems diagnosable on this device.

The complete patch series: [`patches/`](patches/README.md) (7 patches, applies
cleanly onto the manifest-pinned base).

## Installing

See **[INSTALLING.md](INSTALLING.md)** for the full instructions, warnings
and verification steps. The core:

```sh
md5sum recovery.img          # must be 848677614a9f8c40ee87e720b3ec07fe
adb reboot bootloader        # wait for fastboot to enumerate
fastboot flash recovery recovery.img
fastboot reboot recovery
```

Then enter your lock-screen PIN at the password prompt — the same PIN the
phone uses.

## Building it yourself

See **[BUILDING.md](BUILDING.md)**: sync the `twrp-12.1` manifest, clone this
repo into `device/oppo/CPH1979`, apply the 7 patches, run `extract-blobs.sh`
against your own stock firmware dump, `lunch twrp_CPH1979-eng && mka recoveryimage`.

## Repository contents

This repository **is** the device tree (TWRP layout — clone it straight into
`device/oppo/CPH1979` of a synced source tree), plus the patch series and docs.

| path | what it is |
|---|---|
| `BoardConfig.mk`, `twrp_CPH1979.mk`, `device.mk`, `Android*.mk`, `recovery.fstab`, `system.prop`, `vendorsetup.sh` | the device tree (boot header layout, fstab, identity pins) |
| `prebuilt/`, `recovery/root/` | stock kernel/dtbo/dtb; ramdisk overlay (init rc, vintf, the two tree-built ELFs) |
| `extract-blobs.sh` + `proprietary-files.txt` / `blobs.md5` / `symlinks.txt` | pulls the 119 proprietary ramdisk files from **your** stock `recovery.bin` and md5-verifies them |
| `patches/` | the complete source delta vs stock TWRP |
| `DEVICE.md` | device-tree provenance: every value traced to a byte offset in the firmware dump |
| `CHANGES.md` | every change, classified and attributed |
| `BUILDING.md` / `INSTALLING.md` | build & flash instructions |
| `LICENSE` | GPL-3.0-or-later (TWRP's license; see License below) |

## Provenance and data policy

* This repository contains **no device-unique data**: no serial numbers, no
  keys, no RPMB/nvram material, no personal data. The committed prebuilts
  (kernel, dtbo, dtb) are model-firmware components — identical across all
  units running that build — and the 119 extracted TEE/gatekeeper files are
  pulled by *you* from *your* firmware, never shipped.
* The device tree was authored from a raw dump of the author's unit; the
  dump itself is not redistributed here.
* Layout conventions were borrowed from the public OrangeFox device tree
  for `CPH1989` (Reno 2F — note: MT6771, *not* our MT6779); platform,
  fstab, kernel config and all values were re-derived independently.

## Credits

* **Team Win** and AOSP — TWRP and the recovery framework.
* **minimal-manifest-twrp** — the build manifest this tree syncs against.

## License

* Source patches, device tree and documentation: **GPL-3.0-or-later**, the
  same license as TWRP itself (see [`LICENSE`](LICENSE), which carries the
  full text). Files or hunks derived from AOSP retain their original
  Apache-2.0 terms where marked.
* `prebuilt/kernel`, `prebuilt/recovery_dtbo.img`, `prebuilt/dtb/` —
  unmodified stock firmware components from Oppo/MediaTek; the kernel is
  GPLv2-licensed by its authors (source available from the device
  manufacturer's firmware releases).
* Files extracted by `extract-blobs.sh` (Trustonic TEE trusted apps,
  keymaster/gatekeeper binaries) — © Oppo/MediaTek/Trustonic, part of the
  device's firmware; they are **not** included in this repository. The
  published `recovery.img` release contains them, as any bootable recovery
  image built for this device must.

## Disclaimer

Flashing a recovery image can brick your device. This project is provided
as-is, with no warranty of any kind (see `LICENSE`). Verify every downloaded
file's md5 before flashing, keep a copy of your stock recovery, and only
flash images you have checksum-verified.

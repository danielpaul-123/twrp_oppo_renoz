# BUILDING.md — from a clean sync to a flashable `recovery.img`

The reference build environment was: Linux x86-64, OpenJDK 11, the
`minimal-manifest-twrp` manifest at `refs/tags/android-12.1.0_r4`. Every step
below is the one actually used to produce the released image.

## 1. Prerequisites

* A POSIX shell, `repo` (Google's repo tool) on `PATH`, `git`, `python3`.
* **JDK 11** — set `JAVA_HOME` explicitly, e.g.
  `export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64`.
* Disk for a full TWRP/AOSP tree plus `out/`: the reference workspace
  (synced as in §2, with `--depth=1`) measured **~44 GB** total
  (`.repo` 8 GB + checked-out sources 25 GB + `out/` 11 GB) — keep
  ≥ 60 GB free. A full-history sync (without `--depth=1`) produces
  byte-identical checkouts but a much larger `.repo` — measured past
  47 GB mid-sync — so allow ≥ 90 GB free for that variant. (The dump
  itself is separate: the extract step only needs its `recovery.bin`.)
* The device's **stock firmware dump** — specifically `recovery.bin`, the
  raw read of the stock recovery partition. On this project that dump is a
  full per-partition raw read of the device; for *this* build step only
  `recovery.bin` is required (the extract script says so explicitly).

## 2. Sync the source tree

```sh
mkdir twrp-12.1 && cd twrp-12.1
repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git \
          -b twrp-12.1
repo sync
```

The manifest's default revision is already `refs/tags/android-12.1.0_r4`
(revision string from `.repo/manifests/default.xml`), i.e. the exact base
this port was developed and tested against. `--depth=1` fetches only that
tag snapshot per project: the reference workspace and the released image
were built from exactly this (all 218 projects shallow, `.repo` 8 GB), and
the patch series was verified against such clones. Omitting `--depth=1`
fetches full history — same checkouts, same result, but a much larger
`.repo` (see §1).

## 3. Clone this repo into the tree

This repository **is** the device tree (TWRP convention: `BoardConfig.mk` &
friends at the repository root). Clone it to its Android-tree location,
exactly like a TeamWin device tree:

```sh
git clone <this-repository-url> device/oppo/CPH1979
```

This gives you `device/oppo/CPH1979/` in place.

## 4. Apply the patches

From the manifest root (see `patches/README.md` for the table of which patch
touches which repo, and its base commit):

```sh
REPO=$PWD/device/oppo/CPH1979       # the clone from §3
git -C bootable/recovery   apply "$REPO/patches/01-bootable_recovery.patch"
git -C system/vold         apply "$REPO/patches/02-system_vold.patch"
git -C system/security     apply "$REPO/patches/03-system_security_keystore2.patch"
git -C hardware/interfaces apply "$REPO/patches/04-hardware_interfaces_keymaster.patch"
git -C build/make          apply "$REPO/patches/05-build_make_identity.patch"
git -C system/core         apply "$REPO/patches/06-system_core_recovery_available.patch"
git -C system/extras       apply "$REPO/patches/07-system_extras_recovery_available.patch"
```

Each applied repository's `git diff` must then be byte-identical to the
patch file itself — that is the acceptance check in `patches/README.md`, and
it is how the released patches were verified.

## 5. Extract the proprietary ramdisk files

```sh
bash device/oppo/CPH1979/extract-blobs.sh /path/to/your/dump
```

This reads your stock `recovery.bin` (gzip ramdisk at byte offset 13998080,
size 30430430 — Android boot header v2, page_size 2048), copies the 119
files listed in `proprietary-files.txt` into `recovery/root/`, recreates the
4 symlinks in `symlinks.txt`, and **fails unless all 119 md5s match**
`blobs.md5`. Nothing is downloaded; nothing except your own dump is touched.

(The two ELFs under `recovery/root/system/lib64/` that are *not* extracted
are committed to git — they are built from this source tree, see
`CHANGES.md` §8.)

## 6. Build

```sh
source build/envsetup.sh
lunch twrp_CPH1979-eng
mka -j16 recoveryimage      # -j to taste; the reference build used -j16
```

Output: `out/target/product/CPH1979/recovery.img`.

The reference build's script also ran an image-acceptance check (header,
segments, AVB footer compared field-by-field against the stock recovery
header) before flashing; the released image passed it. That check lives in
the project's private acceptance tooling and is not part of this repo, but
the practical smoke test for your own build is in `INSTALLING.md`.

## 7. Expected output

* Header v2, page_size 2048; kernel and dtbo segments laid out as described
  in `device/oppo/CPH1979/DEVICE.md`.
* Signed with the AOSP test key (this device's bootloader accepts it —
  see `BoardConfig.mk`'s AVB notes).

**Byte-reproducibility:** the published image's md5 is
`3f0988438999e42623d761f4e326015c`. **A rebuild from the same tree will not
reproduce that md5**, and that is expected, not a failure of your build. Two
causes, both measured on this project:

* the ramdisk's cpio headers embed file mtimes, which track the build clock;
* AVB signs with RSA-PSS, whose salt is randomized on every signing run, so
  the 256-byte signature and the vbmeta digest differ each time.

What *is* stable, and what the reproducibility gate for this tree actually
compares, is content: the kernel segment (sha256), every ramdisk entry's path
+ mode + type + bytes, all boot header fields, and the AVB footer's
`original_image_size` / vbmeta offset / size. Those match the published image
exactly. Only the exact md5 is expected to drift — see `CHANGES.md` for what
"build 27" pins down (`BUILD_DATETIME=1791199381`, a single clock, where
build 26 was stamped from two 16 s apart).

## Troubleshooting

* **`git apply` fails** — you are not at the base commit listed in
  `patches/README.md`; check it out first (`git -C <repo> rev-parse HEAD`).
* **extract script: "no gzip magic at offset 13998080"** — your
  `recovery.bin` is not this device's stock recovery image (wrong file, or
  a different build).
* **extract script: md5 mismatch** — your stock firmware differs from the
  build this port was developed against (`1654583371623`). The script
  intentionally refuses to continue; see README's "Other stock builds"
  status row.
* **`lunch` doesn't offer `twrp_CPH1979`** — the clone step
  (§3) didn't land in `device/oppo/CPH1979/`.

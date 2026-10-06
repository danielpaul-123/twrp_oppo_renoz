#!/bin/bash
# extract-blobs.sh — populate the proprietary ramdisk files that are kept
# out of git from the device's own stock firmware dump.
#
# Usage:  extract-blobs.sh /path/to/dump
#         (the directory that contains recovery.bin, the raw stock recovery
#          partition read — do NOT modify it; this script only reads)
#
# What it does, and why each step is exact:
#
#   1. dump/recovery.bin is an Android boot image, header v2, page_size 2048,
#      kernel_size 13995930, ramdisk_size 30430430 (parsed from the header:
#      analysis/data/pA_recovery_img.json in the author's dump workspace).
#      The ramdisk therefore starts at byte
#          2048 + ceil(13995930 / 2048) * 2048 = 13998080
#      and is gzip-compressed (magic 1f 8b verified below before use).
#   2. The gunzipped cpio is unpacked to a temp dir (never into the source).
#   3. Every file listed under "# SECTION ramdisk" in proprietary-files.txt is
#      copied out of that ramdisk. The copy set was verified byte-identical:
#      all 67 files md5-match the stock ramdisk, and the 52 odm-dupes
#      md5-match their vendor/ counterparts (52/52).
#   4. The 4 symlinks in symlinks.txt are recreated (they live inside the
#      extracted dirs).
#   5. md5sum -c blobs.md5 — the script fails loudly unless every one of the
#      119 files matches the pinned manifest.
#
# Two files under system/lib64 are NOT extracted: they are built from source
# in this tree (hardware/interfaces/keymaster/3.0/default, Apache-2.0) and
# are committed to git.
set -euo pipefail

DUMP=${1:?usage: extract-blobs.sh /path/to/dump   (dir containing recovery.bin)}
HERE=$(cd "$(dirname "$0")" && pwd)

RD_OFF=13998080          # byte offset of the ramdisk payload
RD_SIZE=30430430         # ramdisk payload size from the boot header
PAGE=2048

SRC="$DUMP/recovery.bin"
if [ ! -f "$SRC" ]; then
    echo "ERROR: $SRC not found." >&2
    echo "Point this at the directory holding the stock recovery partition read." >&2
    exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "[extract] unpacking ramdisk from $SRC (offset $RD_OFF, size $RD_SIZE)"
dd if="$SRC" bs="$PAGE" skip=$((RD_OFF / PAGE)) \
   count=$(((RD_SIZE + PAGE - 1) / PAGE)) of="$TMP/rd.gz" status=none
head -c "$RD_SIZE" "$TMP/rd.gz" > "$TMP/rd.gz.trim"
if ! head -c2 "$TMP/rd.gz.trim" | od -An -tx1 | grep -q "1f 8b"; then
    echo "ERROR: no gzip magic at offset $RD_OFF — is this the stock recovery.img?" >&2
    exit 1
fi
gzip -dc "$TMP/rd.gz.trim" > "$TMP/rd.cpio"
mkdir "$TMP/rd"
(cd "$TMP/rd" && cpio -idm --quiet < "$TMP/rd.cpio")

echo "[extract] copying SECTION ramdisk files"
mode=""
copied=0
duplicated=0
while IFS= read -r line; do
    case "$line" in
        "# SECTION ramdisk"*)  mode="ramdisk";  continue ;;
        "# SECTION odm-dupes"*) mode="dupes";    continue ;;
        ''|'#'*)               continue ;;
    esac
    mkdir -p "$HERE/$(dirname "$line")"
    if [ "$mode" = "ramdisk" ]; then
        # tree path recovery/root/X lives at X inside the stock ramdisk
        src_rel="${line#recovery/root/}"
        if [ ! -f "$TMP/rd/$src_rel" ]; then
            echo "ERROR: $src_rel not present in the stock ramdisk" >&2
            exit 1
        fi
        cp -a "$TMP/rd/$src_rel" "$HERE/$line"
        copied=$((copied + 1))
    else
        src="recovery/root/${line#recovery/root/odm/}"
        if [ ! -f "$HERE/$src" ]; then
            echo "ERROR: odm-dupe source missing: $src" >&2
            exit 1
        fi
        cp -a "$HERE/$src" "$HERE/$line"
        duplicated=$((duplicated + 1))
    fi
done < "$HERE/proprietary-files.txt"
echo "[extract] copied=$copied duplicated=$duplicated"

echo "[extract] recreating symlinks"
while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    path="${line%% -> *}"; target="${line##* -> }"
    mkdir -p "$HERE/$(dirname "$path")"
    ln -sfn "$target" "$HERE/$path"
done < "$HERE/symlinks.txt"

echo "[extract] verifying against blobs.md5"
if (cd "$HERE" && md5sum -c --quiet blobs.md5); then
    echo "[extract] OK — all $(wc -l < "$HERE/blobs.md5") files match the pinned manifest"
else
    echo "ERROR: md5 verification failed (see above)" >&2
    exit 1
fi

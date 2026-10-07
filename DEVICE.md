# device/oppo/CPH1979 — OPPO Reno Z (CPH1979), MT6779 / board `oppo6779`

*This file documents the device tree this repository ships; `device/oppo/CPH1979`
is where it lives in a synced Android tree. References to `report NN`,
`FINDINGS.md` or `analysis/…` below are to the author's private working notes,
which are not included here.*

A recovery device tree **authored from the firmware dump**, not ported.

## Why this exists

There is no public TWRP/OrangeFox tree for this device:

- OrangeFox `device` group: no project matching `CPH1979`, `6779`,
  `oppo6779`, `renoz` or `reno-z`.
- GitHub repo search: 0 results for `CPH1979 twrp`, 0 for `twrp oppo mt6779`.

The closest existing tree is `OrangeFox/device/CPH1989` (Reno 2F), which is
**MT6771, not MT6779**. Its layout conventions are borrowed (header v2,
`pagesize 2048`, `ALLOW_MISSING_DEPENDENCIES`, prebuilt kernel, AVB); its
platform, GPU, kernel config and fstab are **not**.

## Provenance of every device-specific value

Source: the device's own stock firmware dump (raw partition reads; the dump
itself is not redistributed with this tree — see `extract-blobs.sh`).

| value | source |
|---|---|
| `kernel_size` 13995930, `kernel_addr` 0x40080000 | `dump/recovery.bin` boot header → `analysis/data/pA_recovery_img.json` → `header` |
| `ramdisk_addr` 0x51C00000, `tags_addr` 0x57300000, `second_addr` 0 | same |
| `page_size` 2048, `header_version` 2, `os_version` 0x16000166 | same |
| `cmdline` `bootopt=64S3,32N2,64N2 buildvariant=user` | same (`header.cmdline`) |
| `recovery_dtbo_offset` 44429312, `recovery_dtbo_size` 860091 | same; equals the first page boundary after the ramdisk ends (44428510 → 44429312) |
| `base` 0x40078000 + offsets | **derived**, see below |
| AVB `SHA256_RSA2048`, 1792 B, `image_size` 45438976, salt/digest | `pA_recovery_img.json` → `vbmeta` |
| recovery partition end 67108864 | `pA_recovery_img.json` → `footer` (footer @67108800, 64 B) |
| `ro.product.board` `oppo6779`, `ro.board.platform` `mt6779` | `debugfs cat /build.prop dump/vendor.bin` |
| `ro.build.*`, `ro.treble.enabled`, `ro.hardware.*`, `ro.crypto.*` | `debugfs cat /system/build.prop dump/system.bin` + vendor |
| `ro.product.brand/manuf/model/name` = OPPO / OPPO / CPH1979 / CPH1979, `ro.product.device` = **OP48A1** | `strings dump/{system,vendor}.bin` (vendor also carries `OP48A1L1`, `CPH1979EEA`, `CPH1979RU` variants) |
| partition sizes: recovery 67108864 (lba 8..16391), boot 33554432 (lba 200448..208639) | GPT parsed from `dump/gpt.bin` (4096-byte sectors); both equal the dumped files' sizes |
| `recovery.fstab` | extracted verbatim from the recovery ramdisk payload at `dump/recovery.bin[13998080:+30430430]` (855 cpio entries, matching `pA_recovery_img.json` `entry_count`) |
| `prebuilt/kernel` | `extracted/kernel.gz`, 13995930 B — byte-identical to the stock kernel segment (the payload is gzip; `extracted/kernel` is its 38490112-B gunzip) |
| `prebuilt/recovery_dtbo.img` | `dump/dtbo.bin[0:860091]` |

### Header v2's DTB segment (resolves report 09 §11.2 and §11.6)

`pA_recovery_img.json → header` records an 8-byte `board_field`
`0142020000003057` and report 09 §11.6 calls its meaning UNDETERMINED; §5.2
states "Neither image's boot header references container #2 … See hypothesis
§11.2". Both are misreadings of the same two bytes:

```
u32 @1648 = 0x00024201 = 147969   dtb_size   == container #2 total_size
u64 @1652 = 0x57300000            dtb_addr   == tags_addr
u32 @1644 = 1660                  header_size == 1652 + 8  -> layout pinned
```

Reproduced independently on `dump/recovery.bin` **and** `dump/boot.bin`
(`dtbo_size` 0 there, matching report 09's `boot_has_no_recovery_dtbo`
control). The payload at `recovery.bin[45289472:+147969]` starts
`d7b7ab1e 00024201` (MTK container magic + the same size) with FDT magic
`d00dfeed` at +64, and is byte-identical to `boot.bin[14913536:+147969]`.

So container #2 **is** the boot image's `dtb` segment — report 09's §11.2
hypothesis is correct, and §5.2's "not referenced by any header" is wrong.

*The JSON artefact itself is intentionally left untouched (it is a pinned,
md5-protected product of `pA_recovery_img.py`); this correction lives in
report 09's text, not in the data file.*

### The base/offset split (derived, not recorded)

The image stores only **absolute** addresses, so `base` itself is a
convention. `base = 0x40078000` was chosen because it reproduces **all four**
stored addresses using mkbootimg's default `kernel_offset 0x8000` and the
conventional MTK `second_offset 0xBFF88000`:

```
0x40078000 + 0x00008000 = 0x40080000  kernel_addr    MATCH
0x40078000 + 0x11B88000 = 0x51C00000  ramdisk_addr   MATCH
0x40078000 + 0xBFF88000 = 0x00000000  second_addr    MATCH
0x40078000 + 0x17288000 = 0x57300000  tags_addr      MATCH
```

Independently corroborated: `OrangeFox/device/CPH1989` uses
`BOARD_KERNEL_BASE := 0x40078000` and `BOARD_SECOND_OFFSET := 0xbff88000`,
which also yields `second_addr = 0`.

*Confidence: high — 4/4 addresses, plus an unrelated tree agreeing on the two
conventional constants.*

## Constraints this tree must satisfy (FINDINGS.md §8)

1. **Full `kernel_size` 13995930 B at offset 2048** — the device currently
   sits in `recovery` with a kernel truncated by 384 B (report 09 §9.4); the
   repack tool responsible is UNDETERMINED (report 10 §10 point 5).
2. **Ramdisk at 13998080** — the stock layout (the live image's begins at
   13997696 only because of the truncation).
3. **A populated `twres/`** — an earlier build died four times on
   `LoadLanguageListDir '/twres/languages/' path not found` (report 10 P10.5).
   The stock recovery has no `twres/` at all; TWRP provides its own.
4. **`/system/bin/adbd` and `/sbin/e2fsck` must resolve** — `ro.debuggable=1`
   makes `init.rc` fire two paths at an `adbd` that does not exist, and four
   `exec /sbin/e2fsck` target a directory holding only `sh`/`bash`
   (report 10 P10.8).
5. **The abandoned `parrot` build tree is not to be recovered** (user decision,
   report 09 §11.7). Nothing in the log mine names a build system.

## Known build-time unknowns

- `TARGET_CPU_VARIANT := cortex-a75` — MT6779 is 2x A75 + 6x A53; if the
  build system rejects `cortex-a75`, fall back to `cortex-a73` or `armv8-a`.
- `board_field 0142020000003057` in the stock header is **UNDETERMINED**
  (report 09 §11.6); not passed to mkbootimg.
- Whether `BOARD_MKBOOTIMG_ARGS --recovery_dtbo` is honoured by this build
  system version — verify against the emitted image's segment map.
- `os_version 0x16000166` does not decode to `0x0B…` under the plain
  `A<<24|B<<16|C<<8|D` scheme; recorded raw, not load-bearing.

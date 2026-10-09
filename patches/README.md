# patches/ — the complete source delta vs stock TWRP

Seven patches, one per upstream repository. Together they are the **entire**
difference between stock TWRP (`minimal-manifest-twrp` `twrp-12.1`, manifest
pinned to `refs/tags/android-12.1.0_r4`) and the tree that produced the
flashed image `3f0988438999e42623d761f4e326015c` (build 27). Nothing else in
the source tree is modified.

Each patch was exported with `git diff` from the working tree that built
build 26, so it applies to the same base it was made from. Build 27 carries
**the same seven patches, unchanged** — it is build 26 rebuilt with
`BUILD_DATETIME` pinned and a complete `recovery/root` restage, so no source
delta exists between the two. The Gate 4 reproducibility check confirms these
patches are byte-identical (modulo index-hash width) to the applied tree that
rebuilt the published image.

| patch | applies in | base commit | what it carries |
|---|---|---|---|
| `01-bootable_recovery.patch` | `bootable/recovery` | `5c3d206a5eeb3d446bcda8248a405a4b278bab5c` | FBE mount/DE-key lifecycle, system/vendor keep-ro + rw→ro fallback, Install-TWRP-App crash fix + capability routing, relink fixes, keystore2 `stdio_to_kmsg` |
| `02-system_vold.patch` | `system/vold` | `a164ba05c5fef288059774a776b2e6e1119957cf` | legacy keystore store copy, `copySqliteDb` truncation guards, upgrade-blob UB fix, bounded keystore2 wait, decrypt probes |
| `03-system_security_keystore2.patch` | `system/security` | `14737db1429b8eebc15568bc748b2cd79ccad5c2` | ns103→uid 1000 migrator arm, null-VINTF-manifest guard, panic→stderr, begin/create_operation probes |
| `04-hardware_interfaces_keymaster.patch` | `hardware/interfaces` | `ae469cee0dce6d71489588126a15da8e67a50102` | Keymaster3 begin/upgrade probes, `recovery_available` for keymint support |
| `05-build_make_identity.patch` | `build/make` | `1b692e2248609f50a27c48cce53b7445cecdcfc5` | stock platform identity (`release=11`, patch level `2022-06-05`) |
| `06-system_core_recovery_available.patch` | `system/core` | `ac4f36c7eb076ea2c582061a21dfc49eaa71e623` | `libgatekeeper_aidl` buildable for recovery |
| `07-system_extras_recovery_available.patch` | `system/extras` | `ffbe71168883383d7048d076000f4db9936bc00a` | `libf2fs_sparseblock` buildable for recovery |

Per-hunk classification (device adaptation vs functional fix vs diagnostic
probe vs build infrastructure) with the reasoning for each: see
[`../CHANGES.md`](../CHANGES.md).

## Applying

From the root of a synced `twrp-12.1` source tree (paths are relative to the
manifest root, i.e. the same layout the patch headers use):

```sh
REPO=/path/to/twrp_oppo_renoz
git -C bootable/recovery  apply "$REPO/patches/01-bootable_recovery.patch"
git -C system/vold        apply "$REPO/patches/02-system_vold.patch"
git -C system/security    apply "$REPO/patches/03-system_security_keystore2.patch"
git -C hardware/interfaces apply "$REPO/patches/04-hardware_interfaces_keymaster.patch"
git -C build/make         apply "$REPO/patches/05-build_make_identity.patch"
git -C system/core        apply "$REPO/patches/06-system_core_recovery_available.patch"
git -C system/extras      apply "$REPO/patches/07-system_extras_recovery_available.patch"
```

`git apply` (not `git am`): these are plain `git diff` files, exported from
the working trees, and the trees are manifest-pinned checkouts where creating
commits is the builder's choice, not ours.

## Verifying an application

After applying, the diff of each repository must be byte-identical to the
patch file itself:

```sh
for p in "$REPO"/patches/*.patch; do :; done   # (see table for the mapping)
git -C bootable/recovery diff | diff - "$REPO/patches/01-bootable_recovery.patch" && echo OK
# …same for the other six
```

If `diff` prints anything, the tree you patched is not the base listed above
(check out the base commit first — `git -C <repo> checkout <base>`).

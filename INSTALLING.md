# INSTALLING.md — flashing the recovery

> **Read the warnings first.** This writes to your device's recovery
> partition. Verify checksums before flashing anything. This project ships
> no warranty — see `LICENSE`.

## What you need

* `recovery.img` from the Releases page of this repository.
* `adb` and `fastboot` on your computer.
* An unlocked bootloader (see step 0).
* Your lock-screen PIN (entered **on the phone's screen**, never on a
  computer and never typed into any tool).

## Step 0 — preconditions (do not skip)

1. **Check the bootloader state:**

   ```sh
   adb reboot bootloader
   fastboot getvar unlocked
   ```

   *This project never performed an unlock step* — the author's unit
   accepted fastboot writes as it was. Whether a factory-locked unit will
   accept this image was **not tested**; if `getvar unlocked` reports no,
   you must research unlocking this model yourself first (Oppo unlock
   policy applies — do not skip this research, and do not ask this repo's
   author for unlock keys).

2. **Verify the image before touching the device:**

   ```sh
   md5sum recovery.img
   # 3f0988438999e42623d761f4e326015c  recovery.img
   ```

   This identifies the **published** image. If you built the recovery
   yourself, yours will not match — exact md5 is not reproducible (ramdisk
   cpio mtimes, and the AVB signature salt is randomized per build), so a
   mismatch here is only meaningful for a downloaded copy. Verify a
   self-build by content instead; see `BUILDING.md`'s
   "Byte-reproducibility" section. If a *downloaded* copy's md5 differs,
   stop — you have the wrong file (or it was altered).

3. **Back up your stock recovery** by any means you already trust (root
   `dd`, firmware files you keep). Flashing replaces it. Restoring it is
   how you get back to factory service.

## Step 1 — boot into fastboot

With the phone booted into Android and USB debugging enabled:

```sh
adb reboot bootloader
```

Wait for enumeration — on this device fastboot can take ~30 s to appear.
If `fastboot devices` is empty after that: unplug/replug, run
`fastboot kill-server`-equivalents by restarting the USB connection, and
beware a stale `adb` server (`adb kill-server`).

## Step 2 — flash

```sh
fastboot flash recovery recovery.img
```

Only the recovery partition is written: `boot`, `system`, `vendor` and
`userdata` are untouched, so your Android installation and data are not
modified by this step.

## Step 3 — boot the recovery

```sh
fastboot reboot recovery
```

You land in TWRP (`3.7.1_12-0` + this port's changes).

## Step 4 — decrypt

If `/data` is encrypted (FBE), TWRP shows the password prompt — enter your
**lock-screen PIN** on the device's touch screen. Decryption was verified
end-to-end on this port: after the correct PIN, the password screen is
followed by `status=0` and the main UI reports the user decrypted.

## Smoke test (optional, recommended)

With the device decrypted in TWRP:

```sh
adb shell ls /data/data | head    # DE/CE content visible => decrypt works
adb devices                        # device listed in recovery
```

Then, from Android (or TWRP), `adb sideload <zip>` is the tested install
path for unsigned zips.

## After installation — notes

* **Quirk:** if TWRP is killed and restarts *within the same boot*, its
  crash counter disables MTP until the next reboot (the only effect;
  decryption still works — that path is regression-tested). Reboot to
  restore MTP.
* The **Install TWRP App** action installs to `/data/app` on this device
  (system is read-only by design — see README's status table).
* `system`/`vendor` appear as read-only mounts: correct and intentional,
  not a malfunction of your flash.
* Going back: re-flash your backed-up stock recovery image with the same
  `fastboot flash recovery <stock>.img` procedure.

## Uninstalling / returning to stock

Flash your backed-up stock recovery (step 0.3). No other partition was
modified, so no other restoration is required by this project.

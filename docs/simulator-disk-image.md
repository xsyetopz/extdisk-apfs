# A Disk Image on the Volume Works

[Back to the simulator overview](simulator-storage.md). The startup line that
attaches the image is in [simulator-startup-line.md](simulator-startup-line.md).

The refusal above is about the physical volume. A disk image stored on that
volume is not refused, and that makes the volume usable for the part of the
simulator that grows with use, the device data. `extdisk-apfs simdisk` builds
this configuration. Measured on macOS 27.2 with Xcode 27.1 and the iOS 27.2
runtime, with the image on `/Volumes/DevAudioStore`.

## The Commands

On macOS 27.2 `hdiutil create -volname -size`, `hdiutil attach` and
`hdiutil detach` each print a deprecation warning on stderr and name
`diskutil image create from/blank`, `diskutil image attach` and `diskutil eject`
as the replacements. `hdiutil info` prints no warning (`hdiutil info 2>err
>/dev/null` left `err` at 0 bytes), so the tool still reads mount points from it.

```text
$ diskutil image create blank --format UDSB --fs APFS --volumeName SimDevices --size 60g /Volumes/DevAudioStore/SimDevices.sparsebundle
$ diskutil image attach --mountPoint ~/Library/Developer/CoreSimulator/Devices /Volumes/DevAudioStore/SimDevices.sparsebundle
/dev/disk9s1 Apple_APFS_Volume     /Users/krystian/Library/Developer/CoreSimulator/Devices
$ diskutil eject ~/Library/Developer/CoreSimulator/Devices
```

`diskutil image create blank --help` lists `--format` as `RAW`, `ASIF` or
`UDSB`, and `diskutil image info` reports `UDSB` as `Sparse bundle image`. It
still grows on demand: a `--size 60g` image was 12M when new and 562M after one
device was created and booted. `--size` takes diskutil units, and `60g` worked;
a bare number is bytes, which is why the tool refuses a size with no unit.
The attach output is tab-separated and the mount point is the third field of the
last line that has one; the second field is padded with spaces, so they are
stripped.

## Mounted at the Device Set

`--mountPoint` mounts the image directly at the path Xcode and Simulator read:

```text
$ xcrun simctl list devices available            # 11 devices, the image's own set
$ xcrun simctl create 'simdisk-probe' 'iPhone 18 Pro' com.apple.CoreSimulator.SimRuntime.iOS-27-2
73C14D84-6F81-4729-9849-092521BC646D             # succeeded, no --set flag
$ xcrun simctl boot 73C14D84-6F81-4729-9849-092521BC646D   # reported Booted
```

This is better than linking the default set into the image, for four reasons.

- No data is moved. Mounting over an existing non-empty directory shadows it,
  and the directory comes back on eject. A file `underneath.txt` in the
  directory disappeared while the image was mounted and reappeared after
  `diskutil eject`. So there is no backup directory and no `mv`.
- The drive being absent degrades gracefully. With the image detached,
  `simctl list devices available` showed the 11 devices of the original
  internal set. A dangling symlink gave no working set at all.
- The path is the same on every Mac. A symlink had to name the mount point found
  at attach time, and macOS appends a suffix when a `/Volumes` name is taken, so
  the link could dangle. Reasoning, not measured: a mount point under `$HOME`
  cannot collide with another volume's name. A test would attach a second volume
  named like the path's last component and check that the set path still holds
  the image.
- A symlink broke other things. A symlinked `Caches` breaks runtime installation
  with `PinnedFileError "Cannot open source file without following a symlink"`
  (see [simulator-storage.md](simulator-storage.md)). Reasoning, not measured: a
  mount point is not a symlink, so that failure should not apply. The image is
  mounted at `Devices`, not `Caches`, and no runtime install was run through the
  mount. A test would run `xcodebuild -downloadPlatform iOS` with the image
  mounted and check that registration succeeds.

There is no `Simulator.app` on this machine: `find /Applications/Xcode.app -name
Simulator.app` and `find /Library/Developer -name Simulator.app` return nothing,
`mdfind` finds none, and `open -b com.apple.iphonesimulator` fails with
`LSCopyApplicationURLsForBundleIdentifier() failed`. Xcode 27.1 runs the
simulator UI through `SimulatorTrampoline.xpc` inside `CoreSimulator.framework`.
That Xcode reads the mounted set is shown by `xcrun xctrace list devices`, which
is Xcode's own tooling and not `simctl`: it lists the simulators with the
image's UUIDs. No Xcode window was observed.

## The Stacking Hazard

`--mountPoint` over a path that already has a volume mounted silently stacks a
second mount and hides the first. This happened by accident: `mount` listed both
`/dev/disk9s1` and `/dev/disk11s1` on `/Volumes/SimDevices`, and the directory
listing dropped from 12 entries to 1 until the image was ejected. So `simdisk`
never attaches blindly. Before anything is created or attached it looks at the
device set path:

`simdisk_set_state` names one of five states, and `simdisk_set_check` refuses
three of them:

- `ours`: our image is mounted there. It says so and skips (`hdiutil info`
  names the image at the path). Not a refusal.
- `elsewhere`: our image is attached at some other mount point. It stops and
  names that point, and says to eject it. `diskutil` ignores `--mountPoint` for
  an image it has already attached (measured, see
  [simulator-startup-line.md](simulator-startup-line.md#what-was-measured)), so
  attaching would report success and leave the set unmounted.
- `foreign`: another disk image or volume is mounted there. It stops, names the
  device, and says to eject it. `diskutil info <path>` reports `Protocol: Disk
  Image`, a `Device Node`, and a `Mount Point` equal to the path when the path is
  itself a mount point.
- `link`: a symlink is there. It stops, because a symlink cannot be a mount
  point. This is the state an older version of this tool left behind; remove the
  link.
- `free`: a plain directory, or nothing. It proceeds, creating the directory
  first because `--mountPoint` needs it to exist.

The state is read before anything is created, so a refusal leaves nothing behind.
After an attach, `simdisk` dies if `diskutil` reports a mount point other than
the one asked for.

## What Is Not Explained

`mount` reports the image `apfs, local, nodev, nosuid, journaled, noowners`,
while the external volume runs with `Owners: Enabled`. So `noowners` on the
image is a second difference from the volume besides the removable
classification, and the evidence does not separate the two. Neither is claimed
as the cause. `diskutil info` on the mounted image still reports `Protocol: Disk
Image`, and the earlier `Removable Media: Removable` reading came from the same
kind of image. That is the observation; what decides the EPERM is not concluded.

## What `simdisk` Does

```bash
extdisk-apfs simdisk /Volumes/X --dry-run
extdisk-apfs simdisk /Volumes/X [--size 60g]
extdisk-apfs simdisk /Volumes/X --undo
```

In order:

1. Refuses a volume that is the boot volume, not a mount point, or not on an
   external physical disk, the same guard as `host`.
2. Refuses a symlink, a foreign mount, or the image attached elsewhere, at the
   device set path, before creating or attaching anything.
3. Creates `SimDevices.sparsebundle` on the volume if it is absent. `--size` is a
   ceiling and not an allocation. It defaults to `60g` and applies only when the
   image is created.
4. Creates `~/Library/Developer/CoreSimulator/Devices` if it is absent.
5. Attaches the image there with `--mountPoint`, unless it already is.
6. Writes the startup line into the shell startup file, in a block keyed
   `simulator <volume>`
   ([simulator-startup-line.md](simulator-startup-line.md)). If the startup file
   cannot be named, that is a warning and not a failure, because the image is
   attached and the line to add has been printed.

No device data is copied or deleted. The image starts with the standard set that
CoreSimulator fills in. While the image is mounted, the devices in the shadowed
directory are invisible, and they come back when the image is ejected. Measured:
the internal set held 11 devices, the image held 11 different ones, and `iPhone
17` in the image is `066B909E-C685-4ED8-9F23-82BD477AE7F0`.

## The Image Does Not Shrink

Deleting a 192 MB leftover device set inside the image left the bundle still
reporting 778M, read with `du -sh` on the `.sparsebundle`. So deleting files
inside does not give the space back on the volume. The reading is that an APFS
sparse bundle keeps its bands; the cause was not tested. Reclaiming the space
needs the image detached and compacted, which `simdisk` does not do, and a
compact was not run here, so how much it would return is unmeasured.

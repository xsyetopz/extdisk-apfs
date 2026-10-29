# The Simulator on an External Volume

What the iOS Simulator keeps, and which parts of it an external volume can hold.
Checked on macOS 27.2 (build 26B123) with Xcode 27.1 (build 27A9275) and the iOS
27.2 (24B114) runtime, against the volume `/Volumes/DevAudioStore`. The method
for each claim is in the table in
[external-storage.md](external-storage.md#how-each-claim-was-checked). Replace
`/Volumes/X` with your volume's mount point.

The short answer: as tested on this machine, nothing simulator-related could be
stored on the external volume except the downloaded runtime installer. The
runtime is in a system asset location by design, and creating a device in a set
on the volume fails with `EPERM` from `CoreSimulatorService`, while the same
command succeeds on any path on the boot volume and the same user copies the
same content onto the external volume without trouble. That leaves the daemon's
access to a removable volume as the only explanation standing, though no grant
could be made to confirm it, because the daemon is absent from the Files and
Folders pane. A disk image on the volume is the exception: it is not refused,
and [`extdisk-apfs simdisk`](simulator-disk-image.md) hosts the device data
that way.

## Device Sets Take a Path

`xcrun simctl help` gives the usage line `simctl [--set <path>] [--profiles
<path>] <subcommand> ...`, so every subcommand takes a device set path, and
`simctl` validates it:

```bash
$ xcrun simctl --set /tmp/dsprobe/set2 list devices
Provided set path does not exist: /tmp/dsprobe/set2
```

The directory must exist first. The default set stays at
`~/Library/Developer/CoreSimulator`.

The flag does more than pass validation: `simctl --set /tmp/dsprobe create` and
`simctl --set ~/dsprobe-home create` each returned a device UUID and populated
the set, so a working device set can live at any path on the boot volume,
including one outside `~/Library/Developer/CoreSimulator`.

```bash
mkdir -p /Volumes/X/CoreSimulator
xcrun simctl --set /Volumes/X/CoreSimulator list devices
```

This is a per-invocation flag for `simctl`. There is no equivalent for the Xcode
and Simulator applications: the environment variable
`CORESIMULATOR_DEVICE_SET_PATH` does not exist in the installed
`CoreSimulator.framework` binary or in `simctl`.

## A Device Set on an External Volume Fails with EPERM

`--set` is accepted, but creating a device inside a set on this external USB
volume fails, and so did the symlink workarounds. Every attempt below ran with
the iOS 27.2 runtime installed and the directory at `krystian:staff drwxr-xr-x`
on a volume reporting `Owners: Enabled`:

```text
$ xcrun simctl --set /Volumes/X/CoreSimulator create "iPhone 18 Pro" ... iOS-27-2
Internal error: device remained in Creating state after fixup completed even
though it is available.
```

`~/Library/Logs/CoreSimulator/CoreSimulator.log` names the real cause:

```text
CoreSimulatorService: Error copying sample content to path
/Volumes/X/CoreSimulator/<UDID>/data : NSCocoaErrorDomain Code=513
"You don't have permission to save the file ... in the folder "CoreSimulator"."
NSUnderlyingError={Error Domain=NSPOSIXErrorDomain Code=1 "Operation not permitted"}
```

The error is `EPERM`, not `EACCES`. Four tests narrow the cause to the daemon's
access to this volume specifically, and rule out everything else:

| Test | Result |
| --- | --- |
| `ditto` the runtime's whole `SampleContent` tree to the volume, as the user | succeeded, all 79 entries, identical to the same copy onto the boot volume |
| `simctl --set /tmp/dsprobe create` | succeeded, device UUID returned |
| `simctl --set ~/dsprobe-home create` | succeeded, device UUID returned |
| `simctl --set /Volumes/X/CoreSimulator create` | failed, `EPERM` |

So the daemon writes to arbitrary paths on the boot volume, including ones
outside its own `~/Library/Developer/CoreSimulator` root, and the same user
copies the same root-owned content onto this volume without trouble. Neither the
`--set` flag, the sample content, the file ownership, nor the volume's APFS
settings explains the failure. What is left is the daemon's own access to a
removable volume.

That still falls one step short of proof, because no grant was made and the
create retried. The grant could not be made: `CoreSimulatorService` does not
appear under System Settings > Privacy & Security > Files and Folders, and the
`Terminal` entry there offers `Network Volumes` but no `Removable Volumes` row,
so there is nothing to switch on. Adding the daemon by hand under Full Disk
Access, at
`/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/XPCServices/com.apple.CoreSimulator.CoreSimulatorService.xpc`,
is the remaining untried route.

A second measurement is consistent with that, and does not settle it. A
LaunchAgent on macOS 27.2 attached a disk image on the boot volume (exit 0) but
not one on the external volume (`Operation not permitted`, exit 1), and a plain
read of a file on the external volume from that agent failed too. An interactive
shell does both, and that shell does not have Full Disk Access: reading
`~/Library/Application Support/com.apple.TCC/TCC.db`, which needs it, failed.
That is one run of one agent with no grant attempted, so it fits the
removable-volume restriction without identifying the mechanism, and whether
`CoreSimulatorService` meets the same refusal is not shown. The details are in
[simulator-startup-line.md](simulator-startup-line.md#why-not-a-launchagent).

The daemon is not sandbox-restricted in a way that explains this either:
`codesign -d --entitlements -` on that bundle reports only
`com.apple.CoreSimulator.simdiskimaged.manager`, with no app-sandbox
entitlement, and the unified log recorded no sandbox denial for it.

**Replacing the directories with symlinks does not work either**, and each one
fails in its own way. `~/Library/Developer/CoreSimulator/Caches` symlinked to
the volume breaks runtime installation, because the daemon opens a pinned file
without following symlinks:

```text
$ xcodebuild -downloadPlatform iOS -buildVersion 27.2
Error: Registering simulator runtime with CoreSimulator failed.
  CoreSimulatorUtilities.PinnedFileError Code=1
  "Cannot open source file without following a symlink"
```

The 8.32 GB download completed and only the registration step failed, so the
cost of finding this out is a wasted download.
`~/Library/Developer/CoreSimulator/Devices` symlinked to the volume leaves
device creation failing with the same `Creating state` error as `--set`. Both
fail for the same reason, as far as the log shows: `CoreSimulator.log` records
the same "copying sample content" `Operation not permitted` failure twice, once
at a path under the symlinked `Devices` directory and once at a path in the
`--set` directory with no symlink involved. Same error, same daemon, with and
without a symlink; the cause is described with the same caution as above. Both directories were restored to real directories, after which
registration succeeded and `simctl` created and booted an iPhone 18 Pro on iOS
27.2 without error.

## Runtimes Cannot Be Moved

`xcrun simctl help runtime` says `add <path>` adds a runtime disk image "to the
secure storage area", and no subcommand takes a destination. That area is not
even `/Library/Developer/CoreSimulator/Images`: after installing iOS 27.2,
`simctl runtime list -v` reported the 7.7 GB image at
`/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime/<hash>.asset/AssetData`,
mounted as a cryptex under `/private/var/run/com.apple.security.cryptexd/mnt/`.

What can live on the volume is the downloaded installer:

```bash
xcodebuild -downloadPlatform iOS -buildVersion 27.2 -exportPath /Volumes/X/SimRuntimes
```

That installs the runtime and also writes a 7.7 GB
`iphonesimulator_27.2_24B114.exportedBundle` to the volume, confirmed with `du
-sh` and `ls`. `xcodebuild -help` lists `-importPlatform <simruntimedmgpath>`,
which presumably reinstalls such a bundle without a download, but that command
was not run, so the reinstall is documentation and not measurement. Reclaim the
installed copy instead:

```bash
xcrun simctl runtime delete --outdated --dry-run
xcrun simctl runtime delete --notUsedSinceDays 90
xcrun simctl runtime delete --unusable
xcrun simctl delete unavailable
```

`xcrun simctl help delete`: "Specifying unavailable will delete devices that are
not supported by the current Xcode SDK." `--dry-run` prints what
`runtime delete` would remove without removing it.

## There Is No iPadOS Runtime

`xcodebuild -downloadPlatform` takes `iOS|watchOS|tvOS|visionOS` and no
`iPadOS`. iPad simulators are device types of the iOS runtime: `xcrun simctl
list devicetypes | grep -ci ipad` counted 43 iPad types with no runtime
installed. After the iOS 27.2 runtime registered, `xcrun simctl list devices`
listed 11 devices on iOS 27.2 that nobody created by hand, 5 iPhones and 6
iPads, including `iPhone 18 Pro` and `iPad Pro 13-inch (M5)`, all `Shutdown`.
`iPhone 18 Pro` was then booted, reported `Booted`, and was shut down again. So one iOS runtime covers both, and asking for an iPadOS
runtime separately is asking for something that does not exist.

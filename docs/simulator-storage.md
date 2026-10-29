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
on the volume fails with `EPERM` from `CoreSimulatorService`. A TCC denial is
the most likely cause, but no permission grant was tried, so that is an
inference.

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

The error is `EPERM`, not `EACCES`, and the same user can `touch` and `cp -R` in
that directory. That points away from file permissions. The most likely
explanation is a TCC denial of removable-volume access, but that is an
inference: no app or daemon was granted access and the create retried, so it
is not an observed fact. It is also unknown whether `CoreSimulatorService`, a
launchd daemon, can be granted that access at all, or whether macOS attributes
the request to a responsible process such as the terminal or Xcode.

Untried: the Removable Volumes permission under System Settings > Privacy &
Security > Files and Folders, which Apple's Logic Pro page tells you to enable
when relocation is refused. The daemon may not appear in that list. In the one
configuration tested, a `--set` directory on this volume, no device could be
created.

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

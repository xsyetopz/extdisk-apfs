# Putting Development and Audio Data on an External Volume

Once the disk is an APFS volume, the question is which data may live on it. Some
tools take a path. Others search a fixed list of directories, and no setting
adds to that list.

Every claim here was checked on one machine: macOS Darwin 27.2.0, Xcode 27.1
(build 27A9275), `bun` 1.4.4, `/bin/bash` 3.2.57. The method for each claim is
in [How Each Claim Was Checked](#how-each-claim-was-checked). Replace
`/Volumes/X` with your volume's mount point.

This is the long-form evidence. The same mechanisms, plus the ones for
applications that are not installed here, are in the catalogue the tool reads:
`extdisk-apfs hosts /Volumes/X` lists them, `extdisk-apfs explain <id>` shows
one with its source, and [docs/hosts.md](hosts.md) describes the file.

## Before Anything Else: You May Not Own the Volume

`diskutil eraseDisk` leaves the volume's root directory owned by `root`. On the
disk this was developed against:

```bash
$ stat -f '%Su:%Sg %Sp' /Volumes/DevAudioStore
root:wheel drwxrwxr-x
$ touch /Volumes/DevAudioStore/probe
touch: /Volumes/DevAudioStore/probe: Permission denied
```

The console user is in `staff`, not `wheel`, so the user who just created the
volume cannot write to it. Fix it by taking the root directory:

```bash
sudo chown "$(id -u):$(id -g)" /Volumes/X
```

`extdisk-apfs erase --own` runs exactly that, and `extdisk-apfs verify` reports
the owner, the mode and whether you can write.

`diskutil enableOwnership` is a different thing and does not fix this. Per
`man diskutil` it makes "the User and Group ID settings of files, directories,
and links" on the volume count, by editing the Volume Database at
`/var/db/volinfo.database`. That setting is stored on the host, not on the
disk, so another Mac starts from its own default. Use it when you will restore
a tree whose owners must survive; use `chown` when you want access.

The ownership state of a new volume is not stable immediately. Straight after
the erase, `diskutil info` reported `Owners: Disabled`. About 25 minutes later
the same command on the same volume reported `Owners: Enabled`, with
`GlobalPermissionsEnabled` true and no `noowners` flag in `mount`. Read the
current state rather than assuming either value.

## Xcode Build Data

### Derived Data and Archives

Two command-line flags, both from `xcodebuild -help` on Xcode 27.1:

```bash
xcodebuild -scheme MyApp -derivedDataPath /Volumes/X/DerivedData build
xcodebuild -scheme MyApp -clonedSourcePackagesDirPath /Volumes/X/SourcePackages build
```

- `-derivedDataPath PATH`: "specifies the directory where build products and
  other derived data will go".
- `-clonedSourcePackagesDirPath PATH`: "specifies the directory to which remote
  source packages are fetch or expected to be found".

`-archivePath` names the archive bundle, not a parent directory. The two
installed sources disagree about this, so it was tested. `man xcodebuild` says
"the path for the archive produced by the archive action"; `xcodebuild -help`
says "the directory where any created archives will be placed". Archiving a
throwaway package twice settled it: `-archivePath .../out/Probe.xcarchive`
produced `Probe.xcarchive`, and `-archivePath .../outdir` produced
`outdir.xcarchive`, not a directory named `outdir`. The man page is right.

```bash
xcodebuild -scheme MyApp -archivePath /Volumes/X/Archives/MyApp.xcarchive archive
```

These flags apply to one invocation. A persistent setting exists too; see
[The Settings Window](#the-settings-window).

### The Settings Window

Xcode's settings carry the same two locations. The control labels, read from
`IDESettingsPanel.framework` inside the installed Xcode, are **Derived data
location** and **Archives location**, alongside **Build Location** and
**Compilation Cache**. The options, from `IDEKit.framework`, are **Default**,
**Custom**, **Absolute** and **Relative to %@**.

The preference keys behind them exist in `IDEFoundation.framework`:
`IDECustomDerivedDataLocation`, `IDECustomDistributionArchivesLocation`,
`IDECustomBuildLocationType`, `IDECustomBuildProductsPath` and
`IDESharedBuildFolderName`.

Apple publishes no documentation page for these settings; a search of
developer.apple.com for the Xcode derived data and archives locations returns no
such article. So the keys are real but undocumented.

They are also honoured. On Xcode 27.1 (build 27A9275), `defaults write
com.apple.dt.Xcode IDECustomDerivedDataLocation -string /tmp/ddprobe/DD` and
then `xcodebuild -scheme Probe -destination 'platform=macOS' build` on a
throwaway `swift package init --type library` succeeded and filled
`/tmp/ddprobe/DD` with `CompilationCache.noindex`, `ModuleCache.noindex`,
`SDKExplicitPrecompiledModules`, `SDKStatCaches.noindex` and two
`...-djuxcbbnibazutgzwbicdrestqjz` directories, one for the scheme and one for
the package. `~/Library/Developer/Xcode/DerivedData` stayed empty (`total 0`).
The same build with the key set to `/Volumes/DevAudioStore/DerivedData.noindex`
put the same six entries there and left the default location empty again.

The key is the only way found to persist the location for a plain `xcodebuild`
run with no flag. The settings window carries the same locations and is the
other way to set them for Xcode.app:

```bash
defaults write com.apple.dt.Xcode IDECustomDerivedDataLocation -string /Volumes/X/DerivedData.noindex
defaults write com.apple.dt.Xcode IDECustomDistributionArchivesLocation -string /Volumes/X/Archives
```

The bare form of these commands, without `-string`, is the template in the
catalogue. It was verified through the tool: `extdisk-apfs host --only
xcode-derived-data,xcode-archives` applied both keys, and `defaults read`
returned the two volume paths.

The archives key was built against too. With
`IDECustomDistributionArchivesLocation` set to `/Volumes/DevAudioStore/Archives`,
`xcodebuild -scheme ArProbe -destination 'platform=macOS' archive` with no
`-archivePath` printed `archive ok`, and `find /Volumes/DevAudioStore/Archives
-maxdepth 2` listed `2026-10-29/ArProbe 29.10.2026, 18.47.xcarchive`, while
`~/Library/Developer/Xcode/Archives` did not exist. So Xcode puts the archive
under a `<date>/` subdirectory of the configured location: the configured path
is a parent, not the bundle. The risk stays: Apple does not document either key, so a future
Xcode may rename or ignore them, and a build fails while the volume holding the
custom path is detached. `xcodebuild -derivedDataPath` overrides the key for one
invocation. `defaults delete com.apple.dt.Xcode IDECustomDerivedDataLocation`
restores the default.

### Swift Package Manager

From `swift build --help`:

```bash
swift build --scratch-path /Volumes/X/spm-build --cache-path /Volumes/X/spm-cache
```

`--scratch-path` replaces the per-package `.build` directory, and
`--config-path` is also available. The scratch path is per invocation, so it
belongs in a wrapper script.

### Xcode Device Support

`~/Library/Developer/Xcode/iOS DeviceSupport` holds symbol files for connected
devices. No flag for it appears in `xcodebuild -help` or `xcrun simctl help`.
Delete the directories for OS versions you no longer debug; there is no
supported way to move the folder.

## The Simulator

The simulator is its own long story, and the answer for an external volume is
almost entirely no. [simulator-storage.md](simulator-storage.md) has it: a
`--set` device set works at any path on the boot volume but fails on an external
one with a permission error from `CoreSimulatorService`, symlinking the
CoreSimulator directories breaks both runtime installation and device creation,
the runtime itself lives in a system asset location, and the only part the
volume can hold is the downloaded installer bundle. It also explains why there
is no iPadOS runtime to install. The device data can live on the volume inside
a disk image, which `extdisk-apfs simdisk` sets up; see
[simulator-disk-image.md](simulator-disk-image.md).

## Spotlight

Rename a directory so it ends in `.noindex` and Spotlight skips its contents.
No password needed, and it applies per directory rather than per volume:

```bash
mkdir /Volumes/X/build.noindex
```

Tested with the same file written into two sibling directories. `mdfind` found
the copy in `indexed/` within five seconds and never found the copy in
`skipped.noindex/`.

Xcode does this to its own caches. An `xcodebuild archive` run on this machine
created `CompilationCache.noindex`, `ModuleCache.noindex` and
`SDKStatCaches.noindex` inside `~/Library/Developer/Xcode/DerivedData`.

For the whole volume, `man mdutil` gives `-i on | off`, which "sets the indexing
status for the provided volumes":

```bash
sudo mdutil -i off /Volumes/X
sudo mdutil -i on /Volumes/X
```

`-E` erases the local store and `-X` removes the index directory without
disabling indexing.

## Time Machine

```bash
sudo tmutil addexclusion -v /Volumes/X
```

`man tmutil`: `-v` configures a volume exclusion, tracked by file system UUID,
and it "is the only supported way to exclude or unexclude a volume; behavior is
undefined if a sticky or fixed-path exclusion is specified". It needs root and
Full Disk Access. Erasing the volume resets Time Machine to its default
behaviour for the new volume, so re-add the exclusion after a reformat.

## Other Tool Caches

```bash
export HOMEBREW_CACHE=/Volumes/X/homebrew-cache
bun install --cache-dir=/Volumes/X/bun-cache
```

`man brew` on `HOMEBREW_CACHE`: "Use this directory as the download cache",
default `~/Library/Caches/Homebrew`. `bun install --help` on `--cache-dir`:
"Store & load cached data from a specific directory path". `bun pm cache` prints
the current path.

## How Each Claim Was Checked

This table covers the storage documents: this file,
[simulator-storage.md](simulator-storage.md) (and its two companions,
[simulator-disk-image.md](simulator-disk-image.md) and
[simulator-startup-line.md](simulator-startup-line.md)) and
[audio-storage.md](audio-storage.md). Some rows are for text that lives in the
other two.

| Claim | Method |
| --- | --- |
| Volume root is root-owned and unwritable | `stat -f`, `touch`, `id -Gn` on the erased volume |
| `enableOwnership` semantics, `volinfo.database` | `man diskutil` |
| Ownership state changed after the erase | two `diskutil info` runs 25 minutes apart |
| `-derivedDataPath`, `-clonedSourcePackagesDirPath` | `xcodebuild -help`, Xcode 27.1 |
| `-archivePath` names the bundle | two `xcodebuild archive` runs, output inspected |
| Xcode settings labels and options | `strings` on the `IDESettingsPanel` and `IDEKit` binaries |
| Xcode preference keys exist | `grep -aow -c` on the `IDEFoundation` binary |
| No Apple article for those settings | search of developer.apple.com |
| `IDECustomDerivedDataLocation` is honoured | `xcodebuild` build with the key set, twice; the default location checked empty afterwards |
| `IDECustomDistributionArchivesLocation` is honoured, and holds a parent | `xcodebuild archive` with the key set and no `-archivePath`, then `find -maxdepth 2` on the volume and `ls` of the default location, which did not exist |
| The bare `defaults write` template works | `extdisk-apfs host --only xcode-derived-data,xcode-archives`, then `defaults read` returned both paths |
| A device set on the volume fails with `EPERM` from `CoreSimulatorService` | `simctl --set` create on the volume, which stuck in `Creating`, then `CoreSimulator.log` (`Code=513` wrapping `Code=1`), against a successful `touch` and `cp -R` as the same user |
| The daemon's removable-volume access causes that `EPERM` | Narrowed by elimination, not observed: `ditto` of the runtime's `SampleContent` onto the volume as the user succeeded, and `simctl --set` create succeeded at `/tmp` and in the home directory, so only the daemon's access to this volume is left. No grant was tried, because `CoreSimulatorService` is absent from the Files and Folders pane and `Terminal` there has no Removable Volumes row |
| Symlinking `CoreSimulator/Caches` breaks runtime install | `xcodebuild -downloadPlatform iOS` through the symlink, which failed at registration |
| Symlinking `CoreSimulator/Devices` breaks device creation | `simctl create` through the symlink, plus `CoreSimulator.log` holding the same "copying sample content" failure at a `Devices` path and at a `--set` path with no symlink |
| The installer export lands on the volume | `xcodebuild -downloadPlatform iOS -buildVersion 27.2 -exportPath` on the volume, then `du -sh` (7.7 GB) and `ls` of `iphonesimulator_27.2_24B114.exportedBundle` |
| `-importPlatform` reinstalls an exported bundle | Documentation only: `xcodebuild -help` lists `-importPlatform <simruntimedmgpath>`. Not run |
| 43 iPad device types with no runtime | `xcrun simctl list devicetypes \| grep -ci ipad`, run before any runtime was installed |
| The default set holds 11 iOS 27.2 devices | `xcrun simctl list devices` after the runtime registered: 5 iPhones and 6 iPads, all `Shutdown`; `iPhone 18 Pro` was booted, reported `Booted`, and shut down |
| Runtimes install and run once those paths are real | `simctl runtime list`, then `simctl create` and `simctl boot` of an iPhone 18 Pro on iOS 27.2 |
| SwiftPM path flags | `swift build --help` |
| `simctl --set` is honoured | `simctl --set` on a missing path, which it rejects by name, and two creates in sets at `/tmp/dsprobe` and `~/dsprobe-home`, each returning a device UUID |
| `CORESIMULATOR_DEVICE_SET_PATH` absent | `strings` on `CoreSimulator` and `simctl` |
| Runtimes have no path option | `xcrun simctl help runtime` |
| `.noindex` excludes a directory | `mdfind` on two sibling directories holding the same file |
| Xcode uses `.noindex` | directory listing after an `xcodebuild archive` run |
| `mdutil` and `tmutil` behaviour | `man mdutil`, `man tmutil` |
| Audio Unit search paths | Apple's Audio Toolbox "Audio Components" page |
| Logic Pro procedure and requirements | Apple support pages 111094 and 102239 |
| Apple Loops excluded from relocation | Logic Pro 10.4 user guide |
| `HOMEBREW_CACHE`, `bun --cache-dir` | `man brew`, `bun install --help` |
| A mount over a non-empty directory shadows it, and eject brings it back | A file `underneath.txt` in the directory, checked with `ls` while the image was mounted (gone) and after `diskutil eject` (back) |
| The image mounts at the default device set and the simulator works there | `diskutil image attach --mountPoint` at `~/Library/Developer/CoreSimulator/Devices`, then `simctl list devices available` (11 devices, the image's own), `simctl create` with no `--set` (a UUID returned) and `simctl boot` (reported `Booted`) |
| A second mount on a mounted path stacks and hides the first | `mount` listed `/dev/disk9s1` and `/dev/disk11s1` on `/Volumes/SimDevices`, and the directory listing dropped from 12 entries to 1 until the eject. Seen by accident, not set up as an experiment |
| A LaunchAgent cannot attach an image on the external volume or read it | One diagnostic LaunchAgent that logged: boot-volume image attach exit 0, external-volume image attach `Operation not permitted`, a plain read of a file on the volume failed. The shell that succeeds fails to read `TCC.db`, so it has no Full Disk Access. Consistent with the removable-volume restriction; no grant was tried, so the mechanism is not identified |
| Xcode reads the mounted device set | `xcrun xctrace list devices` listed the simulators with the image's UUIDs. That is Xcode's tooling, not `simctl`. No Xcode window was observed and there is no `Simulator.app` on this machine |
| `hdiutil create`, `attach` and `detach` are deprecated, and `hdiutil info` is not | The warning each printed on stderr under macOS 27.2, naming the `diskutil` replacement; `hdiutil info 2>err >/dev/null` left `err` at 0 bytes |
| A sparse bundle grows on demand | A `--size 60g` image read 12M when new and 562M after one device was created and booted. The command that read the size was not recorded |
| `diskutil image attach` ignores `--mountPoint` for an image that is already attached | A scratch image attached at `/private/tmp/elsewhere/a`, then attached again with `--mountPoint /private/tmp/elsewhere/b`: it printed `/private/tmp/elsewhere/a`, exited 0, and `mount` showed one mount. Then `simdisk /Volumes/DevAudioStore` against the live image attached at `/private/tmp/elsewhere-mp` exited 1 with the refusal |
| A second attach of the same image at the same point is a no-op, and so are two concurrent ones | `mount` count stayed 1 after the second attach, and stayed 1 after two attaches started together |
| The `mount` test in the startup line is what stops a second volume's block stacking a mount | A second block naming the same set path stacked a mount (measured, as above); `diskutil` covers only the same image at the same point |
| `simdisk` run twice writes the startup file once | The second run printed `skipped: the block ... is already this`, and the count of `.extdisk-backup` files stayed at 2. The tests in `tests/run` assert the file list and contents |
| `simdisk --undo` works with the drive unplugged, and refuses the boot volume | `simdisk /Volumes/GoneDrive --undo` exited 0 with both steps skipped; `simdisk / --undo` exited 1 with `is on the boot volume` |
| A booted simulator holds the mounted device set open | `lsof` on the mounted device set counted 227 open handles with one simulator booted and 0 after `xcrun simctl shutdown all`, macOS 27.2. That this causes the not-ejected-properly report is inferred, not observed |
| `simdisk --undo` refuses while a simulator is booted, and changes nothing | `tests/run-simdisk`, section `a booted simulator stops the eject`: stand-in `xcrun` and `hdiutil`; the call exited non-zero with the startup block kept, and exited 0 with the block removed when nothing was booted. Not run against a real booted simulator |
| A `simctl` that fails warns and does not end `--undo` | A stand-in `xcrun` exiting 72 ended the run at the assignment with no output, before the fix. After it, the same stand-in through `bin/extdisk-apfs`, which is where `set -euo pipefail` is in force, exits 0. Both are checks in `tests/run-simdisk` |
| The drive will not eject while the image is attached | An eject of `/Volumes/DevAudioStore` with the image mounted at the device set failed, and `diskarbitrationd` logged `unmount call ... returned (status code 0x00000010)`, which is `EBUSY`; macOS showed `Disk Not Ejected Properly`. No USB attach or detach event was in the log for that minute, and `disk4` kept its identifier, so the drive did not leave the bus. Which process asked for the eject is redacted by `diskarbitrationd` |
| One eject while the image was in use caused no file system damage but a rebuilt device set | `diskutil verifyVolume` on the SSD (`/dev/rdisk5s1 ... appears to be OK`, `container /dev/rdisk5 appears to be OK`, exit 0) and on the volume inside the image; the 11 stock device folders in the image were replaced by 11 fresh ones (how they were counted was not recorded). One case |
| A sparse bundle does not shrink when files inside are deleted | `du -sh` on the `.sparsebundle` read 778M after a 192 MB leftover device set was deleted inside. The band cause and the effect of a compact are not tested |

The two location keys and the simulator claims were verified by running
`xcodebuild`, `simctl` and a simulator boot, except `-importPlatform` (not run)
and the removable-volume cause of the `EPERM`, which is narrowed by elimination
rather than observed, because no grant could be made, and the LaunchAgent
refusal, whose mechanism is likewise not identified. What is still unverified here was
not verified against a running Xcode.app, Logic Pro or MainStage window: the
settings window was not opened, so that it stores the same keys is not observed,
and neither Logic Pro nor MainStage is installed. Where that mattered, the claim
comes from Apple's own documentation and says so above. The Audio Unit and Logic
Pro sections are in [audio-storage.md](audio-storage.md).

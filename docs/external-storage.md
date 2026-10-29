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
almost entirely no. [simulator-storage.md](simulator-storage.md) has it: device
sets take a `--set` path but creating a device in a set on an external volume
fails with a permission error from `CoreSimulatorService`, symlinking the CoreSimulator directories breaks both runtime installation and
device creation, the runtime itself lives in a system asset location, and the
only part the volume can hold is the downloaded installer bundle. It also
explains why there is no iPadOS runtime to install.

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

This table covers all three storage documents: this file,
[simulator-storage.md](simulator-storage.md) and
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
| A TCC denial causes that `EPERM` | Inference only: the best explanation of `EPERM` on a writable path. No grant was tried, and whether the daemon can be granted access is unknown |
| Symlinking `CoreSimulator/Caches` breaks runtime install | `xcodebuild -downloadPlatform iOS` through the symlink, which failed at registration |
| Symlinking `CoreSimulator/Devices` breaks device creation | `simctl create` through the symlink, plus `CoreSimulator.log` holding the same "copying sample content" failure at a `Devices` path and at a `--set` path with no symlink |
| The installer export lands on the volume | `xcodebuild -downloadPlatform iOS -buildVersion 27.2 -exportPath` on the volume, then `du -sh` (7.7 GB) and `ls` of `iphonesimulator_27.2_24B114.exportedBundle` |
| `-importPlatform` reinstalls an exported bundle | Documentation only: `xcodebuild -help` lists `-importPlatform <simruntimedmgpath>`. Not run |
| 43 iPad device types with no runtime | `xcrun simctl list devicetypes \| grep -ci ipad`, run before any runtime was installed |
| The default set holds 11 iOS 27.2 devices | `xcrun simctl list devices` after the runtime registered: 5 iPhones and 6 iPads, all `Shutdown`; `iPhone 18 Pro` was booted, reported `Booted`, and shut down |
| Runtimes install and run once those paths are real | `simctl runtime list`, then `simctl create` and `simctl boot` of an iPhone 18 Pro on iOS 27.2 |
| SwiftPM path flags | `swift build --help` |
| `simctl --set` is honoured | `simctl --set` on a missing path, which it rejects by name |
| `CORESIMULATOR_DEVICE_SET_PATH` absent | `strings` on `CoreSimulator` and `simctl` |
| Runtimes have no path option | `xcrun simctl help runtime` |
| `.noindex` excludes a directory | `mdfind` on two sibling directories holding the same file |
| Xcode uses `.noindex` | directory listing after an `xcodebuild archive` run |
| `mdutil` and `tmutil` behaviour | `man mdutil`, `man tmutil` |
| Audio Unit search paths | Apple's Audio Toolbox "Audio Components" page |
| Logic Pro procedure and requirements | Apple support pages 111094 and 102239 |
| Apple Loops excluded from relocation | Logic Pro 10.4 user guide |
| `HOMEBREW_CACHE`, `bun --cache-dir` | `man brew`, `bun install --help` |

The two location keys and the simulator claims were verified by running
`xcodebuild`, `simctl` and a simulator boot, except `-importPlatform` (not run)
and the TCC cause of the `EPERM` (an inference). What is still unverified here was
not verified against a running Xcode.app, Logic Pro or MainStage window: the
settings window was not opened, so that it stores the same keys is not observed,
and neither Logic Pro nor MainStage is installed. Where that mattered, the claim
comes from Apple's own documentation and says so above. The Audio Unit and Logic
Pro sections are in [audio-storage.md](audio-storage.md).

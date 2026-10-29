# Putting Development and Audio Data on an External Volume

Once the disk is an APFS volume, the question is which data may live on it. Some
tools take a path. Others search a fixed list of directories, and no setting
adds to that list.

Every claim here was checked on one machine: macOS Darwin 27.2.0, Xcode 27.1
(build 27A9275), `bun` 1.4.4, `/bin/bash` 3.2.57. The method for each claim is
in [How Each Claim Was Checked](#how-each-claim-was-checked). Replace
`/Volumes/X` with your volume's mount point.

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
such article. So the keys are real but undocumented. Set the locations through
the settings window or the `xcodebuild` flags, and treat
`defaults write com.apple.dt.Xcode IDECustomDerivedDataLocation` as unsupported.

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

### Device Sets Take a Path

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

A device set only writes its `device_set.plist` once it holds a device, and this
machine has no simulator runtimes installed, so no device could be created to
show that file appearing in an alternate set. The path validation above is the
evidence that the option is honoured.

### Runtimes Cannot Be Moved

`xcrun simctl help runtime` says `add <path>` adds a runtime disk image "to the
secure storage area", and no subcommand takes a destination. Reclaim the space
instead:

```bash
xcrun simctl runtime delete --outdated --dry-run
xcrun simctl runtime delete --notUsedSinceDays 90
xcrun simctl runtime delete --unusable
xcrun simctl delete unavailable
```

`xcrun simctl help delete`: "Specifying unavailable will delete devices that are
not supported by the current Xcode SDK." `--dry-run` prints what
`runtime delete` would remove without removing it.

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

## Audio Units Cannot Live on an External Volume

Apple's Audio Toolbox documentation for
[Audio Components](https://developer.apple.com/documentation/audiotoolbox/audio-components)
states that the system searches for `.audiocomp` and `.component` bundles in
exactly three locations:

- `~/Library/Audio/Plug-Ins/Components`
- `/Library/Audio/Plug-Ins/Components`
- `/System/Library/Components`

All three are on the boot volume, and no API adds a search path;
`AudioComponentRegister` registers a component in the calling process only. So
an Audio Unit v2 `.component` bundle has to sit in one of those three
directories. An Audio Unit v3 plug-in is delivered as an app extension inside an
application, so its location is wherever that application is installed.

What you can move is the sample content, which each vendor's installer usually
lets you place. Apple's support page
[Where are third-party Audio Units plug-ins installed on Mac?](https://support.apple.com/en-us/102239)
lists the first two directories and says nothing about external volumes.

## Logic Pro and MainStage Content

From Apple's support page
[Move Logic Pro for Mac and MainStage content](https://support.apple.com/en-us/111094):

- **Logic Pro 12 or MainStage 4 or later.** "In the Music folder on your Mac,
  locate the file called "Logic Pro Library.bundle."" Move that bundle to the
  external drive.
- **Logic Pro 11.2.2 or MainStage 3.7.1 or earlier.** Choose "Logic Pro >
  Sound Library > Relocate Sound Library".

The page's own requirements, quoted:

- "You can't store the Sound Library on a volume used for Time Machine backups."
- "Don't rename the storage device or volume after you've moved the Sound
  Lbrary." The misspelling is Apple's.
- "If you have more than one Mac running Logic Pro or MainStage, each Mac needs
  its own Sound Library."
- "Make sure to click Allow when Logic Pro or MainStage asks for permission to
  access the external device."

The page also covers formatting a drive that "isn't formatted for use with Mac",
enabling Removable Volumes under Privacy & Security > Files and Folders if
relocation is refused, and moving the library back.

**Apple Loops are not part of the move.** The Logic Pro 10.4 user guide page
[Manage Logic Pro content](https://help.apple.com/logicpro/mac/10.4/en.lproj/lgcpf77e757d.html)
states that "When you relocate the Sound Library, all Sound Library content
except for Apple Loops and Impulse Responses" "is moved to the new location."
The current support page says nothing about Apple Loops, and Apple documents no
supported way to put them on an external drive. Symlinking them is a user
practice found in Apple Community threads, not a supported configuration.

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

Nothing here was verified against a running Xcode, Logic Pro or MainStage
window, because this machine has no simulator runtimes and neither Logic Pro nor
MainStage installed. Where that mattered, the claim comes from Apple's own
documentation and says so above.

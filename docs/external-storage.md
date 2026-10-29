# Putting Development and Audio Data on an External Volume

Once the disk is an APFS volume, the question becomes which data may live on it.
Some tools take a documented setting for their location. Others have none, and
only a symlink is left, which is a workaround with its own failure mode.

Every command below was read from the man page or the `--help` output of the
copy installed on the machine where this document was written: Xcode at
`/Applications/Xcode.app/Contents/Developer`, `bun` 1.4.4, macOS Darwin 27.2.0.
Run the same command yourself before trusting a flag, because flags change
between versions.

Replace `/Volumes/X` with your volume's mount point.

## Native Settings

### Xcode Derived Data and Archives

The GUI setting is **Xcode > Settings > Locations**, which holds the Derived
Data and Archives locations. That pane is the Xcode user interface, so it is
not verifiable from a man page; everything else in this section was read from
the installed tool.

On the command line, as complete commands:

```bash
xcodebuild -scheme MyApp -derivedDataPath /Volumes/X/DerivedData build
xcodebuild -scheme MyApp -archivePath /Volumes/X/Archives/MyApp.xcarchive archive
```

`xcodebuild -help` describes `-derivedDataPath` as "specifies the directory
where build products and other derived data will go".

The two installed sources disagree about `-archivePath`, so both are quoted
here. `man xcodebuild`: "Specifies the path for the archive produced by the
archive action, or specifies the archive that should be exported". `xcodebuild
-help`: "specifies the directory where any created archives will be placed, or
the archive that should be exported". Pass a `.xcarchive` path for a single
archive and check the result, rather than relying on either reading.

Caveat: the flags apply to one `xcodebuild` invocation. The Locations pane is
what changes the behaviour of the Xcode application itself.

### Swift Packages Fetched by Xcode

```bash
xcodebuild -clonedSourcePackagesDirPath /Volumes/X/SourcePackages
```

From `xcodebuild -help`: "specifies the directory to which remote source
packages are fetch or expected to be found".

### Swift Package Manager on the Command Line

```bash
swift build --scratch-path /Volumes/X/spm-build --cache-path /Volumes/X/spm-cache
```

`swift build --help` lists `--scratch-path`, `--cache-path` and `--config-path`.
The scratch path replaces the per-package `.build` directory, so it has to be
passed on every invocation or set in a wrapper script.

### Simulator Device Set

```bash
xcrun simctl --set /Volumes/X/CoreSimulator list
```

`xcrun simctl help` gives the usage line `simctl [--set <path>] [--profiles
<path>] <subcommand> ...`, so the device set path is an option on every
subcommand.

Caveat: this is a per-invocation flag. Whether the Xcode and Simulator
applications can be pointed at a non-default device set was **not verified**.
The default set stays at `~/Library/Developer/CoreSimulator`.

### Volume Ownership

```bash
sudo diskutil enableOwnership /Volumes/X
```

`man diskutil` on `enableOwnership`: the Volume Database at
`/var/db/volinfo.database` is changed so that the user and group IDs of files on
the volume are taken into account. The setting survives eject, inject and
reboot, and it is stored on the host rather than on the disk, so another Mac
starts with ownership ignored again.

With ownership ignored, every file on the volume appears to belong to whoever
mounted it. `extdisk-apfs verify` prints this as `owners: enabled` or
`owners: disabled`, read from the `GlobalPermissionsEnabled` key of
`diskutil info -plist`.

### Time Machine Exclusion

```bash
sudo tmutil addexclusion -v /Volumes/X
```

`man tmutil`: `-v` configures a volume exclusion, tracked by file system UUID,
and it "is the only supported way to exclude or unexclude a volume; behavior is
undefined if a sticky or fixed-path exclusion is specified". It needs root and
Full Disk Access. Erasing the volume resets Time Machine to its default
behaviour for the new volume, so the exclusion has to be re-added after a
reformat.

### Spotlight Indexing

```bash
sudo mdutil -i off /Volumes/X
```

`man mdutil`: `-i on | off` sets the indexing status for the given volumes.
`-E` erases the local store, and `-X` removes the index directory without
disabling indexing. Turn indexing back on with `sudo mdutil -i on /Volumes/X`.

Whether this measurably speeds up builds was **not verified**. It is a
documented switch, not a benchmarked one.

### Logic Pro and MainStage Sound Library

This section comes from Apple's support article at
<https://support.apple.com/en-us/111094>, not from an installed tool, so check
the page for your Logic Pro version before following it:

- Logic Pro 12 and MainStage 4 and later: drag `~/Music/Logic Pro Library.bundle`
  to the external drive.
- Logic Pro 11.2.2 and MainStage 3.7.1 and earlier: use
  **Sound Library > Relocate Sound Library**.

Apple's requirements on that page: the drive must be APFS or Mac OS Extended
(Journaled), it must not be a Time Machine volume, and the volume must not be
renamed afterwards. Each Mac needs its own copy. macOS may ask for the
Removable Volumes permission under Privacy & Security > Files and Folders.

### Homebrew Download Cache

```bash
export HOMEBREW_CACHE=/Volumes/X/homebrew-cache
```

`man brew` on `HOMEBREW_CACHE`: "Use this directory as the download cache",
default `~/Library/Caches/Homebrew` on macOS.

### Bun Package Cache

```bash
bun install --cache-dir=/Volumes/X/bun-cache
```

`bun install --help` on `--cache-dir`: "Store & load cached data from a specific
directory path". The current cache path is printed by `bun pm cache`.

## No Native Mechanism Found

For each item here, the installed tool offers no path option. A symlink from the
default location to the external volume is the only remaining approach, and it
is a workaround, not a supported configuration.

The risk of every such symlink is the same: when the volume is not mounted, the
link dangles. What a given tool then does was not tested here, and it varies.
The outcome to watch for is a tool that recreates the directory on the boot
disk, because that silently undoes the move and refills the internal disk
without an error.

### Simulator Runtimes

`xcrun simctl help runtime` says `add <path>` adds a runtime disk image "to the
secure storage area", and no subcommand takes a destination path. Reclaim space
instead of moving it:

```bash
xcrun simctl runtime delete --outdated --dry-run
xcrun simctl runtime delete --notUsedSinceDays 90
xcrun simctl runtime delete --unusable
xcrun simctl delete unavailable
```

`xcrun simctl help delete`: "Specifying unavailable will delete devices that are
not supported by the current Xcode SDK." `--dry-run` on `runtime delete` prints
what would be removed without removing it.

### Xcode Device Support

`~/Library/Developer/Xcode/iOS DeviceSupport` holds symbol files for connected
devices. No flag for it appears in `xcodebuild -help` or `xcrun simctl help`.
Deleting the directories for OS versions you no longer debug is the simpler
option than symlinking the whole folder. Whether Xcode refetches them on the
next device connection was not tested here.

### Audio Unit Plug-Ins

Audio Units are scanned in `/Library/Audio/Plug-Ins/Components` and
`~/Library/Audio/Plug-Ins/Components` (<https://support.apple.com/en-us/102239>).
There is no setting that adds a search path. Whether a `.component` bundle works
when symlinked from an external volume was **not verified**, and reports
conflict, so keep the plug-ins themselves internal and move only their sample
content, which each vendor's installer usually lets you place.

## Not Verified

Stated here so that nobody treats the list above as complete:

- The `defaults` keys behind the Xcode Locations pane. The pane is the
  documented interface; `defaults read com.apple.dt.Xcode
  IDECustomDerivedDataLocation` returned "Could not find key" on an untouched
  install, so the key name could not be confirmed from the installed copy.
- Whether the Xcode and Simulator applications honour a non-default
  `simctl --set` device set.
- Whether Spotlight or Time Machine exclusion changes build times.
- Audio Unit bundles and Apple Loops on an external volume.
- The two Apple support pages linked here were not opened from this machine.
  They are cited as the source of their claims, not confirmed by it.
- The names of GUI panes, such as Xcode > Settings > Locations and Logic Pro's
  Sound Library menu, were not checked against a running application.
- Everything else above was read on macOS Darwin 27.2.0 with one Xcode install.
  No claim is made for other versions.

# `extdisk-apfs`

[![check](https://github.com/xsyetopz/extdisk-apfs/actions/workflows/check.yml/badge.svg)](https://github.com/xsyetopz/extdisk-apfs/actions/workflows/check.yml)

Reclaim an external USB or Thunderbolt disk as one APFS volume on a GUID
partition map, using macOS `diskutil`. Written for the case of an SSD or HDD
that currently holds something else, such as a Ventoy installer, a Windows
layout, or an old backup.

The erase itself is one documented command:

```bash
diskutil eraseDisk APFS <label> GPT /dev/diskN
```

This tool adds the part that is easy to get wrong: finding out which `diskN` the
external disk actually is, showing what would be destroyed, and refusing every
target that is not an external physical whole disk. Disk identifiers are
renumbered on every attach, so `disk4` today can be a different disk tomorrow.

## Requirements

- macOS, with `diskutil`, `plutil`, `md5` and `bash`. All four ship with the
  system. `/bin/bash` is bash 3.2 on macOS, and the code stays inside it.
- No installation step and no dependencies.

## Install

```bash
git clone https://github.com/xsyetopz/extdisk-apfs.git
cd extdisk-apfs
./bin/extdisk-apfs list
```

To run it from anywhere, symlink it onto your `PATH`:

```bash
ln -s "$PWD/bin/extdisk-apfs" /opt/homebrew/bin/extdisk-apfs
```

The script follows the symlink to its own directory, so `lib` and `data` are
found without any variable. `EXTDISK_LIB` and `EXTDISK_HOSTS` override those
two paths if you need them elsewhere.

## Use

```bash
extdisk-apfs list                 # external physical disks, as candidates
extdisk-apfs show disk4           # its partition map and mounted volumes
extdisk-apfs erase disk4 --label Scratch --dry-run
extdisk-apfs erase disk4 --label Scratch --own
extdisk-apfs verify disk4         # partition map, container, volume, capacity
extdisk-apfs hosts /Volumes/Scratch        # what can keep data there
extdisk-apfs explain cargo-home            # one entry, with its source
extdisk-apfs host /Volumes/Scratch         # apply what can be persisted
extdisk-apfs unhost /Volumes/Scratch       # undo exactly that
extdisk-apfs simdisk /Volumes/Scratch --dry-run   # simulator devices, in an image
extdisk-apfs simdisk /Volumes/Scratch --size 60g  # the ceiling of the image
extdisk-apfs simdisk /Volumes/Scratch --undo      # keeps the image
```

`list` output on the machine this was written on:

```text
External physical disks
  IDENT    MEDIA NAME               SIZE       BUS    SSD    CONTENT
  disk4    SP PD60                  256.1 GB   USB    yes    GUID_partition_scheme

  erase applies further checks and may refuse one of these
```

`list` filters only by `diskutil list external physical`. It does not pre-apply
the rest of the refusals, so a disk it lists can still be refused by `erase`,
for example a write-protected one.

`erase` prints the layout, states what will change, requires you to retype the
identifier, and then re-runs every check before writing anything.

### Options for `erase`

| Option | Effect |
| --- | --- |
| `--label <name>` | Volume name. Required, because `diskutil eraseDisk` takes one as a positional argument. |
| `--case-sensitive` | Use the `Case-sensitive APFS` personality. The default `APFS` personality is case-insensitive. |
| `--own` | `chown` the new volume's root directory to you, so that you can write to it. |
| `--enable-owners` | Run `diskutil enableOwnership`, so file owners on the volume are honoured. |
| `--no-spotlight` | `mdutil -i off` for the new volume. |
| `--no-timemachine` | `tmutil addexclusion -v` for the new volume. |
| `--dry-run` | Print every command, run none of them. |
| `--force` | Skip the typed confirmation. For scripts. |

Those four settings each run a `sudo` command, so they ask for an administrator
password. `--no-timemachine` also needs Full Disk Access for your terminal, per
`man tmutil`.

### A New Volume Is Not Yours

`diskutil eraseDisk` leaves the volume's root directory owned by `root`. On the
disk this was developed against it was `root:wheel drwxrwxr-x`, and the console
user is in `staff`, so `touch /Volumes/DevAudioStore/probe` failed with
`Permission denied` right after a successful format. `--own` runs
`sudo chown "$(id -u):$(id -g)"` on the new volume's root directory, which is
the fix. After an erase without it:

```bash
sudo chown "$(id -u):$(id -g)" /Volumes/X
```

`erase` ends by printing the owner, the mode, your user and group, and whether
you can write, so this does not surface later as a permission error from an
unrelated tool.

`--enable-owners` is a different thing. Per `man diskutil`, `enableOwnership`
makes the on-disk user and group IDs count, by editing the Volume Database on
the host; it does not give you access to a root-owned directory. Use it when
you will restore a tree whose owners must survive.

## Hosting Application Data

A formatted volume is only useful once applications keep data on it. Which ones
can is not a matter of opinion: either the vendor documents a setting or it does
not. `data/hosts.tsv` is that answer, one application per line with the source
it came from, and the tool reads it.

```bash
$ extdisk-apfs hosts /Volumes/Scratch

  dev
  ID                       NAME                                   HOSTS    HOW    INSTALLED
  homebrew-cache           Homebrew download cache                partial  env    yes
  npm-cache                npm package cache                      partial  cli    yes
  cargo-home               Rust Cargo home                        full     env    yes
  xcode-derived-data       Xcode derived data                     partial  cli    yes
  simulator-runtimes       Simulator runtimes                     none     none   yes
```

`HOW` is the mechanism, and it decides what `host` can do:

| Mechanism | `extdisk-apfs host` |
| --- | --- |
| `cli` | Runs the tool's own command, such as `npm config set cache=PATH`. `unhost` runs the documented undo. |
| `env` | Writes the variable into a marked block in `~/.zshenv`, or `~/.bash_profile` under bash. `unhost` removes the block. |
| `flag` | Prints it. A per-invocation flag such as `xcodebuild -derivedDataPath` has nothing to persist. |
| `file` | Prints it. The key belongs in a config file this tool will not rewrite for you. |
| `ui` | Prints the steps. The setting lives in a graphical application. |
| `none` | Says why nothing can move, such as Audio Units, which load from three fixed directories on the boot volume. |

`host` creates the directories and applies the first two. It copies, moves and
deletes nothing: a cache refills itself, and a sample library is yours to drag
by the vendor's own procedure. `unhost` undoes only what `host` wrote, and only
where the setting still points at that volume; the directories and their
contents stay. It does not touch the `simulator <volume>` block that `simdisk`
writes; `simdisk <volume> --undo` removes that one.

`extdisk-apfs explain <id>` shows one entry with its source and its
requirements. [docs/hosts.md](docs/hosts.md) describes the file format, how to
add an entry, and the gaps where no vendor page could be read.

### The Simulator

`CoreSimulatorService` refuses to create a simulator device in a device set on a
removable volume (`EPERM`), and no permission can be granted, so the catalogue
lists the simulator device set as not hostable by a directory. A disk image on
the same volume is not refused. `simdisk` creates a sparse bundle there
(`--size` is its ceiling, default `60g`, and it grows on demand) and mounts it
directly at `~/Library/Developer/CoreSimulator/Devices`, which Xcode reads
(`xcrun xctrace list devices` lists the image's simulators). Nothing is moved,
copied or linked: the directory that was there is shadowed while the image is
mounted, its devices are invisible meanwhile, and they are back after the image
is ejected. Before it creates or attaches anything it reads the state of that
path, one of five: `ours` (the image is attached there, so it skips), `free`
(it proceeds), and three it refuses, `link` (a symlink cannot be a mount point),
`foreign` (another volume is mounted there, and a second mount would hide it)
and `elsewhere` (the image is attached at another point, and `diskutil` ignores
`--mountPoint` for an attached image). A line in your shell startup file, in a
block keyed `simulator <volume>`, attaches the image in each new shell and is
silent when the drive is absent. The line only runs when a shell starts, so
Xcode launched from the Dock before any shell has run uses the device set on
the internal disk. A LaunchAgent that was tried could not attach the image or
read the volume (`Operation not permitted`) while it could attach a boot-volume
image; that is consistent with the removable-volume restriction, no grant was
tried, and the mechanism is not identified. Quit Xcode before the first mount;
whether a running Xcode keeps the old directory is untested. Running `simdisk`
twice changes nothing the second time, and makes no second backup of the startup
file: measured, the backup count stayed at 2. `--undo` removes the line and
ejects the image, refuses while a simulator is booted
([why](docs/simulator-startup-line.md#a-booted-simulator-stops-the-eject)), works with the drive unplugged, and leaves the image file,
because removing it destroys the devices inside. Run it before unplugging the
drive: while the image is attached the drive itself will not eject, and macOS
reports a half-finished eject as `Disk Not Ejected Properly`
([measured](docs/simulator-startup-line.md#eject-the-image-before-unplugging-the-drive)). `unhost` leaves the
`simulator <volume>` block alone; only `simdisk --undo` removes it. If an attach
fails, a newly created image and device set directory stay; a re-run is
idempotent and `--undo` removes neither
([where to find them](docs/simulator-startup-line.md#what-a-failed-run-leaves)).
[docs/simulator-storage.md](docs/simulator-storage.md) has the refusal,
[docs/simulator-disk-image.md](docs/simulator-disk-image.md) the image, and
[docs/simulator-startup-line.md](docs/simulator-startup-line.md) the startup line
and its measurements.

## Which Targets Are Refused

`erase` stops, with the reason named, when the target is:

- not a disk identifier. The digits are stripped and the remaining shape must
  be `disk`, `disks` or `diskss`, so `disk0/../disk4`, `disk4;x` and `disk*`
  never reach `diskutil`.
- unknown to `diskutil`
- a partition or a volume rather than a whole disk, and it then names the whole
  disk to use instead
- an internal disk
- virtual, which covers disk images and synthesized APFS containers
- absent from `diskutil list external physical`, which is the authority on what
  counts as external and physical
- marked as OS internal media, or not writable
- the boot disk, or any disk carrying part of the boot disk's storage

Every fact behind those checks is read from `diskutil info -plist` and
`diskutil list -plist`, never from the human-readable columns, which are not a
stable interface. Each check compares against the value that would permit the
erase, so an absent key or a failed `diskutil` call refuses rather than
permits. If the boot disk cannot be determined at all, `erase` refuses outright
instead of treating "no boot disk" as "no conflict".

Three details are worth knowing, because each one is a way a simpler tool gets
this wrong.

**APFS volumes are not listed under the disk they live on.** The container is
synthesized as a separate `diskN`, so the tool follows
`APFSContainerReference` out of each `Apple_APFS` partition. That is why `show`
and `erase` list the APFS volumes an erase would destroy, and why
`disk5s1` is correctly reported as a volume of `disk4`. A tool that reads only
the physical disk's partition list prints "none mounted" and hides them.

**A container can have more than one physical store.** A Fusion Drive container
spans two disks, so the tool walks `APFSPhysicalStores` by index rather than
reading entry zero. Reading only entry zero would let the second disk of a pair
through the boot-disk check.

**The identifier is re-checked after you confirm.** Between the prompt and the
erase, the disk can be unplugged and another one can take its identifier. The
tool fingerprints the media name, the size, the block size and the full
partition layout with `md5` before the prompt, then re-runs every refusal and
compares the fingerprint before erasing. `--force` skips the prompt but not
this re-check.

## What This Does Not Do

- **No secure erase, and no overwrite passes.** The goal is reuse, not
  certified destruction. `eraseDisk` writes a new partition map and a new file
  system; it does not overwrite every block. Old data stops being reachable
  through a file system. `man diskutil` documents `zeroDisk` for writing zeros,
  but on flash storage this tool makes no claim about what remains recoverable
  afterwards, because that depends on the drive's controller and was not
  measured. For data that must be unrecoverable, encrypt from the start, or use
  the drive's own sanitize facility.
- **No internal disks.** By design. See the refusals above.
- **No data migration.** Nothing is copied, moved, or symlinked, by `erase` or
  by `host`. `host` creates empty directories and writes settings; the data
  that lands in them arrives because an application put it there.
  The long-form evidence is in three files, each separating the documented
  settings from the workarounds that were tried and from those that failed:
  [docs/external-storage.md](docs/external-storage.md) for Xcode, Spotlight and
  Time Machine, [docs/simulator-storage.md](docs/simulator-storage.md) for the
  iOS Simulator, and [docs/audio-storage.md](docs/audio-storage.md) for Audio
  Units and Logic Pro.
- **No multi-partition layouts.** One APFS volume on the whole disk. For more,
  `diskutil apfs addVolume` adds volumes to the container afterwards, and they
  share its free space.
- **No guarantee against a disk swapped at exactly the wrong moment.** The
  fingerprint check closes the window it can observe. A replacement disk with
  the same media name, size and partition layout would pass it.

## Notes on APFS

- The plain `APFS` personality is case-insensitive. `diskutil listFilesystems`
  lists it next to `Case-sensitive APFS`. It is the default here because it
  matches the macOS system volumes, which `diskutil apfs list` reports as
  `Case-insensitive`.
- `eraseDisk` creates an EFI system partition alongside the APFS container,
  209.7 MB on the 256 GB disk this was developed against. That is normal for a
  GPT disk on a Mac, and `diskutil verifyDisk` checks it.
- APFS is offered for a mechanical HDD as well, and this tool does not refuse
  one. Whether APFS or HFS+ performs better on a given HDD is not measured
  here, so no recommendation is made.

## Development

Run `scripts/check` before a change; CI runs the same script. The checks, the
opt-in hardware tests and the table of which file holds which concern are in
[docs/development.md](docs/development.md).

## License

MIT. See [LICENSE](LICENSE).

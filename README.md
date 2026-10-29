# `extdisk-apfs`

Reclaim an external USB or Thunderbolt disk as one APFS volume on a GUID
partition map, using macOS `diskutil`. Written for the case of an SSD or HDD
that currently holds something else, such as a Ventoy installer, a Windows
layout, or an old backup.

The erase itself is one documented command:

```
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

```
git clone https://github.com/xsyetopz/extdisk-apfs.git
cd extdisk-apfs
./bin/extdisk-apfs list
```

To run it from anywhere, put `bin` on your `PATH`, or symlink
`bin/extdisk-apfs` and set `EXTDISK_LIB` to the repository's `lib` directory.

## Use

```
extdisk-apfs list                 # external physical disks, as candidates
extdisk-apfs show disk4           # its partition map and mounted volumes
extdisk-apfs erase disk4 --label Scratch --dry-run
extdisk-apfs erase disk4 --label Scratch --enable-owners
extdisk-apfs verify disk4         # partition map, container, volume, capacity
```

`list` output on the machine this was written on:

```
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
|---|---|
| `--label <name>` | Volume name. Required, because `diskutil eraseDisk` takes one as a positional argument. |
| `--case-sensitive` | Use the `Case-sensitive APFS` personality. The default `APFS` personality is case-insensitive. |
| `--enable-owners` | Run `diskutil enableOwnership`, so file owners on the volume are honoured. |
| `--no-spotlight` | `mdutil -i off` for the new volume. |
| `--no-timemachine` | `tmutil addexclusion -v` for the new volume. |
| `--dry-run` | Print every command, run none of them. |
| `--force` | Skip the typed confirmation. For scripts. |

`--enable-owners`, `--no-spotlight` and `--no-timemachine` each run a `sudo`
command, so they ask for an administrator password. `--no-timemachine` also
needs Full Disk Access for your terminal, per `man tmutil`.

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
- **No data migration.** Nothing is copied, moved, or symlinked. Where
  development and audio data may go afterwards is in
  [docs/external-storage.md](docs/external-storage.md), which separates the
  documented settings from the symlink workarounds.
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

```
shellcheck --shell=bash --external-sources bin/extdisk-apfs lib/*.sh
./bin/extdisk-apfs erase diskN --label Test --dry-run
```

`--dry-run` exercises the full path, including every guard and the
post-confirmation re-check, without writing anything, so it is the way to test
a change against a real disk. In a dry run the post-format commands print a
placeholder instead of a mount point, because the volume does not exist yet and
naming a path that belongs to another volume would be misleading.

The code is split by concern:

| File | Concern |
|---|---|
| `lib/diskinfo.sh` | Facts, read from `diskutil`'s plists |
| `lib/guard.sh` | The refusals, and nothing else |
| `lib/inspect.sh` | Listing candidates and showing a layout |
| `lib/erase.sh` | The destructive step and the post-format settings |
| `lib/verify.sh` | The report after a format |
| `lib/ui.sh` | Output, shell quoting, the confirmation prompt |

## License

MIT. See [LICENSE](LICENSE).

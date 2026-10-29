# Extdisk-Apfs

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

- macOS, with `diskutil`, `plutil` and `bash`. All three ship with the system.
- No installation step and no dependencies.

## Install

```
git clone https://github.com/xsyetopz/extdisk-apfs.git
cd extdisk-apfs
./bin/extdisk-apfs list
```

To run it from anywhere, put `bin` on your `PATH`, or symlink `bin/extdisk-apfs`
and set `EXTDISK_LIB` to the repository's `lib` directory.

## Use

```
extdisk-apfs list                 # external physical disks you may erase
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
```

`erase` prints the layout, states what will change, and then requires you to
retype the identifier. A wrong identifier on the command line cannot by itself
destroy a disk.

### Options for `erase`

| Option | Effect |
|---|---|
| `--label <name>` | Volume name. Required, because `diskutil eraseDisk` takes one as a positional argument. |
| `--case-sensitive` | Use the `Case-sensitive APFS` personality. The default `APFS` personality is case-insensitive, which is what macOS itself uses. |
| `--enable-owners` | Run `diskutil enableOwnership`, so file owners on the volume are honoured. |
| `--no-spotlight` | `mdutil -i off` for the new volume. |
| `--no-timemachine` | `tmutil addexclusion -v` for the new volume. |
| `--dry-run` | Print every command, run none of them. |
| `--force` | Skip the typed confirmation. For scripts. |

The last three options need an administrator password, and
`--no-timemachine` also needs Full Disk Access for your terminal.

## Which Targets Are Refused

`erase` stops, with the reason named, when the target is:

- not a disk identifier of the form `diskN`, or unknown to `diskutil`
- a partition or a volume rather than a whole disk, and it then tells you the
  whole disk to use instead
- an internal disk
- virtual, which covers disk images and synthesized APFS containers
- absent from `diskutil list external physical`, which is the authority on what
  counts as external and physical
- marked as OS internal media, or not writable
- the boot disk, or any disk carrying part of the boot disk's storage

Every fact behind those checks is read from `diskutil info -plist` and
`diskutil list -plist`, never from the human-readable columns, which are not a
stable interface.

One check is worth knowing about: an APFS volume does not appear in the listing
of the physical disk it lives on, because the container is synthesized as a
separate `diskN`. The tool follows `APFSContainerReference` from each
`Apple_APFS` partition, so `show` and `erase` list the APFS volumes that an
erase would destroy. A tool that only reads the physical disk's partition list
reports "none mounted" and hides them.

## What This Does Not Do

- **No secure erase, and no overwrite passes.** The goal is reuse, not certified
  destruction. `eraseDisk` writes a new partition map and a new file system; it
  does not overwrite every block. Old data is unreachable through the file
  system, not provably gone from the flash. `diskutil zeroDisk` exists for
  overwriting, and on an SSD it costs a full write cycle while wear levelling
  still keeps some blocks out of reach. For data that must be unrecoverable, use
  full-disk encryption from the start, or the drive's own sanitize command.
- **No internal disks.** By design. See the refusals above.
- **No data migration.** Nothing is copied, moved, or symlinked. Where
  development and audio data may go afterwards is in
  [docs/external-storage.md](docs/external-storage.md), which separates the
  documented settings from the symlink workarounds.
- **No multi-partition layouts.** One APFS volume on the whole disk. For more,
  `diskutil apfs addVolume` adds volumes to the container afterwards, and they
  share its free space.

## Notes on APFS

- The plain `APFS` personality is case-insensitive. `diskutil listFilesystems`
  lists it next to `Case-sensitive APFS`. Case-insensitive matches the macOS
  boot volume and avoids tools that assume it, so it is the default here.
- `eraseDisk` creates a 209.7 MB EFI system partition alongside the APFS
  container. That is normal for a GPT disk on a Mac, and `diskutil verifyDisk`
  checks it.
- Apple designed APFS for solid-state storage. It is also offered for a
  mechanical HDD, and this tool does not refuse one. Whether APFS or HFS+ is
  faster on a given HDD is not measured here, so no recommendation is made.

## Development

```
shellcheck --shell=bash --external-sources bin/extdisk-apfs lib/*.sh
./bin/extdisk-apfs erase diskN --label Test --dry-run
```

`--dry-run` exercises the full path, including every guard, without writing
anything, so it is the way to test a change against a real disk.

The code is split by concern: `lib/diskinfo.sh` reads `diskutil`'s plists,
`lib/inspect.sh` finds and refuses targets, `lib/erase.sh` holds the destructive
step and the post-format settings, `lib/verify.sh` reports, and `lib/ui.sh` does
output and the confirmation prompt.

## License

MIT. See [LICENSE](LICENSE).

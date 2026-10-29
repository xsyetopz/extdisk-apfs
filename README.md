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
  xcode-derived-data       Xcode derived data                     partial  flag   yes
  simulator-runtimes       Simulator runtimes                     none     none   yes
```

`HOW` is the mechanism, and it decides what `host` can do:

| Mechanism | `extdisk-apfs host` |
|---|---|
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
contents stay.

`extdisk-apfs explain <id>` shows one entry with its source and its
requirements. [docs/hosts.md](docs/hosts.md) describes the file format, how to
add an entry, and the gaps where no vendor page could be read.

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
  [docs/external-storage.md](docs/external-storage.md) is the long-form
  evidence behind the Xcode, simulator, Spotlight, Time Machine and Audio Unit
  entries, and it separates the documented settings from the symlink
  workarounds.
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

```bash
scripts/check              # everything below, in order
scripts/check lint         # shellcheck
scripts/check syntax       # bash 3.2 parse check
scripts/check exec         # file modes
scripts/check actions      # actionlint over .github/workflows
scripts/check tests        # tests/run
```

`scripts/check` is what CI runs, so a green run locally is a green run there.
The checks are:

- **`shellcheck`** over every shell file, including `tests/run` and
  `scripts/check` themselves. The settings live in `.shellcheckrc`, so an
  editor plugin reports the same findings: `shell=bash` because the library
  files have no shebang and would otherwise be read as POSIX `sh`,
  `external-sources` and `source-path=SCRIPTDIR` so the `.` lines are followed,
  and four optional checks. `check-extra-masked-returns` is deliberately off:
  it fired 98 times, every one on `dk_get`, which reports an unknown value as
  empty output and exits zero by design.
- **`bash -n`** with `/bin/bash` specifically, which is bash 3.2.57. The tool
  has to run under the bash that macOS ships, not under a newer one from
  Homebrew.
- **File modes.** `bin/extdisk-apfs`, `tests/run` and `scripts/check`
  executable; every `lib/*.sh` not executable, because they are sourced and
  have no shebang.
- **`actionlint`**, which also runs `shellcheck` over each `run:` block in the
  workflow.
- **`tests/run`**, every check that needs no external disk. It reports the
  counts it ran, and one check is skipped unless you opt in below.

Install the two linters with `brew install shellcheck actionlint`.

Each test asserts on an exit status or a returned value, never on the wording
of a message. The hardware facts are read from whichever disk holds the running
system rather than from a hardcoded `disk0`, so the suite also passes on a VM
or a CI runner. The destructive path is covered by the refusals and by a dry
run; to include the accepting side of `guard_target`, name a real external disk:

```bash
EXTDISK_TEST_DISK=disk4 tests/run
```

That adds three checks and still writes nothing: it dry-runs an erase of that
disk and asserts that `guard_unchanged` accepts a matching fingerprint and
refuses a changed one.

A dry run is also how to test a change by hand:

```bash
./bin/extdisk-apfs erase diskN --label Test --dry-run
```

It exercises the full path, including every guard and the post-confirmation
re-check, without writing anything. In a dry run the post-format commands print
a placeholder instead of a mount point, because the volume does not exist yet
and naming a path that belongs to another volume would be misleading.

The code is split by concern:

| File | Concern |
| --- | --- |
| `bin/extdisk-apfs` | Loading the modules and dispatching one command |
| `lib/cli.sh` | The usage text and each command's options |
| `lib/diskinfo.sh` | Facts, read from `diskutil`'s plists |
| `lib/guard.sh` | The refusals, and nothing else |
| `lib/inspect.sh` | Listing candidates and showing a layout |
| `lib/erase.sh` | The destructive step and the post-format settings |
| `lib/verify.sh` | The report after a format |
| `lib/hosts.sh` | Reading the host catalogue and reporting it |
| `lib/adopt.sh` | Writing the settings that point an app at the volume |
| `lib/ui.sh` | Output, shell quoting, the confirmation prompt |
| `data/hosts.tsv` | The catalogue: one application per line, with its source |
| `tests/run` | The checks that need no external disk |
| `scripts/check` | Every check, for a shell and for CI |

## License

MIT. See [LICENSE](LICENSE).

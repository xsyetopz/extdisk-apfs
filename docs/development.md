# Development

```bash
scripts/check              # everything below, in order
scripts/check lint         # shellcheck
scripts/check syntax       # bash 3.2 parse check
scripts/check exec         # file modes
scripts/check actions      # actionlint over .github/workflows
scripts/check tests        # tests/run, then tests/run-simdisk
```

`scripts/check` is what CI runs, so a green run locally is a green run there.
The checks are:

- **`shellcheck`** over every shell file, including `tests/run`,
  `tests/run-simdisk`, `tests/helpers.sh` and `scripts/check` themselves. The settings live in `.shellcheckrc`, so an
  editor plugin reports the same findings: `shell=bash` because the library
  files have no shebang and would otherwise be read as POSIX `sh`,
  `external-sources` and `source-path=SCRIPTDIR` so the `.` lines are followed,
  and four optional checks. `check-extra-masked-returns` is deliberately off:
  it fired 98 times, every one on `dk_get`, which reports an unknown value as
  empty output and exits zero by design.
- **`bash -n`** with `/bin/bash` specifically, which is bash 3.2.57. The tool
  has to run under the bash that macOS ships, not under a newer one from
  Homebrew.
- **File modes.** `bin/extdisk-apfs`, `tests/run`, `tests/run-simdisk` and
  `scripts/check` executable; every `lib/*.sh` not executable, because they are sourced and
  have no shebang.
- **`actionlint`**, which also runs `shellcheck` over each `run:` block in the
  workflow.
- **`tests/run`** and **`tests/run-simdisk`**, every check that needs no
  external disk. Each reports the counts it ran. `tests/run` skips its hardware
  checks unless you opt in below; `tests/run-simdisk` never needs hardware and
  never attaches an image or asks the real simulator anything: its `hdiutil` and
  its `xcrun` are stand-ins inside the temporary directory, put first on `PATH`
  for the two sections that need them and taken off again with the check that
  says so.

Install the two linters with `brew install shellcheck actionlint`.

Each test asserts on an exit status or a returned value, never on the wording
of a message. The hardware facts are read from whichever disk holds the running
system rather than from a hardcoded `disk0`, so the suite also passes on a VM
or a CI runner. The destructive path is covered by the refusals and by a dry
run; to include the accepting side of `guard_target`, name a real external disk:

```bash
EXTDISK_TEST_DISK=disk4 EXTDISK_TEST_VOLUME=/Volumes/Scratch tests/run
```

`EXTDISK_TEST_DISK` adds five checks and still writes nothing: it dry-runs an
erase of that disk, with and without the post-format steps, refuses the same
erase with no `--label`, and asserts that `guard_unchanged` accepts a matching
fingerprint and refuses a changed one.

`EXTDISK_TEST_VOLUME` adds nine more: the accepting side of `guard_volume`, and
`hosts`, `host`, `unhost`, `explain` and the two `simdisk` forms against a real
mount point. Every one is a dry run, and the last check asserts that no
directory appeared on the volume. `EXTDISK_ENV_FILE` points into the temporary
directory, but `HOME` is deliberately the real one for the two `simdisk` checks:
a dry run writes nothing, and with a scratch `HOME` an image that is attached at
the real device set path reads as attached elsewhere, which is a refusal.

That last check is skipped, not failed, when the volume cannot be listed at
either end. A volume that unmounts mid-run makes `find` print nothing and exit
non-zero, and comparing that to the entries taken before reports every entry on
the volume as created by a dry run. That happened once on the machine this was
written on. The evidence is the run's own output: `find: /Volumes/DevAudioStore:
No such file or directory` on stderr, then the check's failure message listing
17 entries as changed, every one of which already existed. The snapshots now go
through a function that returns `find`'s status, so an unreadable volume is
reported as what it is. The cause was outside the suite: an eject of the volume
was requested while the simulator image on it was mounted, and `diskarbitrationd`
logged `unmount call ... returned (status code 0x00000010)`, which is `EBUSY`.

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
| `lib/envblock.sh` | The marked blocks in the shell startup file: find the file, write, read and strip a block |
| `lib/adopt.sh` | Applying a catalogue row: the commands, the environment lines and the undo |
| `lib/simdisk.sh` | The simulator disk image, its mount at the device set, and their undo |
| `lib/simhook.sh` | The shell startup line that attaches that image |
| `lib/ui.sh` | Output, shell quoting, the confirmation prompt |
| `data/hosts.tsv` | The catalogue: one application per line, with its source |
| `tests/run` | The checks that need no external disk, and the optional hardware dry runs |
| `tests/run-simdisk` | The `simdisk` and startup line checks, with a stand-in `hdiutil` and `xcrun` |
| `tests/helpers.sh` | The counters, the scratch directory and the assertions that both test files share |
| `scripts/check` | Every check, for a shell and for CI |

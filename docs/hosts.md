# The Host Catalogue

An external APFS volume is useful once applications keep data on it. Which
applications can is not a matter of opinion: either the vendor documents a
setting or it does not. `data/hosts.tsv` is that answer in one file, and
`extdisk-apfs` reads it.

```bash
extdisk-apfs hosts /Volumes/X          # what is installed and what it can host
extdisk-apfs hosts --all               # the whole catalogue
extdisk-apfs explain cargo-home        # one entry, with its source
extdisk-apfs host /Volumes/X --dry-run # every command, nothing written
extdisk-apfs host /Volumes/X           # apply what a tool can persist
extdisk-apfs unhost /Volumes/X         # undo exactly that
```

## What `host` Does and Does Not Do

`host` creates the directories, then acts by mechanism:

| Mechanism | What happens |
|---|---|
| `cli` | The tool's own command runs, such as `npm config set cache=PATH`. Persistent, and `unhost` runs the documented undo. |
| `env` | The variable goes into a marked block in your shell startup file. `unhost` removes the block. |
| `flag` | Printed. A per-invocation flag such as `xcodebuild -derivedDataPath` has nothing to persist. |
| `file` | Printed. The key belongs in a config file whose format this tool will not rewrite for you. |
| `ui` | Printed. The setting lives in a graphical application, so the steps are yours to follow. |
| `none` | Nothing can move, and the entry says why. |

It never copies, moves, or deletes application data. A cache that moves refills
itself; a library that moves is yours to drag, by the vendor's own procedure.

`host` refuses a volume that is not the mount point of a volume on an external
physical disk, or that you cannot write to. The reasons are the same as for
`erase`, and the message names the `chown` to run.

### The Environment Block

Variables go to `~/.zshenv` under zsh, or `~/.bash_profile` under bash, chosen
from `$SHELL`. zsh reads `.zshenv` for every shell, including the
non-interactive one a build tool gets from an editor, which is why it is that
file and not `.zshrc`.

```sh
# >>> extdisk-apfs /Volumes/X >>>
export HOMEBREW_CACHE="/Volumes/X/homebrew-cache"
export CARGO_HOME="/Volumes/X/cargo-home"
# <<< extdisk-apfs /Volumes/X <<<
```

The file is copied to `<file>.extdisk-backup.<timestamp>` before the first
change. Writing twice replaces the block rather than adding a second one, a
second volume gets its own block, and `unhost` removes one block by its
markers and leaves every other line alone. A new shell picks the variables up;
the one you ran the command in does not.

Set `EXTDISK_ENV_FILE` to write somewhere else, which is what the tests do.

## The File Format

Tab-separated, twelve fields. `extdisk-apfs validate` checks every row, and so
does `tests/run`, so a malformed row fails CI.

| Field | Meaning |
|---|---|
| `id` | kebab-case and unique. This is what `--only` and `explain` take. |
| `category` | `dev`, `apple`, `audio` or `container`. |
| `name` | What a person reads. |
| `scope` | `full` for the whole data directory, `partial` for a cache or a media folder, `none` when nothing can move. |
| `detect` | `cmd:NAME`, `path:PATH`, `glob:PATTERN` or `always`. |
| `kind` | `cli`, `env`, `ui`, `flag`, `file` or `none`, as in the table above. |
| `subdir` | The directory to create on the volume, or `-`. |
| `setting` | The argv template, variable name, flag or steps, with `%s` for the path. |
| `query` | For `cli`: an argv template that prints the current value. |
| `revert` | For `cli`: an argv template that undoes the setting. |
| `source` | The command, man page or URL the claim came from. |
| `note` | A requirement or a consequence, or `-`. |

A `cli` template is split on spaces into an argument list, and `%s` is replaced
inside one token. Nothing is passed to a shell, so no `eval` touches the
catalogue, and a path containing a space, a dollar sign or a semicolon stays
one argument. The tests cover each of those.

Two rules the validator enforces are worth stating plainly: a row must name a
source, and a `cli` row must carry both a query and an undo. An entry nobody
can undo does not belong in a tool that writes to your shell configuration.

## Adding an Entry

1. Find the vendor's own page or the tool's own `--help`, and read it.
2. Prefer a mechanism in this order: `cli`, `env`, `file`, `ui`. A `flag` entry
   is worth adding anyway, because it tells a person the only honest answer.
3. Put the exact source in the `source` field. A short command such as
   `man brew` or `swift build --help` beats a URL when the claim can be checked
   locally.
4. Run `extdisk-apfs validate` and `scripts/check`.
5. Test it with `extdisk-apfs host /Volumes/X --only your-id --dry-run`.

A claim with no source does not go in. "Probably works" and "should be
possible" are not entries.

## Where the Claims Came From

Every tool installed on the machine this was built on was checked directly:
`man brew` for `HOMEBREW_CACHE`; `bun pm cache`, `uv cache dir` and
`pip3 cache dir` each run twice, once with the documented variable set, to
confirm it moves the path; `npm config set` and `npm config delete` run against
a throwaway `HOME` to confirm both directions; `xcodebuild -help`,
`swift build --help` and `xcrun simctl help` for the flags. The
`-archivePath` semantics were settled by two `xcodebuild archive` runs, because
the man page and `-help` disagree.

For a tool or application that is not installed here, the entry cites the
vendor's documentation, and the `source` field holds that URL.

Two honest gaps:

- **Ableton's help site answers an automated fetch with HTTP 403.** The
  `ableton-packs` entry cites the Managing Packs article, whose text was read
  through a search index rather than fetched directly. The Preferences path in
  the entry is the one that article gives.
- **Several vendors document nothing citable**, so they have no entry:
  CocoaPods names no cache-directory setting; OrbStack documents no data
  location; Steam's macOS help page, Arturia's support site and Steinberg's
  help centre all refused an automated read; and Apple documents no external
  location for GarageBand's sound library. Likewise, `pip config set
  global.cache-dir` appears in no page that was read, so `pip-cache` uses
  `PIP_CACHE_DIR`.
- **pnpm's global configuration file is platform-specific**, and only
  [pnpm's `config` page](https://pnpm.io/cli/config) gives the paths. The
  macOS one is `~/Library/Preferences/pnpm/config.yaml`; the `~/.config/pnpm`
  path that most writing quotes is the Linux one, and pnpm on macOS ignores it
  unless `XDG_CONFIG_HOME` is set. The `storeDir` key comes from
  [the store settings page](https://pnpm.io/settings/store). `pnpm config set`
  is documented, but neither page spells the store key as a command argument,
  so `pnpm-store` stays a `file` entry rather than becoming a `cli` one.

[docs/external-storage.md](external-storage.md) is the long-form evidence for
the Xcode, simulator, Spotlight, Time Machine and Audio Unit claims, including
what could not be checked on this machine and why.

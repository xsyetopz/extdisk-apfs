# cli.sh - the usage text and the option parsing for each command that takes
# options. bin/extdisk-apfs stays a loader and a dispatch table, so that
# reading one command's arguments does not mean reading the whole tool.
# Each cmd_* function validates, then calls into the module that does the work.

usage() {
  cat <<'EOF'
extdisk-apfs - reclaim an external disk as one APFS volume on GPT.

usage:
  extdisk-apfs list
  extdisk-apfs show   <disk>
  extdisk-apfs erase  <disk> --label <name> [options]
  extdisk-apfs verify <disk>
  extdisk-apfs hosts  [--all] [<volume>]
  extdisk-apfs host   <volume> [--only <id,id>] [--dry-run]
  extdisk-apfs unhost <volume> [--dry-run]
  extdisk-apfs simdisk <volume> [--size <size>] [--dry-run]
  extdisk-apfs simdisk <volume> --undo [--dry-run]
  extdisk-apfs explain <id> [<volume>]
  extdisk-apfs validate
  extdisk-apfs --version

commands:
  list            Show every external physical disk, as candidates.
  show            Show one disk's current partition map and mounted volumes.
  erase           Erase the disk and create one APFS volume. Destroys all data.
  verify          Report the partition map, container, volume and capacity.
  hosts           Show which applications can keep data on the volume, and
                  which of them are installed. --all includes the rest.
  host            Create the directories and apply every setting that a
                  command or an environment variable can persist. Prints the
                  ones only you can set. Moves no data.
  unhost          Remove what host wrote, and leave every file in place.
  simdisk         Keep simulator devices on the volume, in a sparse bundle
                  disk image, because CoreSimulatorService refuses a device
                  set on a removable volume itself. Mounts the image at the
                  default device set and adds a line to your shell startup
                  file that attaches it in each new shell. --undo reverses
                  that and keeps the image.
  explain         Show one catalogue entry: the mechanism, the exact setting,
                  the source it came from, and what to know before using it.
  validate        Check every row of the catalogue, and fail on a bad one.
  --version       Print the version.

host options:
  --only <id,id>  Restrict to these catalogue ids. Default is everything
                  installed.
  --dry-run       Print every command and every line, write nothing.

simdisk options:
  --size <size>   The image's ceiling, such as 60g or 500m. Default 60g. The
                  image grows on demand, so this is not allocated up front.
                  Applies only when the image is created.
  --undo          Remove the startup line and eject the image. The image
                  file stays.
  --dry-run       Print every command, run none.

erase options:
  --label <name>        Volume name. Required, because diskutil requires one.
  --case-sensitive      Use the case-sensitive APFS personality. Default is
                        the plain APFS personality, which is case-insensitive.
  --own                 chown the new volume's root directory to you. A
                        freshly erased volume is root-owned, so without this
                        you may not be able to write to it. Needs an
                        administrator password.
  --enable-owners       Run diskutil enableOwnership on the new volume, so
                        that the on-disk user and group IDs count. This is a
                        different thing from --own and does not grant you
                        access. Needs an administrator password.
  --no-spotlight        Turn off Spotlight indexing for the new volume. Needs
                        an administrator password.
  --no-timemachine      Add a Time Machine volume exclusion. Needs an
                        administrator password and Full Disk Access.
  --dry-run             Print every command without running any of it.
  --force               Skip the typed confirmation. For scripts only; the
                        refusals and the re-check still apply.

examples:
  extdisk-apfs list
  extdisk-apfs show disk4
  extdisk-apfs erase disk4 --label Scratch --enable-owners --own
  extdisk-apfs erase disk4 --label Scratch --dry-run
  extdisk-apfs hosts /Volumes/Scratch
  extdisk-apfs explain homebrew-cache /Volumes/Scratch
  extdisk-apfs host /Volumes/Scratch --dry-run
  extdisk-apfs host /Volumes/Scratch --only homebrew-cache,npm-cache
  extdisk-apfs simdisk /Volumes/Scratch --size 100g --dry-run

The tool refuses any target that is internal, virtual, read-only, a partition
rather than a whole disk, or part of the boot disk's storage.
EOF
}

cmd_erase() {
  local disk="${1:-}"
  shift || true
  [ -n "$disk" ] || die "erase needs a disk identifier; run 'extdisk-apfs list'"

  local label='' personality='APFS' force=0
  # An array, so each step stays one argument. In bash 3.2 under set -u an
  # empty array cannot be expanded bare, hence the ${steps[@]+...} guard below.
  local steps=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --label)
        [ $# -ge 2 ] || die "--label needs a value"
        label="$2"
        shift 2
        ;;
      --label=*) label="${1#--label=}"; shift ;;
      --case-sensitive) personality='Case-sensitive APFS'; shift ;;
      --own) steps[${#steps[@]}]=own; shift ;;
      --enable-owners) steps[${#steps[@]}]=owners; shift ;;
      --no-spotlight) steps[${#steps[@]}]=spotlight; shift ;;
      --no-timemachine) steps[${#steps[@]}]=timemachine; shift ;;
      --dry-run) dry_run_on; shift ;;
      --force) force=1; shift ;;
      *) die "unknown option '$1'; run 'extdisk-apfs' for the usage" ;;
    esac
  done

  erase_flow "$disk" "$label" "$personality" "$force" ${steps[@]+"${steps[@]}"}
}

cmd_hosts() {
  local all=0 volume=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) all=1; shift ;;
      --*) die "unknown option '$1'; run 'extdisk-apfs' for the usage" ;;
      *)
        [ -z "$volume" ] || die "hosts takes one volume, and got '$volume' and '$1'"
        volume="$1"
        shift
        ;;
    esac
  done
  [ -z "$volume" ] || guard_volume "$volume"
  print_hosts "$volume" "$all"
}

cmd_host() {
  local volume="${1:-}" only=''
  shift || true
  [ -n "$volume" ] || die "host needs a volume, such as /Volumes/Scratch"
  while [ $# -gt 0 ]; do
    case "$1" in
      --only)
        [ $# -ge 2 ] || die "--only needs a comma-separated list of ids"
        only="$2"
        shift 2
        ;;
      --only=*) only="${1#--only=}"; shift ;;
      --dry-run) dry_run_on; shift ;;
      *) die "unknown option '$1'; run 'extdisk-apfs' for the usage" ;;
    esac
  done
  local id
  for id in $(printf '%s' "$only" | tr ',' ' '); do
    [ -n "$(hosts_row "$id")" ] || die "no catalogue entry with id '$id'; run 'extdisk-apfs hosts --all'"
  done
  host_volume "$volume" "$only"
}

cmd_unhost() {
  local volume="${1:-}"
  shift || true
  [ -n "$volume" ] || die "unhost needs a volume, such as /Volumes/Scratch"
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run_on; shift ;;
      *) die "unknown option '$1'; run 'extdisk-apfs' for the usage" ;;
    esac
  done
  guard_volume "$volume"
  unhost_volume "$volume"
}

cmd_simdisk() {
  local volume="${1:-}" size='60g' undo=0
  shift || true
  case "$volume" in
    '' | -*) die "simdisk needs a volume, such as /Volumes/Scratch" ;;
  esac
  while [ $# -gt 0 ]; do
    case "$1" in
      --size)
        [ $# -ge 2 ] || die "--size needs a value, such as 60g"
        size="$2"
        shift 2
        ;;
      --size=*) size="${1#--size=}"; shift ;;
      --undo) undo=1; shift ;;
      --dry-run) dry_run_on; shift ;;
      *) die "unknown option '$1'; run 'extdisk-apfs' for the usage" ;;
    esac
  done
  simdisk_size_ok "$size" || die "--size '$size' is not a number and a unit, such as 60g, 500m or 1t"
  if [ "$undo" = "1" ]; then
    simdisk_down "$volume"
  else
    simdisk_up "$volume" "$size"
  fi
}

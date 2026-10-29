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
  extdisk-apfs explain <id> [<volume>]

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
  explain         Show one catalogue entry: the mechanism, the exact setting,
                  the source it came from, and what to know before using it.

host options:
  --only <id,id>  Restrict to these catalogue ids. Default is everything
                  installed.
  --dry-run       Print every command and every line, write nothing.

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

The tool refuses any target that is internal, virtual, read-only, a partition
rather than a whole disk, or part of the boot disk's storage.
EOF
}

# post_format_steps <mount-point> [step...]
# Each step is one of the tokens below, passed as its own argument.
post_format_steps() {
  local mp="$1" step
  shift
  for step in "$@"; do
    case "$step" in
      own) take_ownership "$mp" ;;
      owners) enable_owners "$mp" ;;
      spotlight) disable_spotlight "$mp" ;;
      timemachine) exclude_from_time_machine "$mp" ;;
    esac
  done
}

cmd_erase() {
  local disk="${1:-}"
  shift || true
  [ -n "$disk" ] || die "erase needs a disk identifier; run 'extdisk-apfs list'"

  local label='' personality='APFS' force=0
  local identity mount_point boot_disks
  # An array, so each step stays one argument. In bash 3.2 under set -u an
  # empty array cannot be expanded bare, hence the ${steps[@]+...} guard at
  # each use site.
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
      --dry-run) DRY_RUN=1; shift ;;
      --force) force=1; shift ;;
      *) die "unknown option '$1'; run 'extdisk-apfs' for the usage" ;;
    esac
  done

  guard_target "$disk"
  guard_label "$label"
  identity="$(dk_identity "$disk")"
  [ -n "$identity" ] || die "could not fingerprint $disk"

  print_layout "$disk"

  boot_disks="$(dk_boot_disks | tr '\n' ' ')"
  heading "What happens next"
  say "  target:        $disk  $(dk_get "$disk" MediaName)  $(human_size "$(dk_get "$disk" TotalSize)")"
  say "  partition map: GPT, replacing $(dk_get "$disk" Content)"
  say "  file system:   $personality, one volume named '$label'"
  say "  boot disk:     ${boot_disks% }, untouched"
  warn "every byte of data on $disk becomes unreachable"

  if [ "$DRY_RUN" = "1" ]; then
    heading "Dry run, nothing is written"
  elif [ "$force" = "1" ]; then
    warn "--force given, skipping the typed confirmation"
  else
    confirm_identifier "$disk"
  fi

  # Re-checked here rather than only above, because the prompt leaves a window
  # in which the disk can be detached and another one can take the identifier.
  guard_unchanged "$disk" "$identity"

  do_erase "$disk" "$label" "$personality"

  if [ "$DRY_RUN" = "1" ]; then
    # No volume exists, so the real mount point is unknowable. A bare token
    # keeps the printed commands from naming a path that may belong to another
    # volume, such as /Volumes/Macintosh HD, which is a symlink to / on a
    # stock system. The token has no shell metacharacters, so it prints as
    # typed rather than escaped.
    if [ "${#steps[@]}" -gt 0 ]; then
      say ''
      dim 'MOUNT_POINT below stands for the new volume, read from diskutil after the erase'
    fi
    post_format_steps MOUNT_POINT ${steps[@]+"${steps[@]}"}
    say ''
    dim "dry run finished; rerun without --dry-run to erase $disk"
    return 0
  fi

  if mount_point="$(new_volume_mount_point "$disk")"; then
    post_format_steps "$mount_point" ${steps[@]+"${steps[@]}"}
    report_writability "$mount_point"
  else
    mount_point='(not mounted)'
    if [ "${#steps[@]}" -gt 0 ]; then
      warn "the new volume is not mounted, so the post-format steps were skipped"
    fi
  fi

  verify_disk "$disk"
  say ''
  ok "$disk is now GPT with one $personality volume '$label' at $mount_point"
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
      --dry-run) DRY_RUN=1; shift ;;
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
      --dry-run) DRY_RUN=1; shift ;;
      *) die "unknown option '$1'; run 'extdisk-apfs' for the usage" ;;
    esac
  done
  guard_volume "$volume"
  unhost_volume "$volume"
}

# erase.sh - the destructive step and the optional post-format settings.

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

# erase_flow <whole-disk> <label> <personality> <force 0|1> [step...]
# The whole destructive sequence: refuse, fingerprint, show, confirm, re-check,
# erase, then the post-format steps and the report. lib/cli.sh parses the
# options and calls this, so the order of the refusals is decided in one place
# and does not depend on how the arguments were spelled.
erase_flow() {
  local disk="$1" label="$2" personality="$3" force="$4"
  shift 4
  local identity mount_point boot_disks

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

  if [ "${DRY_RUN:-0}" = "1" ]; then
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

  if [ "${DRY_RUN:-0}" = "1" ]; then
    # No volume exists, so the real mount point is unknowable. A bare token
    # keeps the printed commands from naming a path that may belong to another
    # volume, such as /Volumes/Macintosh HD, which is a symlink to / on a
    # stock system. The token has no shell metacharacters, so it prints as
    # typed rather than escaped.
    if [ "$#" -gt 0 ]; then
      say ''
      dim 'MOUNT_POINT below stands for the new volume, read from diskutil after the erase'
    fi
    post_format_steps MOUNT_POINT "$@"
    say ''
    dim "dry run finished; rerun without --dry-run to erase $disk"
    return 0
  fi

  if mount_point="$(new_volume_mount_point "$disk")"; then
    post_format_steps "$mount_point" "$@"
    report_writability "$mount_point"
  else
    mount_point='(not mounted)'
    if [ "$#" -gt 0 ]; then
      warn "the new volume is not mounted, so the post-format steps were skipped"
    fi
  fi

  verify_disk "$disk"
  say ''
  ok "$disk is now GPT with one $personality volume '$label' at $mount_point"
}

# do_erase <whole-disk> <label> <personality>
# One normal erase: diskutil writes a fresh GUID partition map and formats one
# APFS volume. This is a repartition, not an overwrite of every block, which is
# what reuse needs; see the "What This Does Not Do" section of the README.
do_erase() {
  local disk="$1" label="$2" personality="$3"
  heading "Erasing $disk"
  run_cmd diskutil eraseDisk "$personality" "$label" GPT "/dev/$disk" ||
    die "diskutil eraseDisk failed; the disk may be left unformatted, and rerunning is safe"
}

# new_volume_mount_point <whole-disk>
# The mount point of the volume that the erase just created, read from
# diskutil. Building /Volumes/<label> instead would be wrong: when a volume of
# that name is already mounted, macOS mounts the new one under a different
# path, and the post-format commands would then run against the older volume.
# /Volumes/Macintosh HD is a symlink to / on a stock system, so that mistake
# can reach the boot volume.
new_volume_mount_point() {
  local disk="$1" vol mp
  for vol in $(dk_apfs_volumes_of_disk "$disk"); do
    mp="$(dk_get "$vol" MountPoint)"
    if [ -n "$mp" ]; then
      printf '%s\n' "$mp"
      return 0
    fi
  done
  return 1
}

# take_ownership <mount-point>
# diskutil eraseDisk leaves the volume's root directory owned by root. On the
# disk this was developed against it was root:wheel drwxrwxr-x, and the
# console user is in staff rather than wheel, so the user who just created the
# volume could not write to it. chown on the root directory is what makes the
# volume usable; enable_owners below does not, and would not.
take_ownership() {
  local mp="$1"
  heading "Taking ownership of $mp"
  say "This needs an administrator password."
  run_cmd sudo chown "$(id -u):$(id -g)" "$mp" ||
    warn "could not change the owner of $mp; it may stay unwritable for $(id -un)"
}

# enable_owners <mount-point>
# Makes the on-disk user and group IDs count, per man diskutil. This is about
# whether ownership is honoured, not about who owns anything: on a volume whose
# root is owned by root it does not grant you access, and --own is the option
# for that. Use this when you will restore a tree whose owners must survive.
enable_owners() {
  local mp="$1"
  heading "Enabling ownership on $mp"
  say "This needs an administrator password."
  run_cmd sudo diskutil enableOwnership "$mp" ||
    warn "could not enable ownership on $mp; the volume still works, but file owners are ignored"
}

# exclude_from_time_machine <mount-point>
# Build artifacts and caches are reproducible, so backing them up wastes
# backup space and time. man tmutil: -v is the only supported way to exclude a
# volume, and it tracks the volume by file system UUID. A sticky or fixed-path
# exclusion on a volume is undefined, so -v is not optional here. Erasing the
# volume resets Time Machine to its default behaviour for the new volume.
exclude_from_time_machine() {
  local mp="$1"
  heading "Excluding $mp from Time Machine"
  say "This needs an administrator password, and Terminal needs Full Disk Access."
  run_cmd sudo tmutil addexclusion -v "$mp" ||
    warn "could not add the Time Machine exclusion; grant Full Disk Access to your terminal and rerun: sudo tmutil addexclusion -v $(shell_quote "$mp")"
}

# disable_spotlight <mount-point>
# Turns off indexing of the whole volume. Re-enable it with:
#   sudo mdutil -i on <mp>
# For build artifacts a .noindex directory suffix is the lighter alternative,
# needs no password, and is what Xcode does to its own caches. See the
# Spotlight section of docs/external-storage.md.
disable_spotlight() {
  local mp="$1"
  heading "Disabling Spotlight indexing on $mp"
  say "This needs an administrator password."
  run_cmd sudo mdutil -i off "$mp" ||
    warn "could not disable Spotlight indexing on $mp"
}

# in_group <group-name>
# True when the invoking user belongs to the group.
in_group() {
  case " $(id -Gn) " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# report_writability <mount-point>
# Says plainly whether the invoking user can write to the new volume, because
# a freshly erased volume is root-owned and the failure otherwise shows up
# later as a permission error from an unrelated tool.
report_writability() {
  local mp="$1"
  heading "Write access to $mp"
  local owner_group member
  owner_group="$(stat -f '%Sg' "$mp")"
  if in_group "$owner_group"; then member=yes; else member=no; fi
  printf '  owner:    %s\n' "$(stat -f '%Su:%Sg' "$mp")"
  printf '  mode:     %s\n' "$(stat -f '%Sp' "$mp")"
  printf '  you:      %s:%s\n' "$(id -un)" "$(id -gn)"
  printf '  in %s:    %s\n' "$owner_group" "$member"
  if [ -w "$mp" ]; then
    ok "  $(id -un) can write to $mp"
  else
    warn "$(id -un) cannot write to $mp; rerun with --own, or run: sudo chown $(id -u):$(id -g) $(shell_quote "$mp")"
  fi
}

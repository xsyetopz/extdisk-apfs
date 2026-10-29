# erase.sh - the destructive step and the optional post-format settings.

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

# enable_owners <mount-point>
# An external volume mounts with ownership ignored, so every file appears to
# belong to the mounting user. Developer tooling that checks file ownership,
# and anything restoring a tree with mixed owners, needs ownership honoured.
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
# Turns off indexing of the volume. Re-enable it with: sudo mdutil -i on <mp>
disable_spotlight() {
  local mp="$1"
  heading "Disabling Spotlight indexing on $mp"
  say "This needs an administrator password."
  run_cmd sudo mdutil -i off "$mp" ||
    warn "could not disable Spotlight indexing on $mp"
}

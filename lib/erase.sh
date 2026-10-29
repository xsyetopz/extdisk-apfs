# erase.sh - the destructive step and the optional post-format settings.

# do_erase <whole-disk> <label> <personality>
# One normal erase: diskutil writes a fresh GUID partition map and formats one
# APFS volume. This is a repartition, not an overwrite of every block, which is
# what reuse needs; see the "What This Does Not Do" section of the README.
do_erase() {
  disk="$1"
  label="$2"
  personality="$3"
  heading "Erasing $disk"
  run_cmd diskutil eraseDisk "$personality" "$label" GPT "/dev/$disk" ||
    die "diskutil eraseDisk failed; the disk may be left unformatted, and rerunning is safe"
}

# enable_owners <mount-point>
# An external volume mounts with ownership ignored, so every file appears to
# belong to the mounting user. Developer tooling that checks file ownership,
# and anything restoring a tree with mixed owners, needs ownership honoured.
enable_owners() {
  mp="$1"
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
  mp="$1"
  heading "Excluding $mp from Time Machine"
  say "This needs an administrator password, and Terminal needs Full Disk Access."
  run_cmd sudo tmutil addexclusion -v "$mp" ||
    warn "could not add the Time Machine exclusion for $mp; grant Full Disk Access to your terminal and rerun 'sudo tmutil addexclusion -v $mp'"
}

# disable_spotlight <mount-point>
# Spotlight indexing of a build-artifact volume costs CPU and disk on every
# build. Re-enable it with: sudo mdutil -i on <mount-point>
disable_spotlight() {
  mp="$1"
  heading "Disabling Spotlight indexing on $mp"
  run_cmd sudo mdutil -i off "$mp" ||
    warn "could not disable Spotlight indexing on $mp"
}

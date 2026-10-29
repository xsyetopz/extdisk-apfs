# guard.sh - the refusals. Nothing here prints a report; it either returns or
# dies with the reason named, because an operator who cannot explain a refusal
# reaches for --force.

# guard_target <identifier>
# Passes only an external, physical, writable whole disk that carries no part
# of the boot disk's storage.
guard_target() {
  local disk="$1" boot_disks boot member external=0 candidate

  case "$disk" in
    /dev/*) die "pass the identifier such as disk4, not the device node $disk" ;;
  esac

  # Removing the digits leaves the shape of the identifier: diskN becomes
  # "disk", diskNsM becomes "disks", and diskNsMsK becomes "diskss". Anything
  # else is not an identifier, which keeps a crafted argument such as
  # disk0/../disk4 out before any diskutil call. A partition is accepted here
  # so that the next check can name the whole disk to use instead.
  case "${disk//[0-9]/}" in
    disk | disks | diskss) : ;;
    *) die "'$disk' is not a disk identifier such as disk4; run 'extdisk-apfs list' to see the candidates" ;;
  esac

  dk_exists "$disk" || die "diskutil does not know '$disk'"

  [ "$(dk_get "$disk" WholeDisk)" = "true" ] ||
    die "$disk is a partition or a volume; pass the whole disk, such as $(dk_whole_disk_of "$disk")"

  # Checked before the external test, because an internal disk is the mistake
  # worth naming plainly. On the author's machine the internal NVMe reports
  # VirtualOrPhysical=Unknown, so that key alone cannot carry the decision.
  # Every test below compares against the passing value, so an absent key or a
  # diskutil failure refuses rather than permits.
  [ "$(dk_get "$disk" Internal)" = "false" ] ||
    die "$disk is an internal disk, and this tool only erases external disks"

  [ "$(dk_get "$disk" VirtualOrPhysical)" != "Virtual" ] ||
    die "$disk is virtual, so it is a disk image or a synthesized APFS container, not hardware"

  # diskutil's own external-physical filter is the authority on what this tool
  # may touch, so membership in that list is required rather than inferred.
  for candidate in $(dk_external_whole_disks); do
    [ "$candidate" != "$disk" ] || external=1
  done
  [ "$external" = "1" ] ||
    die "$disk is not in 'diskutil list external physical', so it is not an external physical disk"

  [ "$(dk_get "$disk" OSInternalMedia)" = "false" ] ||
    die "$disk is marked as OS internal media"

  [ "$(dk_get "$disk" WritableMedia)" = "true" ] ||
    die "$disk is not writable; check a physical write-protect switch on the enclosure"

  # An empty boot disk list would make every comparison below pass, so the
  # lookup failing is itself a refusal.
  boot_disks="$(dk_boot_disks)"
  [ -n "$boot_disks" ] ||
    die "could not determine the boot disk from 'diskutil info /', so no erase is safe to attempt"

  for boot in $boot_disks; do
    [ "$disk" != "$boot" ] ||
      die "$disk is the boot disk, which holds the running system"
  done

  for member in $(dk_storage_members "$disk"); do
    for boot in $boot_disks; do
      [ "$(dk_whole_disk_of "$member")" != "$boot" ] ||
        die "$disk carries part of the boot disk's storage, through $member"
    done
  done
}

# guard_unchanged <identifier> <fingerprint-from-dk_identity>
# Re-runs every refusal and compares the hardware fingerprint. Called after the
# confirmation prompt, because identifiers are reassigned on every attach and
# the prompt leaves a window in which the target can become another disk.
guard_unchanged() {
  local disk="$1" before="$2" after
  guard_target "$disk"
  after="$(dk_identity "$disk")"
  [ -n "$after" ] ||
    die "could not re-read $disk, so the erase was not attempted"
  [ "$after" = "$before" ] ||
    die "$disk is not the disk it was before the confirmation; it was detached or replaced, so nothing was changed"
}

# guard_label <label>
# diskutil takes the label as a positional argument and APFS stores it as the
# volume name, so a label that reads as a flag or as a path component must not
# reach it. No maximum length is enforced here, because the limit APFS applies
# was not verified; diskutil rejects an over-long name itself.
guard_label() {
  local label="$1"
  [ -n "$label" ] || die "the volume label is empty, and diskutil requires one"
  case "$label" in
    . | ..) die "the label '$label' is a path component, so /Volumes/$label would not be the new volume" ;;
    */*) die "the label '$label' contains a slash, which cannot appear in a volume name" ;;
    *:*) die "the label '$label' contains a colon, which macOS reserves in volume names" ;;
    -*) die "the label '$label' starts with a dash, so diskutil would read it as a flag" ;;
    ' '* | *' ') die "the label '$label' has a leading or trailing space, which is invisible in Finder" ;;
    *$'\t'* | *$'\n'*) die "the label contains a tab or a newline" ;;
  esac
}

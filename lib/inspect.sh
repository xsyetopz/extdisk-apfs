# inspect.sh - find candidate disks, show a layout, and refuse unsafe targets.

# print_candidates
# One line per external physical whole disk.
print_candidates() {
  found=0
  heading "External physical disks"
  printf '  %-8s %-24s %-10s %-6s %-6s %s\n' \
    IDENT 'MEDIA NAME' SIZE BUS SSD CONTENT
  for d in $(dk_external_whole_disks); do
    found=1
    printf '  %-8s %-24s %-10s %-6s %-6s %s\n' \
      "$d" \
      "$(dk_get "$d" MediaName)" \
      "$(human_size "$(dk_get "$d" TotalSize)")" \
      "$(dk_get "$d" BusProtocol)" \
      "$([ "$(dk_get "$d" SolidState)" = "true" ] && echo yes || echo no)" \
      "$(dk_get "$d" Content)"
  done
  if [ "$found" = "0" ]; then
    say '  none attached'
  fi
}

# dk_storage_members <whole-disk>
# Every identifier whose data lives on this physical disk: the disk, its
# partitions, and the volumes of any APFS container built on those partitions.
# An APFS volume is not listed under the physical disk, because the container
# is synthesized as a separate disk, so following the container is the only way
# to see what an erase would destroy.
dk_storage_members() {
  disk="$1"
  for part in $(dk_list_get AllDisks "$disk"); do
    printf '%s\n' "$part"
    if [ "$(dk_get "$part" Content)" = "Apple_APFS" ]; then
      container="$(dk_container_of "$part")"
      if [ -n "$container" ]; then
        dk_list_get AllDisks "$container"
      fi
    fi
  done | sort -u
}

# print_layout <whole-disk>
# The current partition layout and every mounted volume on that disk, so the
# operator sees what is about to be destroyed before confirming.
print_layout() {
  disk="$1"
  heading "Current layout of $disk"
  diskutil list "$disk"
  heading "Mounted volumes on $disk"
  mounted=0
  for member in $(dk_storage_members "$disk"); do
    mp="$(dk_get "$member" MountPoint)"
    if [ -n "$mp" ]; then
      mounted=1
      printf '  %-10s %-24s %s\n' "$member" "$(dk_get "$member" VolumeName)" "$mp"
      df -h "$mp" | tail -n 1 | sed 's/^/      /'
    fi
  done
  if [ "$mounted" = "0" ]; then
    say '  none mounted'
  fi
}

# guard_target <identifier>
# Dies unless the identifier is an external, physical, writable whole disk that
# is not the boot disk. Each check names the reason, because a refusal the
# operator cannot explain invites --force.
guard_target() {
  disk="$1"

  case "$disk" in
    /dev/*) die "pass the identifier such as disk4, not the device node $disk" ;;
    disk[0-9]*) : ;;
    *) die "'$disk' is not a disk identifier; run 'extdisk-apfs list' to see the candidates" ;;
  esac

  dk_exists "$disk" || die "diskutil does not know '$disk'"

  [ "$(dk_get "$disk" WholeDisk)" = "true" ] ||
    die "$disk is a partition or a volume; pass the whole disk, such as $(dk_whole_disk_of "$disk")"

  # Checked before the external test, because an internal disk is the mistake
  # worth naming plainly. On this machine the internal NVMe reports
  # VirtualOrPhysical=Unknown, so that key alone cannot carry the decision.
  [ "$(dk_get "$disk" Internal)" = "false" ] ||
    die "$disk is an internal disk, and this tool only erases external disks"

  [ "$(dk_get "$disk" VirtualOrPhysical)" != "Virtual" ] ||
    die "$disk is virtual, so it is a disk image or a synthesized APFS container, not hardware"

  # diskutil's own external-physical filter is the authority on what this tool
  # may touch, so membership in that list is required rather than inferred.
  external=0
  for candidate in $(dk_external_whole_disks); do
    [ "$candidate" != "$disk" ] || external=1
  done
  [ "$external" = "1" ] ||
    die "$disk is not in 'diskutil list external physical', so it is not an external physical disk"

  [ "$(dk_get "$disk" OSInternalMedia)" = "false" ] ||
    die "$disk is marked as OS internal media"

  [ "$(dk_get "$disk" WritableMedia)" = "true" ] ||
    die "$disk is not writable; check a physical write-protect switch on the enclosure"

  boot="$(dk_boot_disk)"
  [ "$disk" != "$boot" ] ||
    die "$disk is the boot disk, which holds the running system"

  for member in $(dk_storage_members "$disk"); do
    [ "$(dk_whole_disk_of "$member")" != "$boot" ] ||
      die "$disk carries part of the boot disk's storage, through $member"
  done
}

# guard_label <label>
# APFS stores the label as the volume name, and diskutil takes it as a
# positional argument, so an empty or path-like label must not reach it.
guard_label() {
  label="$1"
  [ -n "$label" ] || die "the volume label is empty, and diskutil requires one"
  case "$label" in
    */*) die "the label '$label' contains a slash, which cannot appear in a volume name" ;;
    *:*) die "the label '$label' contains a colon, which macOS reserves in volume names" ;;
    -*) die "the label '$label' starts with a dash, so diskutil would read it as a flag" ;;
  esac
  [ "${#label}" -le 127 ] || die "the label is ${#label} characters, and 127 is the maximum"
}

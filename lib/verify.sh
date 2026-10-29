# verify.sh - report the state of a formatted disk from diskutil itself.

# verify_disk <whole-disk>
# Prints the partition map, the APFS container, the volume, and the mounted
# capacity, then verifies the map. Read-only: it changes nothing.
verify_disk() {
  local disk="$1" part container='' store='' vol name mp
  dk_exists "$disk" || die "diskutil does not know '$disk'"

  heading "Partition map of $disk"
  diskutil list "$disk"

  printf '  scheme:  %s\n' "$(dk_get "$disk" Content)"
  printf '  media:   %s\n' "$(dk_get "$disk" MediaName)"
  printf '  bus:     %s\n' "$(dk_get "$disk" BusProtocol)"
  printf '  size:    %s\n' "$(human_size "$(dk_get "$disk" TotalSize)")"

  for part in $(dk_list_get AllDisks "$disk"); do
    if [ "$(dk_get "$part" Content)" = "Apple_APFS" ]; then
      container="$(dk_container_of "$part")"
      store="$part"
    fi
  done

  if [ -z "$container" ]; then
    warn "$disk has no APFS container"
    return 1
  fi

  heading "APFS container $container"
  printf '  physical store: %s\n' "$store"
  diskutil apfs list "$container" | sed 's/^/  /'

  heading "Volumes"
  for vol in $(dk_volumes_of_container "$container"); do
    name="$(dk_get "$vol" VolumeName)"
    mp="$(dk_get "$vol" MountPoint)"
    printf '  %-10s %-24s %s\n' "$vol" "$name" "${mp:-not mounted}"
    printf '    filesystem:  %s\n' "$(dk_get "$vol" FilesystemName)"
    # Tested on the string, because dk_get always exits 0 and so cannot carry
    # this answer in its exit status.
    printf '    mounted:     %s\n' "$([ -n "$mp" ] && echo yes || echo no)"
    printf '    owners:      %s\n' \
      "$([ "$(dk_get "$vol" GlobalPermissionsEnabled)" = "true" ] && echo enabled || echo disabled)"
    printf '    free space:  %s\n' "$(human_size "$(dk_get "$vol" APFSContainerFree)")"
    if [ -n "$mp" ]; then
      # Who owns the root directory and whether you can write there. A freshly
      # erased volume is root-owned, so this is the question an operator asks
      # of a volume next, and diskutil does not answer it.
      printf '    owner:       %s\n' "$(stat -f '%Su:%Sg' "$mp")"
      printf '    mode:        %s\n' "$(stat -f '%Sp' "$mp")"
      if [ -w "$mp" ]; then
        printf '    you:         %s can write\n' "$(id -un)"
      else
        printf '    you:         %s cannot write; run: sudo chown %s:%s %s\n' \
          "$(id -un)" "$(id -u)" "$(id -g)" "$(shell_quote "$mp")"
      fi
      df -h "$mp" | sed 's/^/    /'
    fi
  done

  heading "Partition map verification"
  diskutil verifyDisk "$disk" | sed 's/^/  /'
}

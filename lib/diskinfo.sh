# diskinfo.sh - read facts about a disk from diskutil's own plist output.
# Every fact here comes from `diskutil info -plist` or `diskutil list -plist`,
# so the tool never parses the human-readable columns, which are not a contract.

# dk_exists <identifier>
dk_exists() { diskutil info "$1" >/dev/null 2>&1; }

# dk_get <identifier> <plist-keypath>
# Prints the raw value, or nothing when the key is absent. A caller that makes
# a safety decision must treat empty as "unknown" and refuse, because this
# function cannot distinguish an absent key from a diskutil failure.
dk_get() {
  diskutil info -plist "$1" 2>/dev/null |
    plutil -extract "$2" raw -o - - 2>/dev/null || true
}

# dk_list_get <plutil-keypath> <diskutil-list-args...>
# Prints a JSON array from `diskutil list -plist`, one element per line.
dk_list_get() {
  local keypath="$1"
  shift
  diskutil list -plist "$@" 2>/dev/null |
    plutil -extract "$keypath" json -o - - 2>/dev/null |
    tr -d '[]" ' | tr ',' '\n' | sed '/^$/d'
}

# dk_physical_stores <container>
# Every physical store partition of an APFS container, one per line. A Fusion
# Drive container has two, so reading only index 0 would miss a disk.
dk_physical_stores() {
  local container="$1" index=0 store
  while :; do
    store="$(dk_get "$container" "APFSPhysicalStores.$index.APFSPhysicalStore")"
    [ -n "$store" ] || break
    printf '%s\n' "$store"
    index=$((index + 1))
  done
}

# dk_whole_disks_of <identifier>
# Every physical whole disk whose hardware stores this identifier's data. A
# mount point, a partition, or a synthesized APFS container all resolve here.
# An APFS container is synthesized, so its ParentWholeDisk is itself and the
# physical stores are the only way out.
dk_whole_disks_of() {
  local id="$1" parent store found=0
  parent="$(dk_get "$id" ParentWholeDisk)"
  if [ -z "$parent" ]; then
    printf '%s\n' "$id"
    return 0
  fi
  for store in $(dk_physical_stores "$parent"); do
    if [ "$store" != "$parent" ]; then
      found=1
      dk_whole_disks_of "$store"
    fi
  done
  [ "$found" = "1" ] || printf '%s\n' "$parent"
}

# dk_whole_disk_of <identifier>
# The first disk from dk_whole_disks_of, for use in a message.
dk_whole_disk_of() { dk_whole_disks_of "$1" | head -n 1; }

# dk_boot_disks
# Every physical whole disk holding the running system volume.
dk_boot_disks() { dk_whole_disks_of /; }

# dk_external_whole_disks
# Every external physical whole disk, one identifier per line.
dk_external_whole_disks() { dk_list_get WholeDisks external physical; }

# dk_container_of <partition>
# The synthesized APFS container reference for an Apple_APFS partition.
dk_container_of() { dk_get "$1" APFSContainerReference; }

# dk_volumes_of_container <container>
# Every volume identifier inside a container, one per line.
dk_volumes_of_container() {
  dk_list_get AllDisks "$1" | grep -v "^$1\$" || true
}

# dk_storage_members <whole-disk>
# Every identifier whose data lives on this physical disk: the disk, its
# partitions, and the volumes of any APFS container built on those partitions.
dk_storage_members() {
  local disk="$1" part container
  for part in $(dk_list_get AllDisks "$disk"); do
    printf '%s\n' "$part"
    if [ "$(dk_get "$part" Content)" = "Apple_APFS" ]; then
      container="$(dk_container_of "$part")"
      if [ -n "$container" ]; then
        dk_volumes_of_container "$container"
      fi
    fi
  done | sort -u
}

# dk_apfs_volumes_of_disk <whole-disk>
# Every APFS volume carried by this physical disk, one per line.
dk_apfs_volumes_of_disk() {
  local disk="$1" part container
  for part in $(dk_list_get AllDisks "$disk"); do
    [ "$(dk_get "$part" Content)" = "Apple_APFS" ] || continue
    container="$(dk_container_of "$part")"
    [ -n "$container" ] || continue
    dk_volumes_of_container "$container"
  done
}

# dk_identity <whole-disk>
# A fingerprint of the hardware and its current layout, including the partition
# UUIDs that diskutil reports. Taken before a confirmation prompt and compared
# after, it detects a disk that was swapped while the prompt waited, because
# identifiers are reassigned on every attach.
dk_identity() {
  local disk="$1"
  {
    dk_get "$disk" MediaName
    dk_get "$disk" TotalSize
    dk_get "$disk" DeviceBlockSize
    diskutil list -plist "$disk" 2>/dev/null
  } | md5 -q
}

# diskinfo.sh - read facts about a disk from diskutil's own plist output.
# Every fact here comes from `diskutil info -plist` or `diskutil list -plist`,
# so the tool never parses the human-readable columns, which are not a contract.

# dk_exists <identifier>
dk_exists() { diskutil info "$1" >/dev/null 2>&1; }

# dk_get <identifier> <plist-keypath>
# Prints the raw value, or nothing when the key is absent.
dk_get() {
  diskutil info -plist "$1" 2>/dev/null |
    plutil -extract "$2" raw -o - - 2>/dev/null || true
}

# dk_list_get <plutil-keypath> <diskutil-list-args...>
# Prints a JSON array from `diskutil list -plist`, one element per line.
dk_list_get() {
  keypath="$1"
  shift
  diskutil list -plist "$@" 2>/dev/null |
    plutil -extract "$keypath" json -o - - 2>/dev/null |
    tr -d '[]" ' | tr ',' '\n' | sed '/^$/d'
}

# dk_whole_disk_of <identifier>
# Resolves anything (a mount point, a partition, a synthesized APFS container)
# down to the physical whole disk that actually stores it. An APFS container is
# synthesized, so its ParentWholeDisk is itself; the physical store leads out.
dk_whole_disk_of() {
  id="$1"
  parent="$(dk_get "$id" ParentWholeDisk)"
  if [ -z "$parent" ]; then
    printf '%s' "$id"
    return 0
  fi
  store="$(dk_get "$parent" APFSPhysicalStores.0.APFSPhysicalStore)"
  if [ -n "$store" ] && [ "$store" != "$parent" ]; then
    dk_whole_disk_of "$store"
  else
    printf '%s' "$parent"
  fi
}

# dk_boot_disk
# The physical whole disk holding the running system volume.
dk_boot_disk() { dk_whole_disk_of /; }

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

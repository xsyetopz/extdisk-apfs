# inspect.sh - show what is attached and what a given disk currently holds.
# The refusals live in guard.sh, so that reporting and deciding stay apart.

# print_candidates
# One line per external physical whole disk. These are candidates, not approved
# targets: erase applies the full set of refusals in guard.sh to whichever one
# is named, and may still refuse it.
print_candidates() {
  local found=0 d
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
  say ''
  dim '  erase applies further checks and may refuse one of these'
}

# print_layout <whole-disk>
# The current partition layout and every mounted volume on that disk, so the
# operator sees what is about to be destroyed before confirming.
print_layout() {
  local disk="$1" mounted=0 member mp
  heading "Current layout of $disk"
  diskutil list "$disk"
  heading "Mounted volumes on $disk"
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

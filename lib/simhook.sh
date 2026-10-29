# simhook.sh - the shell startup line that attaches the simulator disk image.
# A LaunchAgent did not work, so the attach goes in the shell startup file.
# Measured on macOS 27.2: from a LaunchAgent, `diskutil image attach` on an
# image on the external volume failed with "Operation not permitted", and
# reading a file on that volume failed too, while the same agent attached an
# image on the boot volume with exit 0. A shell started by hand does both, and
# that shell has no Full Disk Access. No permission grant was tried, so this
# says a LaunchAgent is refused, not why.
# docs/simulator-startup-line.md has the evidence.
#
# The block is keyed "simulator <volume>", so host's own "<volume>" block and
# this one replace and remove independently. The word goes in front rather than
# behind, because a volume's mount point always starts with a slash, so no
# volume name can ever equal another volume's simulator key. A key of
# "<volume> simulator" would collide with the volume named "<volume> simulator".

simhook_key() { printf 'simulator %s\n' "$1"; }

# simhook_line <image> <set>
# One startup line, with every path quoted by shell_quote, because a volume
# named with a $ or a backtick would otherwise be expanded by every shell that
# reads the startup file.
#
# It must never fail the shell or print anything, so every branch ends in a
# true command and all output is discarded.
#
# The mount test is what keeps the mount single, not an optimisation. For this
# image at this point, diskutil is a no-op on a second attach, measured, and
# two shells racing leave one mount. But a second volume's block naming the
# same set path would stack a mount and hide the first, also measured, and the
# test is the only thing that stops it. It costs one `mount` call per shell.
simhook_line() {
  local image="$1" set="$2"
  printf '%s\n' "[ -d $(shell_quote "$image") ] && ! /sbin/mount | /usr/bin/grep -qF $(shell_quote " on $set (") && /usr/sbin/diskutil image attach --mountPoint $(shell_quote "$set") $(shell_quote "$image") >/dev/null 2>&1 || true"
}

# simhook_install <volume> <image> <set>
simhook_install() {
  env_block_put "$(simhook_key "$1")" 'simulator attach line' \
    "$(simhook_line "$2" "$3")"
}

# simhook_remove <volume>
simhook_remove() {
  local file key
  key="$(simhook_key "$1")"
  file="$(env_file)" || {
    warn "your shell is ${SHELL:-unknown}, so remove the '$key' block yourself"
    return 0
  }
  if [ ! -f "$file" ] || ! grep -qxF "$(env_marker_start "$key")" "$file"; then
    say "  skipped: $file has no $key block"
    return 0
  fi
  if [ "${DRY_RUN:-0}" = "1" ]; then
    dim "  would remove the $key block from $file"
    return 0
  fi
  env_block_strip "$file" "$key" || die "could not rewrite $file"
  say "  removed the $key block from $file"
}

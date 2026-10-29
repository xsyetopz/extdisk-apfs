# simdisk.sh - a simulator device set inside a disk image on the volume.
# CoreSimulatorService refuses a device set on a removable volume (EPERM), but
# a sparse bundle on that volume is not refused, so the devices go in an image
# and the image is mounted at the default device set path. docs/simulator-storage.md
# has the evidence. The startup line that attaches the image is in simhook.sh.
# Nothing here moves, copies or deletes the image or a device.

SIMDISK_VOLNAME='SimDevices'
SIMDISK_IMAGE='SimDevices.sparsebundle'

# The device set the image is mounted at. Xcode and Simulator read this path.
simdisk_devices() { printf '%s\n' "$HOME/Library/Developer/CoreSimulator/Devices"; }

# simdisk_size_ok <size>
# A number and a unit, such as 60g. diskutil --size reads a bare number as
# bytes, so 60 would mean 60 bytes. A size with no unit is refused rather than
# guessed at.
simdisk_size_ok() {
  case "$1" in
    [1-9]*) : ;;
    *) return 1 ;;
  esac
  case "${1//[0-9]/}" in
    k | K | m | M | g | G | t | T) return 0 ;;
    *) return 1 ;;
  esac
}

# simdisk_show_cmd <command...>
# Echoes a command the way run_cmd does, for the one step whose output is read.
simdisk_show_cmd() { dim "\$ $(shell_quote "$@")"; }

# simdisk_mount_of <image>
# The mount point of an attached image, or nothing. Read from hdiutil info,
# which is not deprecated. The mount point is the third tab-separated field.
simdisk_mount_of() {
  hdiutil info 2>/dev/null | awk -F'\t' -v img="$1" '
    /^=+$/ { inb = 0 }
    /^image-path/ { p = $0; sub(/^image-path *: /, "", p); inb = (p == img) }
    inb && /^\/dev\// && NF >= 3 && $3 != "" { m = $3 }
    END { sub(/ +$/, "", m); print m }
  '
}

# simdisk_info_field <path> <key>
# One value from diskutil info, such as "Mount Point" or "Device Node".
simdisk_info_field() {
  diskutil info "$1" 2>/dev/null | awk -F': +' -v key="$2" '
    { k = $1; sub(/^ +/, "", k) }
    k == key { print $2; exit }
  '
}

# simdisk_set_state <image>
# What is at the device set path: link, ours, elsewhere, foreign or free. A
# second mount on a mounted path hides the first, so only ours and free may be
# attached to. elsewhere is the image attached at some other point: diskutil
# then returns that point and ignores --mountPoint, measured, so attaching
# would report success and leave the set unmounted.
simdisk_set_state() {
  local dev mp
  dev="$(simdisk_devices)"
  mp="$(simdisk_mount_of "$1")"
  if [ -L "$dev" ]; then
    echo link
  elif [ -n "$mp" ] && [ "$mp" = "$dev" ]; then
    echo ours
  elif [ -n "$mp" ]; then
    echo elsewhere
  elif [ -d "$dev" ] && [ "$(simdisk_info_field "$dev" 'Mount Point')" = "$dev" ]; then
    echo foreign
  else
    echo free
  fi
}

# simdisk_booted
# The UDID of each booted simulator, one per line. simctl reads the same
# default device set the image is mounted at, so these are the devices in the
# image. A booted device holds files open on that mount: with one device booted
# lsof reported 227 open handles on it, so ejecting then is what makes macOS
# report a drive as not ejected properly.
#
# Nothing booted and "could not ask" are different answers, and the exit status
# is what tells them apart: 0 with no output means nothing is booted, non-zero
# means simctl could not answer. Without xcrun there is no simulator to be
# booted, so that is 0 with no output too. /usr/bin/xcrun is a shim present on
# practically every Mac, so the absent-binary case is not the common one: the
# common one is a shim whose simctl fails, with no Xcode selected or
# CoreSimulatorService down.
#
# simctl runs before the pipeline rather than inside it, because under pipefail
# a failing xcrun would make this function's own status non-zero and $(...) in
# a bare assignment would then abort the caller under set -e, with the stderr
# already discarded. Measured: a stand-in xcrun exiting 72 ended the script at
# the assignment with no message.
simdisk_booted() {
  local out
  command -v xcrun >/dev/null 2>&1 || return 0
  out="$(xcrun simctl list devices booted 2>/dev/null)" || return 1
  printf '%s\n' "$out" |
    awk 'match($0, /\(Booted\)/) {
      if (match($0, /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/))
        print substr($0, RSTART, RLENGTH)
    }'
}

# simdisk_set_check <image>
# Every refusal about the device set path, before anything is created or
# attached, so a refusal leaves nothing behind.
simdisk_set_check() {
  local dev node
  dev="$(simdisk_devices)"
  case "$(simdisk_set_state "$1")" in
    link)
      die "$dev is a symlink to $(readlink "$dev"), and a symlink cannot be a mount point; remove it yourself (rm $(shell_quote "$dev")) and run this again" ;;
    elsewhere)
      die "$1 is already attached at $(simdisk_mount_of "$1"), not at $dev; eject it first (diskutil eject $(shell_quote "$(simdisk_mount_of "$1")")) and run this again, because diskutil ignores --mountPoint for an image it has already attached" ;;
    foreign)
      node="$(simdisk_info_field "$dev" 'Device Node')"
      die "$dev already has ${node:-a volume} mounted on it, which is not $1; eject it first (diskutil eject $(shell_quote "$dev")), because a second mount would hide it" ;;
  esac
}

# simdisk_create <image> <size>
simdisk_create() {
  local image="$1" size="$2"
  if [ -e "$image" ]; then
    say "  skipped: $image exists, and $size applies only to a new image"
    return 0
  fi
  run_cmd diskutil image create blank --format UDSB --fs APFS \
    --volumeName "$SIMDISK_VOLNAME" --size "$size" "$image" ||
    die "diskutil could not create $image"
}

# simdisk_attach <image> <mount-point>
simdisk_attach() {
  local image="$1" dev="$2" out mp
  if [ "$(simdisk_set_state "$image")" = ours ]; then
    say "  skipped: already attached at $dev"
    return 0
  fi
  if [ "${DRY_RUN:-0}" = "1" ]; then
    run_cmd diskutil image attach --mountPoint "$dev" "$image"
    return 0
  fi
  simdisk_show_cmd diskutil image attach --mountPoint "$dev" "$image"
  out="$(diskutil image attach --mountPoint "$dev" "$image")" ||
    die "diskutil could not attach $image"
  mp="$(printf '%s\n' "$out" | awk -F'\t' '$3 != "" { m = $3 } END { sub(/ +$/, "", m); print m }')"
  [ "$mp" = "$dev" ] ||
    die "attached $image, but diskutil mounted it at ${mp:-no mount point}, not $dev; eject it and run this again"
  say "  attached at $dev"
}

# simdisk_up <volume> <size>
simdisk_up() {
  local volume="$1" size="$2" image dev
  guard_volume "$volume"
  image="$volume/$SIMDISK_IMAGE"
  dev="$(simdisk_devices)"
  simdisk_set_check "$image"

  heading "Hosting simulator devices on $volume"
  dim '  quit Xcode and Simulator first: the device set is covered by the image'
  say ''
  say "1. Disk image $image"
  simdisk_create "$image" "$size"
  say "2. Device set directory $dev"
  if [ -d "$dev" ]; then
    say '  skipped: it exists'
  else
    run_cmd mkdir -p "$dev" || die "could not create $dev"
  fi
  say '3. Attach at the device set'
  simdisk_attach "$image" "$dev"
  # A startup file this tool cannot name is not fatal: the image is attached
  # and usable now, and env_block_put has already printed the line to add.
  simhook_install "$volume" "$image" "$dev" ||
    warn "the image is attached, but nothing will attach it in a new shell until you add that line"

  heading 'Result'
  say "  image:   $image (grows on demand, up to $size)"
  say "  devices: $dev"
  dim '  no device data was copied or deleted'
  dim '  a new shell attaches the image whenever the drive is here'
}

# simdisk_down <volume>
# The reverse, in the safe order: the startup line, then the mount. The image
# stays.
#
# guard_volume is deliberately not called. It requires the volume to be mounted
# on an external disk, and undo has to work with the drive unplugged: that is
# when a user wants the startup line gone. Neither step needs the volume to be
# there. Removing the line needs only the key, and the eject needs only the
# device set path.
#
# The two checks that are kept do not need the volume to be mounted. An
# absolute path is what makes the key match the one simdisk wrote. The boot
# volume is refused as everywhere else in this tool, and diskutil is asked only
# when it knows the path at all, so an unplugged drive still passes.
simdisk_down() {
  local volume="$1" image dev mp booted ejected=0
  case "$volume" in
    /*) : ;;
    *) die "pass the volume's mount point, such as /Volumes/Scratch, not '$volume'" ;;
  esac
  mp="$(dk_get "$volume" MountPoint)"
  if [ "$volume" = "/" ] || [ "$mp" = "/" ]; then
    die "$volume is on the boot volume, and this tool only hosts data on an external disk"
  fi
  image="$volume/$SIMDISK_IMAGE"
  dev="$(simdisk_devices)"

  # Before anything changes, so a refusal does not leave the startup line gone
  # and the image still mounted. Ejecting a mount a booted simulator holds open
  # is what macOS reports as a drive not ejected properly.
  #
  # The assignment is the condition of the if, not a bare one, because set -e
  # ends the script on a bare assignment whose command substitution fails, and
  # a simctl that cannot answer must not be a silent exit. It is a warning and
  # not a refusal: undo has to work on a Mac with no usable Xcode, and the eject
  # itself fails safely when something holds the mount.
  if [ "$(simdisk_set_state "$image")" = ours ]; then
    if booted="$(simdisk_booted)"; then
      [ -z "$booted" ] ||
        die "$(printf '%s\n' "$booted" | wc -l | tr -d ' ') booted simulator(s) hold $dev open, so ejecting it now would be an improper ejection; shut them down first (xcrun simctl shutdown all) and run this again"
    else
      warn "simctl could not say which simulators are booted, so that was not checked; quit Xcode and any simulator first, because ejecting a mount one holds open is an improper ejection"
    fi
  fi

  heading "Giving $volume's simulator image back"
  say '1. The startup line'
  simhook_remove "$volume"
  say "2. Eject $dev"
  if [ "$(simdisk_set_state "$image")" = ours ]; then
    if run_cmd diskutil eject "$dev"; then
      ejected=1
    else
      warn "could not eject $dev; quit Xcode and any booted simulator, then run: diskutil eject $(shell_quote "$dev")"
    fi
  else
    say "  skipped: $image is not mounted at $dev"
    ejected=1
  fi

  heading 'Result'
  if [ -e "$image" ]; then
    say "  the image is still at $image"
    dim '  removing the image destroys the simulator devices inside it; this tool never does'
  else
    say "  there is no image at $image, so nothing of it was removed"
  fi
  if [ "$ejected" = "1" ]; then
    dim "  the device set at $dev is the one on this Mac again"
  else
    dim "  the image is still mounted at $dev, so the directory it covers is still hidden"
  fi
}

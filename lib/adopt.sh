# adopt.sh - making a volume host application data, and giving it back.
# Only the cli and env mechanisms in the catalogue can be written by a tool;
# the flag, file and ui ones are printed for the operator to do. Nothing here
# copies, moves or deletes a byte of application data.

# cli_argv <argv-template> <path>
# Fills CLI_ARGV, because bash 3.2 cannot return an array. Splitting the
# template on spaces and substituting into one token keeps the path a single
# argument even when it contains a space, and keeps the shell out of it: no
# eval touches this data.
cli_argv() {
  local template="$1" path="$2" token
  CLI_ARGV=()
  # Globbing off for the split: an unquoted expansion would turn a template
  # token containing * or ? into whatever files sit in the current directory.
  set -f
  for token in $template; do
    CLI_ARGV[${#CLI_ARGV[@]}]="${token//%s/$path}"
  done
  set +f
}

# cli_current <query-template>
# What the tool reports as its current value, with no path substituted. An
# empty answer is returned as empty; the caller says so rather than treating it
# as "does not point at this volume".
cli_current() {
  cli_argv "$1" ''
  "${CLI_ARGV[@]}" 2>/dev/null | head -n 1 || true
}

# guard_volume <path>
# A target volume has to be the mount point of a volume on an external
# physical disk, and writable by you. The same reasons as for erase: the boot
# volume and a disk image are not what this tool is for.
guard_volume() {
  local volume="$1" mp disk candidate external=0
  case "$volume" in
    /*) : ;;
    *) die "pass the volume's mount point, such as /Volumes/Scratch, not '$volume'" ;;
  esac
  [ -d "$volume" ] || die "'$volume' is not a directory"
  mp="$(dk_get "$volume" MountPoint)"
  [ -n "$mp" ] || die "diskutil does not know '$volume', so it is not a mounted volume"
  [ "$mp" = "$volume" ] ||
    die "'$volume' sits inside the volume mounted at '$mp'; pass that mount point instead"
  for disk in $(dk_whole_disks_of "$volume"); do
    for candidate in $(dk_external_whole_disks); do
      [ "$candidate" != "$disk" ] || external=1
    done
  done
  [ "$external" = "1" ] ||
    die "$volume is not on a disk in 'diskutil list external physical', and this tool only hosts data on an external disk"
  [ -w "$volume" ] ||
    die "$(id -un) cannot write to $volume; run: sudo chown $(id -u):$(id -g) $(shell_quote "$volume")"
}

# host_volume <volume> <only-ids-or-empty>
# Creates each directory, applies every cli and env row whose tool is
# installed, and prints the rest as steps for the operator.
host_volume() {
  local volume="$1" only="$2"
  local id name detect kind subdir setting query revert
  local target applied=0 manual=0 skipped=0
  local pairs='' manual_lines=''
  guard_volume "$volume"

  heading "Hosting application data on $volume"
  while IFS=$'\037' read -r id _ name _ detect kind subdir setting query revert _; do
    if [ -n "$only" ]; then
      case ",$only," in
        *",$id,"*) : ;;
        *) continue ;;
      esac
    fi
    host_installed "$detect" || { skipped=$((skipped + 1)); continue; }
    [ "$kind" != 'none' ] || { skipped=$((skipped + 1)); continue; }
    target="$volume"
    [ "$subdir" = '-' ] || target="$volume/$subdir"
    [ "$subdir" = '-' ] || run_cmd mkdir -p "$target" || die "could not create $target"
    case "$kind" in
      env)
        pairs="$pairs$(env_pair "$setting" "$target")
"
        applied=$((applied + 1))
        ;;
      cli)
        cli_argv "$setting" "$target"
        if run_cmd "${CLI_ARGV[@]}"; then
          applied=$((applied + 1))
        else
          warn "$name: the command failed, so nothing changed for it"
        fi
        ;;
      *)
        manual=$((manual + 1))
        # \037 between the name and the steps, matching the separator the rows
        # are read with, so a tab or a space inside either one is safe.
        manual_lines="$manual_lines$name"$'\037'"$(host_render "$setting" "$target")
"
        ;;
    esac
  done <<EOF
$(hosts_rows_us)
EOF

  # One variable per line, so a value containing a space survives.
  [ -z "$pairs" ] || env_block_write_lines "$volume" "$pairs"

  if [ -n "$manual_lines" ]; then
    heading 'Yours to set, because no command persists these'
    printf '%s' "$manual_lines" | while IFS=$'\037' read -r name setting; do
      printf '  %s\n    %s\n' "$name" "$setting"
    done
  fi

  heading 'Result'
  say "  applied:  $applied"
  say "  yours:    $manual"
  say "  skipped:  $skipped  (not installed, or nothing can move)"
  dim '  no application data was copied, moved or deleted'
}

# env_block_write_lines <volume> <newline-separated VAR="value" lines>
# A wrapper, because the pairs are collected as text in bash 3.2 rather than
# as an array that survives a subshell.
env_block_write_lines() {
  local volume="$1" text="$2" line
  local args=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    args[${#args[@]}]="$line"
  done <<EOF
$text
EOF
  env_block_write "$volume" ${args[@]+"${args[@]}"}
}

# unhost_volume <volume>
# Removes the environment block and undoes each cli setting that still points
# into this volume. It leaves every directory and every byte in them alone.
unhost_volume() {
  local volume="$1" file reverted=0 left=0
  local id name detect kind subdir setting query revert current
  file="$(env_file)" || file=''
  heading "Giving $volume back"
  if [ -n "$file" ] && [ -f "$file" ]; then
    if grep -qF "$(env_marker_start "$volume")" "$file"; then
      if [ "${DRY_RUN:-0}" = "1" ]; then
        say "  would remove the extdisk-apfs block for $volume from $file"
      else
        env_block_strip "$file" "$volume" && say "  removed the block for $volume from $file"
      fi
    else
      say "  no extdisk-apfs block for $volume in $file"
    fi
  fi
  while IFS=$'\037' read -r id _ name _ detect kind subdir setting query revert _; do
    [ "$kind" = 'cli' ] || continue
    host_installed "$detect" || continue
    current="$(cli_current "$query")"
    if [ -z "$current" ]; then
      warn "$name: '$query' printed nothing, so its setting was left as it is"
      left=$((left + 1))
      continue
    fi
    # The expansion is quoted, so a volume named with a *, a ? or a [ is
    # matched literally rather than as a pattern.
    case "$current" in
      "$volume" | "$volume"/*)
        cli_argv "$revert" ''
        if run_cmd "${CLI_ARGV[@]}"; then
          reverted=$((reverted + 1))
        else
          warn "$name: could not undo the setting; it still points at $current"
        fi
        ;;
      *) left=$((left + 1)) ;;
    esac
  done <<EOF
$(hosts_rows_us)
EOF
  heading 'Result'
  say "  undone:   $reverted"
  say "  untouched: $left  (their setting does not point at $volume)"
  dim "  the directories on $volume and everything in them are still there"
}

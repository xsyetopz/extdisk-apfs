# envblock.sh - marked blocks in the shell startup file.
# Several commands have to leave a line in a file the operator owns: the
# environment variables that host puts an application's data on the volume, and
# the line that attaches the simulator disk image. Each block is keyed, so each
# one is written, replaced and removed on its own, and the rest of the file is
# never touched. zsh reads .zshenv for every shell, including a non-interactive
# one, which is what a build tool started by an editor gets, so that is the
# target.

# env_file
# Where an exported variable has to go to outlive the shell. zsh reads .zshenv
# for every shell, including a non-interactive one, which is what a build tool
# started by an editor gets.
env_file() {
  if [ -n "${EXTDISK_ENV_FILE:-}" ]; then
    printf '%s\n' "$EXTDISK_ENV_FILE"
    return 0
  fi
  case "${SHELL:-}" in
    */zsh) printf '%s\n' "$HOME/.zshenv" ;;
    */bash) printf '%s\n' "$HOME/.bash_profile" ;;
    *) return 1 ;;
  esac
}

env_marker_start() { printf '# >>> extdisk-apfs %s >>>\n' "$1"; }
env_marker_end() { printf '# <<< extdisk-apfs %s <<<\n' "$1"; }

# env_block_strip <file> <volume>
# Removes this volume's block, so writing is idempotent and unhost is just
# this step. The comparison is on the whole line, not a pattern, because a
# volume name can contain a regular expression character.
env_block_strip() {
  local file="$1" volume="$2" start end tmp starts ends
  [ -f "$file" ] || return 0
  start="$(env_marker_start "$volume")"
  end="$(env_marker_end "$volume")"
  starts="$(grep -cxF "$start" "$file" || true)"
  ends="$(grep -cxF "$end" "$file" || true)"
  [ "$starts" != "0" ] || return 0
  # An unbalanced pair means someone edited the file by hand. Skipping from the
  # start marker to a missing end marker would drop every line after it, so
  # refuse and let the operator look.
  [ "$starts" = "$ends" ] ||
    die "$file has $starts start markers and $ends end markers for $volume; fix them by hand, because removing the block would delete the rest of the file"
  tmp="$file.extdisk-tmp.$$"
  awk -v s="$start" -v e="$end" '
    $0 == s { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip
  ' "$file" >"$tmp" || { rm -f "$tmp"; return 1; }
  # Copied back rather than moved over: a .zshenv managed by a dotfiles
  # repository is a symlink, and mv would replace the link with a regular file
  # and reset its mode. cp writes through the link.
  cp "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
}

# env_block_read <file> <key>
# The lines inside <key>'s block, or nothing. The comparison is on the whole
# line, as in env_block_strip, because a volume name can contain a regular
# expression character.
env_block_read() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  awk -v s="$(env_marker_start "$key")" -v e="$(env_marker_end "$key")" '
    $0 == e { inb = 0 }
    inb { print }
    $0 == s { inb = 1 }
  ' "$file"
}

# env_block_put <key> <what> <line...>
# Writes <key>'s marked block, replacing one already there. The lines go in as
# given, so a caller that wants an export writes the word itself. <key> is what
# env_block_strip removes, so two blocks with different keys do not disturb
# each other. <what> names the block in the output.
env_block_put() {
  local key="$1" what="$2" file line backup
  shift 2
  file="$(env_file)" || {
    warn "your shell is ${SHELL:-unknown}, so I do not know which startup file to write; add these lines yourself:"
    for line in "$@"; do say "  $line"; done
    return 1
  }
  heading "Writing the $what in $file"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    dim "$(env_marker_start "$key")"
    for line in "$@"; do dim "$line"; done
    dim "$(env_marker_end "$key")"
    return 0
  fi
  # A block already exactly right is left alone, so a second run writes no
  # backup and does not touch the file's timestamp. Without this, running the
  # same command twice leaves a new .extdisk-backup copy each time.
  if [ -f "$file" ] && [ "$(env_block_read "$file" "$key")" = "$(printf '%s\n' "$@")" ]; then
    say "  skipped: the block in $file is already this"
    return 0
  fi
  if [ -f "$file" ]; then
    backup="$file.extdisk-backup.$(date +%Y%m%d%H%M%S)"
    cp "$file" "$backup" || die "could not back up $file, so it was not changed"
    say "  backed up to $backup"
  fi
  env_block_strip "$file" "$key" || die "could not rewrite $file"
  {
    env_marker_start "$key"
    for line in "$@"; do printf '%s\n' "$line"; done
    env_marker_end "$key"
  } >>"$file" || die "could not append to $file"
  for line in "$@"; do say "  $line"; done
  dim '  a new shell picks this up; this one does not'
}

# env_block_write <volume> <VAR=value...>
# EXPORT_LINES is local, so a nested call cannot see the caller's copy, and the
# empty case returns before the expansion: "${arr[@]}" on an empty array is an
# unbound variable under bash 3.2 with set -u.
env_block_write() {
  local volume="$1" pair
  local EXPORT_LINES
  shift
  [ $# -gt 0 ] || return 0
  EXPORT_LINES=()
  for pair in "$@"; do EXPORT_LINES[${#EXPORT_LINES[@]}]="export $pair"; done
  env_block_put "$volume" 'environment block' "${EXPORT_LINES[@]}"
}

# env_pair <VAR> <path>
# One line for the block. Quoted by printf %q rather than wrapped in double
# quotes: a volume named with a $ or a backtick would otherwise be expanded, or
# run a command substitution, every time a shell sources the startup file.
env_pair() { printf '%s=%s\n' "$1" "$(shell_quote "$2")"; }

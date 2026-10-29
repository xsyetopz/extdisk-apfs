# ui.sh - terminal output and the typed confirmation prompt.
# Sourced by bin/extdisk-apfs. Not executable on its own.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'
  C_YEL=$'\033[33m'
  C_GRN=$'\033[32m'
  C_DIM=$'\033[2m'
  C_OFF=$'\033[0m'
else
  C_BOLD='' C_RED='' C_YEL='' C_GRN='' C_DIM='' C_OFF=''
fi

say() { printf '%s\n' "$*"; }

heading() { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_OFF"; }

dim() { printf '%s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }

warn() { printf '%swarning: %s%s\n' "$C_YEL" "$*" "$C_OFF" >&2; }

ok() { printf '%s%s%s\n' "$C_GRN" "$*" "$C_OFF"; }

die() {
  printf '%serror: %s%s\n' "$C_RED" "$*" "$C_OFF" >&2
  exit 1
}

# run_cmd <command...>
# Prints the command, then runs it unless DRY_RUN is 1.
run_cmd() {
  printf '%s$ %s%s\n' "$C_DIM" "$*" "$C_OFF"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    return 0
  fi
  "$@"
}

# confirm_identifier <expected-identifier>
# Requires the operator to retype the disk identifier, so that a wrong
# identifier on the command line cannot destroy a disk by itself.
confirm_identifier() {
  expected="$1"
  if [ ! -t 0 ]; then
    die "stdin is not a terminal, so the erase cannot be confirmed; rerun with --force only if you are sure of $expected"
  fi
  printf '%sType %s to erase it. Anything else aborts: %s' "$C_BOLD" "$expected" "$C_OFF"
  IFS= read -r typed || typed=''
  if [ "$typed" != "$expected" ]; then
    die "you typed '$typed' and the target is '$expected', so nothing was changed"
  fi
}

# human_size <bytes>
# Formats a byte count the way diskutil reports it, in decimal GB.
human_size() {
  awk -v b="${1:-0}" 'BEGIN {
    if (b >= 1000000000000) printf "%.1f TB", b / 1000000000000;
    else if (b >= 1000000000) printf "%.1f GB", b / 1000000000;
    else if (b >= 1000000) printf "%.1f MB", b / 1000000;
    else printf "%d B", b;
  }'
}

# tests/helpers.sh - the counters and assertions that tests/run and
# tests/run-simdisk share. Sourced, never run.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # used by the files that source this one
BIN="$ROOT/bin/extdisk-apfs"
PASS=0
FAIL=0
SKIP=0

# A scratch directory for the catalogue fixtures and the shell startup file
# that the env-block tests write. Removed on exit, including on a failure.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/extdisk-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass() {
  PASS=$((PASS + 1))
  printf '  ok    %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL  %s\n' "$1" >&2
  [ -z "${2:-}" ] || printf '        %s\n' "$2" >&2
}

skip() {
  SKIP=$((SKIP + 1))
  printf '  skip  %s (%s)\n' "$1" "$2"
}

# exits_zero <description> <command...>
exits_zero() {
  local desc="$1" out
  shift
  if out="$("$@" 2>&1)"; then
    pass "$desc"
  else
    fail "$desc" "exit $?: $(printf '%s' "$out" | tail -n 1)"
  fi
}

# exits_nonzero <description> <command...>
exits_nonzero() {
  local desc="$1" out
  shift
  if out="$("$@" 2>&1)"; then
    fail "$desc" 'exit 0, so it was accepted'
  else
    pass "$desc"
  fi
}

# equals <description> <expected> <actual>
equals() {
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail "$1" "wanted '$2', got '$3'"
  fi
}

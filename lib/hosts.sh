# hosts.sh - the catalogue: which applications can keep their data on the
# volume, and how each one is told to. The facts live in data/hosts.tsv; this
# file reads them, decides what is installed, and prints. Writing a setting is
# in adopt.sh, so reporting and changing stay apart.

HOST_CATEGORIES='dev apple audio container'

# hosts_file
# ROOT is set by bin/extdisk-apfs. EXTDISK_HOSTS overrides the path, which is
# how a test points at a fixture.
hosts_file() { printf '%s\n' "${EXTDISK_HOSTS:-$ROOT/data/hosts.tsv}"; }

# hosts_rows
# Every data row: no comment, no blank line, and not the header.
hosts_rows() {
  awk -F'\t' 'NF > 0 && $1 !~ /^#/ && $1 != "id"' "$(hosts_file)"
}

# hosts_rows_us
# The same rows with every tab turned into a unit separator. Tab is an IFS
# whitespace character, so `IFS=$'\t' read` collapses two tabs into one: a row
# with an empty field would shift every later field by one, and validation
# would read the wrong column. \037 is not whitespace, so read keeps the empty
# field and the row fails validation as it should.
hosts_rows_us() { hosts_rows | tr '\t' '\037'; }

# host_row <id>
hosts_row() { awk -F'\t' -v want="$1" '$1 == want' "$(hosts_file)"; }

# host_field <field-number> <row>
host_field() { printf '%s\n' "$2" | cut -f "$1"; }

# host_ids
host_ids() { hosts_rows | cut -f 1; }

# host_render <template> <path>
# Substitutes the path into the template. A plain string replacement, so a
# path containing % or $ stays literal.
host_render() { printf '%s\n' "${1//%s/$2}"; }

# host_installed <detect-field>
# cmd:NAME on the PATH, path:PATH present, glob:PATTERN matching something, or
# always. find does the glob, because a pattern such as
# /Applications/Ableton Live*.app contains a space and would word-split.
host_installed() {
  local detect="$1" target="${1#*:}"
  case "$detect" in
    always) return 0 ;;
    cmd:*) command -v "$target" >/dev/null 2>&1 ;;
    path:*) [ -e "$target" ] ;;
    glob:*)
      [ -n "$(find "$(dirname "$target")" -maxdepth 1 -name "$(basename "$target")" -print -quit 2>/dev/null)" ]
      ;;
    *) return 1 ;;
  esac
}

# hosts_validate
# Checks the catalogue itself and prints one line per problem. Used by
# tests/run, so a malformed row fails CI rather than surfacing as a confusing
# command at erase time.
hosts_validate() {
  local problems=0 row id category name scope detect kind subdir setting query revert source
  local seen=''
  [ -r "$(hosts_file)" ] || {
    printf 'catalogue is not readable: %s\n' "$(hosts_file)"
    return 1
  }
  while IFS=$'\037' read -r id category name scope detect kind subdir setting query revert source _; do
    row="$id"
    case " $seen " in
      *" $id "*) printf '%s: duplicate id\n' "$row"; problems=$((problems + 1)) ;;
    esac
    seen="$seen $id"
    case "$id" in
      *[^a-z0-9-]* | '') printf '%s: id is not kebab-case\n' "$row"; problems=$((problems + 1)) ;;
    esac
    case " $HOST_CATEGORIES " in
      *" $category "*) : ;;
      *) printf '%s: category %s is not one of %s\n' "$row" "$category" "$HOST_CATEGORIES"; problems=$((problems + 1)) ;;
    esac
    case "$scope" in
      full | partial | none) : ;;
      *) printf '%s: scope %s is not full, partial or none\n' "$row" "$scope"; problems=$((problems + 1)) ;;
    esac
    case "$detect" in
      always | cmd:?* | path:?* | glob:?*) : ;;
      *) printf '%s: detect %s is not always, cmd:, path: or glob:\n' "$row" "$detect"; problems=$((problems + 1)) ;;
    esac
    case "$kind" in
      cli | env | ui | flag | file | none) : ;;
      *) printf '%s: kind %s is not cli, env, ui, flag, file or none\n' "$row" "$kind"; problems=$((problems + 1)) ;;
    esac
    if [ "$subdir" != '-' ]; then
      case "$subdir" in
        *[!a-zA-Z0-9._-]* | '')
          printf '%s: subdir %s has a character that is not safe in a directory name\n' "$row" "$subdir"
          problems=$((problems + 1))
          ;;
      esac
    fi
    [ -n "$name" ] || { printf '%s: name is empty\n' "$row"; problems=$((problems + 1)); }
    [ -n "$source" ] || { printf '%s: source is empty, and an unsourced claim does not belong here\n' "$row"; problems=$((problems + 1)); }
    [ -n "$setting" ] || { printf '%s: setting is empty\n' "$row"; problems=$((problems + 1)); }
    # A mechanism that takes a path has to say where the path goes.
    case "$kind" in
      cli | flag | ui | file)
        case "$setting" in
          *%s*) : ;;
          *) printf '%s: kind %s needs %%s in the setting\n' "$row" "$kind"; problems=$((problems + 1)) ;;
        esac
        ;;
      env)
        case "$setting" in
          *[!A-Z0-9_]* | '') printf '%s: env setting %s is not a variable name\n' "$row" "$setting"; problems=$((problems + 1)) ;;
        esac
        [ "$subdir" != '-' ] || { printf '%s: an env row needs a subdir to point the variable at\n' "$row"; problems=$((problems + 1)); }
        ;;
    esac
    # cli rows are applied and reverted by this tool, so both templates and
    # the query that reads the current value have to be there.
    if [ "$kind" = 'cli' ]; then
      [ "$query" != '-' ] || { printf '%s: a cli row needs a query template\n' "$row"; problems=$((problems + 1)); }
      [ "$revert" != '-' ] || { printf '%s: a cli row needs a revert template\n' "$row"; problems=$((problems + 1)); }
    fi
  done <<EOF
$(hosts_rows_us)
EOF
  [ "$problems" = "0" ]
}

# print_hosts <volume-or-empty> <all 0|1>
# The survey. Installed things first, because that is what the operator can
# act on; --all adds the rest.
print_hosts() {
  local volume="$1" all="$2" hidden=0 shown=0 category
  heading "What can host its data on ${volume:-an external volume}"
  for category in $HOST_CATEGORIES; do
    local printed_header=0 id name scope kind detect installed
    while IFS=$'\037' read -r id _ name scope detect kind _; do
      if host_installed "$detect"; then installed=yes; else installed=no; fi
      if [ "$installed" = "no" ] && [ "$all" != "1" ]; then
        hidden=$((hidden + 1))
        continue
      fi
      if [ "$printed_header" = "0" ]; then
        printf '\n  %s\n' "$category"
        printf '  %-24s %-38s %-8s %-6s %s\n' ID NAME HOSTS HOW INSTALLED
        printed_header=1
      fi
      shown=$((shown + 1))
      printf '  %-24s %-38s %-8s %-6s %s\n' "$id" "$name" "$scope" "$kind" "$installed"
    done <<EOF
$(hosts_rows | awk -F'\t' -v c="$category" '$2 == c' | tr '\t' '\037')
EOF
  done
  say ''
  if [ "$hidden" -gt 0 ]; then
    dim "  $shown shown, $hidden not installed and hidden"
  else
    dim "  $shown shown"
  fi
  dim "  hosts --all shows every entry; explain <id> shows one in full"
  dim '  HOW: cli and env are applied by host; flag, file and ui you set yourself'
}

# print_host <id> <volume-or-empty>
# One entry in full, with the path substituted when a volume is given.
print_host() {
  local id="$1" volume="$2" row
  row="$(hosts_row "$id")"
  [ -n "$row" ] || die "no catalogue entry with id '$id'; run 'extdisk-apfs hosts --all' for the ids"
  local name scope detect kind subdir setting query revert source note target
  name="$(host_field 3 "$row")"
  scope="$(host_field 4 "$row")"
  detect="$(host_field 5 "$row")"
  kind="$(host_field 6 "$row")"
  subdir="$(host_field 7 "$row")"
  setting="$(host_field 8 "$row")"
  query="$(host_field 9 "$row")"
  revert="$(host_field 10 "$row")"
  source="$(host_field 11 "$row")"
  note="$(host_field 12 "$row")"
  target="$volume"
  [ "$subdir" = '-' ] || [ -z "$volume" ] || target="$volume/$subdir"

  heading "$name"
  printf '  id:        %s\n' "$id"
  printf '  hosts:     %s\n' "$scope"
  printf '  mechanism: %s\n' "$kind"
  if host_installed "$detect"; then
    printf '  installed: yes (%s)\n' "$detect"
  else
    printf '  installed: no (%s)\n' "$detect"
  fi
  [ -z "$target" ] || printf '  directory: %s\n' "$target"
  case "$kind" in
    none) printf '  why not:   %s\n' "$setting" ;;
    env) printf '  variable:  %s=%s\n' "$setting" "${target:-<volume>}" ;;
    *) printf '  setting:   %s\n' "$(host_render "$setting" "${target:-<volume>}")" ;;
  esac
  if [ "$kind" = 'cli' ]; then
    printf '  current:   %s\n' "$query"
    printf '  undo:      %s\n' "$revert"
  fi
  printf '  source:    %s\n' "$source"
  [ "$note" = '-' ] || printf '  note:      %s\n' "$note"
}

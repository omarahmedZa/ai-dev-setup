#!/usr/bin/env bash
# ai-dev-setup installer: CLI contract and preflight.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC2034 # consumed by later installation stages
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
LOCKHASH_FILE="$CFG/.lockhash"

DRY_RUN=false
# shellcheck disable=SC2034 # consumed by later installation stages
FORCE=false
# shellcheck disable=SC2034 # consumed by later installation stages
CONFIG_ONLY=false
# shellcheck disable=SC2034 # consumed by later installation stages
WITH_HEADROOM=false
DOCTOR=false
HELP=false

NVM_HINT='curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash && nvm install --lts'

usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Options:
  --dry-run        Print every action, write nothing
  --force          Overwrite changed files even if they differ from the repo
                   (a backup is still taken)
  --config-only    Skip binary installation; do config, plugins, npm install,
                   skills and delegation lanes
  --with-headroom  After the config install, run
                   `headroom deploy --target opencode --port 8787`, then
                   re-assert the repo config
  --doctor         Run checks only; exit non-zero on failure
  --help           Show this help and exit
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage_error() {
  printf 'error: %s\n' "$*" >&2
  printf '\n' >&2
  usage >&2
  exit 2
}

# need_cmd <command> [hint]
need_cmd() {
  local cmd=$1 hint=${2:-}
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "missing required command: $cmd${hint:+ ($hint)}"
  fi
}

check_node() {
  local version major
  if ! version=$(node -v 2>/dev/null); then
    die "Node.js >= 18 is required but node was not found; install it with: $NVM_HINT"
  fi
  version=${version#v}
  major=${version%%.*}
  if [[ ! "$major" =~ ^[0-9]+$ ]] || (( 10#$major < 18 )); then
    die "Node.js >= 18 is required (found $version); install it with: $NVM_HINT"
  fi
}

check_payload() {
  local dir
  for dir in config plugins skills delegate; do
    if [[ ! -d "$ROOT/$dir" ]]; then
      die "not a complete checkout: $ROOT/$dir is missing"
    fi
  done
}

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --dry-run) DRY_RUN=true ;;
      --force) FORCE=true ;;
      --config-only) CONFIG_ONLY=true ;;
      --with-headroom) WITH_HEADROOM=true ;;
      --doctor) DOCTOR=true ;;
      --help | -h) HELP=true ;;
      --)
        shift
        break
        ;;
      -*)
        usage_error "unknown option: $1"
        ;;
      *)
        usage_error "unexpected argument: $1"
        ;;
    esac
    shift
  done

  if (( $# > 0 )); then
    usage_error "unexpected argument: $1"
  fi
}

BACKUP_DIR=""
SKIPPED=0
INSTALLED=0
REMOVED=0
CHANGED=()    # existing destinations that differ from the repo (drift)
PLAN_SRC=()   # copies deferred until after the drift decision
PLAN_DEST=()
FILE_MAP=()

# Relative path of an installed file, used both for backup and messages.
relative_install_path() {
  local path=$1
  case "$path" in
    "$CFG"/*) printf '%s\n' "${path#"$CFG"/}" ;;
    "$HOME/.config"/*) printf '%s\n' "${path#"$HOME/.config"/}" ;;
    "$HOME"/*) printf '%s\n' "${path#"$HOME"/}" ;;
    *) printf '%s\n' "${path#/}" ;;
  esac
}

# backup_file <path>: copy an installed file into $BACKUP_DIR, preserving its
# path relative to $CFG (or $HOME/.config for the delegation config).
backup_file() {
  local path=$1 rel dest
  rel=$(relative_install_path "$path")
  dest="$BACKUP_DIR/$rel"
  mkdir -p "$(dirname "$dest")"
  cp "$path" "$dest"
  printf 'backup: %s -> %s\n' "$path" "$dest"
}

# plan_file <src> <dest>: decide what one payload file needs and, for an
# existing destination that will be replaced, take its backup now. Copies are
# queued in PLAN_SRC/PLAN_DEST so a drift abort can stop before any destination
# is created or modified. Drift is recorded in CHANGED.
plan_file() {
  local src=$1 dest=$2
  if [[ -e "$dest" ]] && cmp -s "$src" "$dest"; then
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    if [[ -e "$dest" ]]; then
      printf 'would overwrite %s\n' "$dest"
    else
      printf 'would create %s\n' "$dest"
    fi
    return 0
  fi

  if [[ -e "$dest" ]]; then
    backup_file "$dest"
    CHANGED+=("$dest")
  fi

  PLAN_SRC+=("$src")
  PLAN_DEST+=("$dest")
}

# apply_files: perform every queued copy (the apply phase).
apply_files() {
  local i dest
  for i in "${!PLAN_SRC[@]}"; do
    dest=${PLAN_DEST[$i]}
    mkdir -p "$(dirname "$dest")"
    cp "${PLAN_SRC[$i]}" "$dest"
    INSTALLED=$((INSTALLED + 1))
    printf 'installed %s\n' "$dest"
  done
}

# remove_stale <path>: back up and delete one known-obsolete config file.
remove_stale() {
  local path=$1
  [[ -e "$path" ]] || return 0

  if [[ "$DRY_RUN" == true ]]; then
    printf 'would remove stale %s\n' "$path"
    return 0
  fi

  backup_file "$path"
  rm -- "$path"
  REMOVED=$((REMOVED + 1))
  printf 'removed stale %s\n' "$path"
}

# ensure_plugin_deps: local plugins import @opencode/plugin, so $CFG needs
# node_modules. Install only when the plugin is missing or the installed
# lockfile differs from the hash recorded at the last successful install.
ensure_plugin_deps() {
  local plugin_dir="$CFG/node_modules/@opencode/plugin"
  local lock_file="$CFG/package-lock.json"
  local hash

  # In a dry run the payload is not copied; report against what would be
  # installed by hashing the repository lockfile.
  if [[ "$DRY_RUN" == true ]]; then
    lock_file="$ROOT/config/package-lock.json"
  fi
  hash=$(sha256sum "$lock_file" | awk '{print $1}')

  if [[ -e "$plugin_dir" && -f "$LOCKHASH_FILE" ]] &&
     [[ "$(cat "$LOCKHASH_FILE")" == "$hash" ]]; then
    printf 'plugin deps up to date\n'
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    printf 'would run: npm install --omit=dev (in %s)\n' "$CFG"
    return 0
  fi

  ( cd "$CFG" && npm install --omit=dev ) || die "npm install failed"

  sha256sum "$CFG/package-lock.json" | awk '{print $1}' > "$LOCKHASH_FILE"
  printf 'installed plugin dependencies\n'
}

# build_file_map: src|dest pairs for the config payload. Recursion over
# plugins/ and skills/ preserves relative paths (including dotfiles).
build_file_map() {
  FILE_MAP=(
    "$ROOT/config/opencode.jsonc|$CFG/opencode.jsonc"
    "$ROOT/config/cli.json|$CFG/cli.json"
    "$ROOT/config/AGENTS.md|$CFG/AGENTS.md"
    "$ROOT/config/package.json|$CFG/package.json"
    "$ROOT/config/package-lock.json|$CFG/package-lock.json"
    "$ROOT/delegate/config.json|$HOME/.config/delegate-skills/config.json"
  )
  local src
  while IFS= read -r src; do
    FILE_MAP+=("$src|$CFG/${src#"$ROOT"/}")
  done < <(find "$ROOT/plugins" "$ROOT/skills" -type f -print | LC_ALL=C sort)
}

install_all() {
  BACKUP_DIR="$CFG/backups/$(date -u +%Y%m%dT%H%M%SZ)"
  SKIPPED=0
  INSTALLED=0
  REMOVED=0
  CHANGED=()
  PLAN_SRC=()
  PLAN_DEST=()

  build_file_map
  local entry src dest
  for entry in "${FILE_MAP[@]}"; do
    src=${entry%%|*}
    dest=${entry#*|}
    plan_file "$src" "$dest"
  done

  # Dry-run reports the whole plan (including stale removals) and writes nothing.
  if [[ "$DRY_RUN" == true ]]; then
    remove_stale "$CFG/opencode.json"
    remove_stale "$CFG/opencode.jsonc.headroom-backup"
    ensure_plugin_deps
    return 0
  fi

  # Drift abort: every backup is already written, but no destination has been
  # created, modified, or removed.
  if (( ${#CHANGED[@]} > 0 )) && [[ "$FORCE" != true ]]; then
    printf 'refusing to overwrite: %s\n' "${CHANGED[@]}" >&2
    die "config differs from the repository; re-run with --force (backups are kept)"
  fi

  apply_files

  remove_stale "$CFG/opencode.json"
  remove_stale "$CFG/opencode.jsonc.headroom-backup"

  ensure_plugin_deps

  if (( INSTALLED == 0 && REMOVED == 0 && SKIPPED > 0 )); then
    printf 'up to date (%d files unchanged)\n' "$SKIPPED"
  fi

  print_next_steps
}

print_next_steps() {
  cat <<'EOF'

Next steps (run these manually):
  - opencode auth login
  - headroom: sign in to your headroom account if the proxy backend requires one
  - GitHub over HTTPS: authenticate with `gh auth login`
EOF
}

# Placeholder until the doctor checks land in a later task.
doctor() {
  printf 'doctor: not implemented yet\n'
  return 0
}

main() {
  parse_args "$@"

  if [[ "$HELP" == true ]]; then
    usage
    return 0
  fi

  need_cmd bash
  need_cmd curl
  check_node
  check_payload

  if [[ "$DOCTOR" == true ]]; then
    doctor
    return 0
  fi

  install_all
}

main "$@"

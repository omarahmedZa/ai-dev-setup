#!/usr/bin/env bash
# ai-dev-setup installer: CLI contract and preflight.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC2034 # consumed by later installation stages
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

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

# Placeholder until the copy engine lands in a later task.
install_all() {
  printf 'nothing to do yet\n'
  return 0
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

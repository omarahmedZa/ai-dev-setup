#!/usr/bin/env bash
# ai-dev-setup installer: CLI contract and preflight.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC2034 # consumed by later installation stages
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
LOCKHASH_FILE="$CFG/.lockhash"

# Tools installed without root land here; let later checks see them in this run.
PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
export PATH

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
DELEGATE_REPO='amElnagdy/delegate-skills'
FIND_SKILLS='vercel-labs/skills@find-skills'

OPENCODE_INSTALL='curl -fsSL https://opencode.ai/v2/install | bash'
UV_INSTALL='curl -LsSf https://astral.sh/uv/install.sh | sh'
RTK_INSTALL='curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh'
HEADROOM_INSTALL='uv tool install headroom-ai'
GRAPHIFY_INSTALL='uv tool install graphifyy'

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

# ensure_bin <command> <install-command>: report what is present, install the
# missing ones with the upstream installer unless this is a dry run.
ensure_bin() {
  local cmd=$1 install_cmd=$2 version
  if command -v "$cmd" >/dev/null 2>&1; then
    version=$("$cmd" --version 2>/dev/null | head -n 1) || version=""
    printf 'found %s %s\n' "$cmd" "${version:-unknown}"
    return 0
  fi

  printf 'missing %s: %s\n' "$cmd" "$install_cmd"
  if [[ "$DRY_RUN" == true ]]; then
    return 0
  fi

  bash -o pipefail -c "$install_cmd" || die "failed to install $cmd"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "installer for $cmd did not produce a working $cmd"
  fi
}

# install_binaries: external tools the config depends on. --config-only skips
# this whole phase so no installer is piped from the network.
install_binaries() {
  ensure_bin opencode "$OPENCODE_INSTALL"
  ensure_bin uv "$UV_INSTALL"
  ensure_bin rtk "$RTK_INSTALL"
  ensure_bin headroom "$HEADROOM_INSTALL"
  ensure_bin graphify "$GRAPHIFY_INSTALL"
}

# deploy_headroom: opt-in proxy setup. `headroom deploy` rewrites
# $CFG/opencode.jsonc, so the repository copy is re-asserted afterwards and
# always wins. A deploy failure only warns.
deploy_headroom() {
  [[ "$WITH_HEADROOM" == true ]] || return 0

  if [[ "$DRY_RUN" == true ]]; then
    printf 'would run: headroom deploy --target opencode --port 8787\n'
    return 0
  fi

  if headroom deploy --target opencode --port 8787; then
    printf 'headroom deployed\n'
  else
    printf 'warning: headroom deploy failed; keeping the repository config\n' >&2
  fi

  mkdir -p "$CFG"
  cp "$ROOT/config/opencode.jsonc" "$CFG/opencode.jsonc"
  printf 're-asserted %s\n' "$CFG/opencode.jsonc"
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

  # npm may rewrite package.json/package-lock.json (for example, normalizing
  # the root name from the directory). Re-assert the repository files so the
  # installed lock always matches the committed payload, then stamp its hash.
  cp "$ROOT/config/package.json" "$CFG/package.json"
  cp "$ROOT/config/package-lock.json" "$CFG/package-lock.json"

  sha256sum "$CFG/package-lock.json" | awk '{print $1}' > "$LOCKHASH_FILE"
  printf 'installed plugin dependencies\n'
}

# install_skills: delegation skills come from the upstream skills CLI, which
# owns its install path under $HOME/.agents/skills.
install_skills() {
  if [[ "$DRY_RUN" == true ]]; then
    printf 'would run: npx --yes skills add %s -g -y\n' "$DELEGATE_REPO"
    printf 'would run: npx --yes skills add %s -g -y\n' "$FIND_SKILLS"
    return 0
  fi

  # A fully provisioned rerun needs no network: only --force updates the
  # upstream skills, and a genuinely missing skill tree still installs.
  if [[ "$FORCE" != true ]]; then
    local skill all_present=true
    for skill in opencode-delegate delegate-setup find-skills; do
      if [[ ! -f "$HOME/.agents/skills/$skill/SKILL.md" ]]; then
        all_present=false
        break
      fi
    done
    if [[ "$all_present" == true ]]; then
      printf 'skills up to date\n'
      return 0
    fi
  fi

  need_cmd npx "install Node.js >= 18 (nvm) and retry"

  npx --yes skills add "$DELEGATE_REPO" -g -y || die "skills install failed"
  npx --yes skills add "$FIND_SKILLS" -g -y || die "skills install failed"

  local count=0
  if [[ -d "$HOME/.agents/skills" ]]; then
    count=$(find "$HOME/.agents/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  fi
  printf '%d skills present\n' "$count"
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

  if [[ "$CONFIG_ONLY" != true ]]; then
    install_binaries
  fi

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
    install_skills
    deploy_headroom
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
  install_skills
  deploy_headroom

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

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# check <description> <command...>: run one read-only probe, print PASS or FAIL,
# and keep the doctor counters. A failing probe's output becomes the detail.
check() {
  local desc=$1 output line
  shift
  if output=$("$@" 2>&1); then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'PASS %s\n' "$desc"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'FAIL %s\n' "$desc"
  fi
  if [[ -n "$output" ]]; then
    while IFS= read -r line; do
      printf '  %s\n' "$line"
    done <<< "$output"
  fi
}

# doctor_commands: every tool the config depends on is on PATH, prints each
# tool's version, and enforces the runtime minimums (Node >= 18, OpenCode V2).
doctor_commands() {
  local cmd version major
  local missing=()
  for cmd in git node opencode uv rtk headroom graphify; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
      continue
    fi
    version=$("$cmd" --version 2>/dev/null | head -n 1) || true
    printf '%s: %s\n' "$cmd" "${version:-unknown}"
  done
  if (( ${#missing[@]} > 0 )); then
    printf 'missing: %s\n' "${missing[*]}"
    return 1
  fi

  version=$(node --version 2>/dev/null) || version=""
  version=${version#v}
  major=${version%%.*}
  if [[ ! "$major" =~ ^[0-9]+$ ]] || (( 10#$major < 18 )); then
    printf 'Node.js >= 18 required (found %s)\n' "${version:-unknown}"
    return 1
  fi

  version=$(opencode --version 2>/dev/null) || version=""
  version=${version#v}
  major=${version%%.*}
  if [[ ! "$major" =~ ^[0-9]+$ ]] || (( 10#$major < 2 )); then
    printf 'OpenCode >= 2 required (found %s)\n' "${version:-unknown}"
    return 1
  fi
}

doctor_config_files() {
  local file
  local missing=()
  for file in "$CFG/opencode.jsonc" "$CFG/cli.json" "$CFG/AGENTS.md"; do
    [[ -f "$file" ]] || missing+=("$file")
  done
  if (( ${#missing[@]} > 0 )); then
    printf 'missing: %s\n' "${missing[*]}"
    return 1
  fi
}

# doctor_config_jsonc: opencode.jsonc is plain JSON (comments are not used), so
# a strict parse is enough; then assert the V2 sections the setup provides.
doctor_config_jsonc() {
  node -e '
    const fs = require("fs");
    let cfg;
    try {
      cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    } catch (err) {
      console.error("invalid JSON: " + err.message);
      process.exit(1);
    }
    const get = (obj, path) =>
      path.split(".").reduce((cur, key) => (cur == null ? undefined : cur[key]), obj);
    const missing = ["mcp.servers.headroom", "mcp.servers.serena", "providers.headroom"]
      .filter((path) => !get(cfg, path));
    if (missing.length > 0) {
      console.error("missing: " + missing.join(", "));
      process.exit(1);
    }
  ' "$CFG/opencode.jsonc"
}

doctor_plugin_deps() {
  local dir="$CFG/node_modules/@opencode/plugin"
  if [[ ! -e "$dir" ]]; then
    printf 'missing %s\n' "$dir"
    return 1
  fi
}

doctor_skills() {
  local dir missing=()
  for dir in "$HOME/.agents/skills/opencode-delegate" "$HOME/.agents/skills/delegate-setup"; do
    [[ -f "$dir/SKILL.md" ]] || missing+=("$dir/SKILL.md")
  done
  if (( ${#missing[@]} > 0 )); then
    printf 'missing: %s\n' "${missing[*]}"
    return 1
  fi
}

# doctor_lanes: the delegation fleet config must parse, define at least one
# lane, and name an implementer for each.
doctor_lanes() {
  node -e '
    const fs = require("fs");
    let cfg;
    try {
      cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    } catch (err) {
      console.error("invalid JSON: " + err.message);
      process.exit(1);
    }
    const lanes = cfg.lanes && typeof cfg.lanes === "object" ? cfg.lanes : {};
    const names = Object.keys(lanes);
    if (names.length === 0) {
      console.error("no delegate lanes configured");
      process.exit(1);
    }
    const bad = names.filter((name) => !lanes[name] || !lanes[name].implementer);
    if (bad.length > 0) {
      console.error("lanes without implementer: " + bad.join(", "));
      process.exit(1);
    }
  ' "$HOME/.config/delegate-skills/config.json"
}

doctor_rtk_rewrite() {
  local out status=0
  # rtk exits 3 when no global hook is installed even though the rewrite is
  # correct; the spec check is output-based, so tolerate the exit status.
  out=$(rtk rewrite "git status" 2>/dev/null) || status=$?
  if [[ "$out" != "rtk git status" ]]; then
    printf 'expected "rtk git status", got "%s" (exit %d)\n' "$out" "$status"
    return 1
  fi
}

# doctor_port: read-only listen check; it never dials or starts the proxy.
doctor_port() {
  local out
  out=$(ss -ltn 2>&1) || {
    printf '%s\n' "$out"
    return 1
  }
  if printf '%s\n' "$out" | awk '{print $4}' | grep -Eq '(^|[:.])8787$'; then
    return 0
  fi
  printf 'nothing is listening on port 8787\n'
  return 1
}

doctor_opencode_paths() {
  local out
  out=$(opencode debug paths config 2>&1) || {
    printf '%s\n' "$out"
    return 1
  }
  if [[ "$out" != "$CFG" ]]; then
    printf 'expected %s, got %s\n' "$CFG" "$out"
    return 1
  fi
}

# doctor: read-only verification of an installed setup. It never starts an
# OpenCode service and never calls the OpenCode API.
doctor() {
  PASS_COUNT=0
  FAIL_COUNT=0
  SKIP_COUNT=0

  check "commands" doctor_commands
  check "config files" doctor_config_files
  check "config jsonc" doctor_config_jsonc
  check "plugin deps" doctor_plugin_deps
  check "delegate skills" doctor_skills
  check "delegate lanes" doctor_lanes
  check "rtk rewrite" doctor_rtk_rewrite

  if [[ "$WITH_HEADROOM" == true ]]; then
    if command -v ss >/dev/null 2>&1; then
      check "port 8787" doctor_port
    else
      SKIP_COUNT=$((SKIP_COUNT + 1))
      printf 'SKIP port 8787\n'
    fi
  fi

  check "opencode paths" doctor_opencode_paths

  printf 'doctor: %d passed, %d failed, %d skipped\n' \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
  (( FAIL_COUNT == 0 ))
}

main() {
  parse_args "$@"

  if [[ "$HELP" == true ]]; then
    usage
    return 0
  fi

  # Doctor diagnoses the environment itself, so it must run before the
  # install-only preflight (which exits on a missing/old Node or incomplete
  # checkout) and report those problems as FAIL lines.
  if [[ "$DOCTOR" == true ]]; then
    if ! doctor; then
      exit 1
    fi
    return 0
  fi

  need_cmd bash
  need_cmd curl
  check_node
  check_payload

  install_all
}

main "$@"

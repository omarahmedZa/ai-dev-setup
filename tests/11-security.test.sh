#!/usr/bin/env bash
# shellcheck shell=bash
# Security regressions: secret hygiene, installer blast radius, file modes.
#
# The repository is public, so a failing scan reports the offending file only,
# never the matched text: the suite cannot leak a real credential.

# Tracked .gitignore must list each secret/artifact pattern on its own line; a
# substring match would let `*.env` stand in for the `.env` entry.
test_gitignore_covers_secrets_and_artifacts() {
  check git -C "$ROOT" ls-files --error-unmatch -- .gitignore
  assert_exit 0

  local entry
  for entry in service.json .env node_modules/ backups/ '*.headroom-backup'; do
    check grep -qxF -- "$entry" "$ROOT/.gitignore"
    if (( STATUS != 0 )); then
      _fail "expected .gitignore line '$entry' got no exact match"
    fi
  done
}

# No secret-shaped string anywhere in the shipped payload or installer.
test_no_secret_shaped_strings_in_repo() {
  local pattern='sk-[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY'
  check grep -rEl -- "$pattern" \
    "$ROOT/install.sh" "$ROOT/README.md" \
    "$ROOT/config" "$ROOT/plugins" "$ROOT/skills" "$ROOT/delegate"
  if (( STATUS == 0 )); then
    _fail "expected no secret-shaped strings in the payload, got files: $(printf '%s\n' "$OUT" | tr '\n' ' ')"
  elif (( STATUS != 1 )); then
    _fail "expected a clean secret scan (exit 1), got scan error (exit $STATUS)"
  fi
}

# Secret-shaped strings must not survive anywhere in reachable git history.
# Report only commit/file context so a failure never prints the credential.
test_no_secret_shaped_strings_in_git_history() {
  command -v git >/dev/null 2>&1 || return 0

  local history
  if ! history=$(git -C "$ROOT" log -p --all --format='commit %H' -- \
    . ':(exclude)tests/11-security.test.sh' 2>/dev/null); then
    # An unborn branch has no history to scan; an unavailable repository is
    # likewise not a secret-scanning failure.
    return 0
  fi

  local pattern='sk-[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY'
  local matching_lines
  matching_lines=$(printf '%s\n' "$history" | grep -nE -- "$pattern" | cut -d: -f1 || true)
  [[ -z "$matching_lines" ]] && return 0

  local line commit diff_start diff_context old_file new_file file
  line=${matching_lines%%$'\n'*}
  commit=$(printf '%s\n' "$history" | head -n "$line" | grep '^commit ' | tail -n 1 || true)
  diff_start=$(printf '%s\n' "$history" | head -n "$line" \
    | grep -n '^diff --git ' | tail -n 1 | cut -d: -f1 || true)
  if [[ -n "$diff_start" ]]; then
    diff_context=$(printf '%s\n' "$history" | head -n "$line" | tail -n "+$diff_start")
    old_file=$(printf '%s\n' "$diff_context" | grep '^--- ' | tail -n 1 || true)
    new_file=$(printf '%s\n' "$diff_context" | grep '^+++ ' | tail -n 1 || true)
    if [[ "$new_file" == '+++ /dev/null' ]]; then
      file=$old_file
    else
      file=${new_file:-$old_file}
    fi
    file=${file:-$(printf '%s\n' "$diff_context" | head -n 1)}
  fi
  if [[ -n "$file" ]] && printf '%s\n' "$file" | grep -qE -- "$pattern"; then
    file='[redacted sensitive path]'
  fi
  _fail "expected no secret-shaped strings in git history, got ${commit:-unknown commit} ${file:-unknown file}"
}

# Credentials belong to the auth layer: the installer must never touch or
# mention service.json, not even in a hint or an error message.
test_installer_never_references_service_json() {
  check grep -qF -- 'service.json' "$ROOT/install.sh"
  if (( STATUS == 0 )); then
    _fail "expected no 'service.json' reference in install.sh, got a match"
  elif (( STATUS != 1 )); then
    _fail "expected a clean scan of install.sh (exit 1), got scan error (exit $STATUS)"
  fi
}

# The installer deletes exactly one guarded path and never escalates, widens
# permissions, or evaluates generated code.
test_installer_has_no_destructive_patterns() {
  local pattern
  for pattern in 'rm -rf' 'rm -fr' 'sudo' 'doas' 'chmod 777' 'eval'; do
    check grep -qwF -- "$pattern" "$ROOT/install.sh"
    if (( STATUS == 0 )); then
      _fail "expected no '$pattern' in install.sh, got a match"
    elif (( STATUS != 1 )); then
      _fail "expected a clean scan for '$pattern' (exit 1), got scan error (exit $STATUS)"
    fi
  done

  # `rm` as a command word, not inside words like "removed".
  local rm_count
  rm_count=$(grep -owE 'rm' "$ROOT/install.sh" | grep -c . || true)
  if [[ "$rm_count" != 1 ]]; then
    _fail "expected exactly 1 rm command in install.sh, got $rm_count"
  fi

  # That one rm must be the guarded `rm -- "$path"` form: a flag (`rm -f --`)
  # or an unquoted path fails it.
  check grep -qE '^[[:space:]]*rm -- "\$[a-z_]+"[[:space:]]*$' "$ROOT/install.sh"
  if (( STATUS != 0 )); then
    _fail "expected the only rm to be the guarded 'rm -- \"\$path\"' form, got no match"
  fi

  # The guarded removal must still cover the two named stale files.
  check grep -qE 'remove_stale "\$CFG/opencode\.json"' "$ROOT/install.sh"
  assert_exit 0
  check grep -qE 'remove_stale "\$CFG/opencode\.jsonc\.headroom-backup"' \
    "$ROOT/install.sh"
  assert_exit 0
}

# Network installers run under pipefail so a failed download cannot be masked,
# and each one is verified with `command -v` afterwards.
test_piped_installers_are_pipefail_guarded() {
  local exec_line verify_line installer body line
  check grep -qF -- 'bash -o pipefail -c' "$ROOT/install.sh"
  assert_exit 0

  # Scope the ordering check to ensure_bin, the helper that runs installers:
  # `command -v` also appears in unrelated preflight helpers.
  body=$(awk '/^ensure_bin\(\)/ { inside = 1 } inside { print } inside && /^\}/ { inside = 0 }' \
    "$ROOT/install.sh")
  if [[ -z "$body" ]]; then
    _fail "expected an ensure_bin function that runs installer commands"
    return
  fi

  exec_line=$(printf '%s\n' "$body" | grep -nF -- 'bash -o pipefail -c "$install_cmd"' |
    head -n 1 | cut -d: -f1)
  verify_line=$(printf '%s\n' "$body" | grep -nF -- 'command -v "$cmd"' |
    tail -n 1 | cut -d: -f1)
  if [[ -z "$exec_line" || -z "$verify_line" ]]; then
    _fail "expected a pipefail exec and a command -v check in ensure_bin (exec=$exec_line verify=$verify_line)"
  elif (( verify_line <= exec_line )); then
    _fail "expected the command -v check after the install exec in ensure_bin (exec=$exec_line verify=$verify_line)"
  fi

  # A pipe into sh/bash may only live in a quoted install-command constant; an
  # executable pipe outside the guard would run straight from the network.
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if ! [[ $line =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[\'\"] ]]; then
      _fail "expected piped installers behind 'bash -o pipefail -c', got executable pipe: $line"
    fi
  done < <(grep -E '\|[[:space:]]*(bash|sh)([[:space:]]|$)' "$ROOT/install.sh" || true)

  # Every installer constant must actually be run through the guarded helper.
  for installer in \
    'ensure_bin opencode "\$OPENCODE_INSTALL"' \
    'ensure_bin uv "\$UV_INSTALL"' \
    'ensure_bin rtk "\$RTK_INSTALL"' \
    'ensure_bin headroom "\$HEADROOM_INSTALL"' \
    'ensure_bin graphify "\$GRAPHIFY_INSTALL"'; do
    check grep -qE -- "$installer" "$ROOT/install.sh"
    if (( STATUS != 0 )); then
      _fail "expected installer routed through ensure_bin: $installer"
    fi
  done
}

# assert_no_group_or_world_writable <dir>...: every directory must exist and
# nothing under it may carry the group- or world-write bit.
assert_no_group_or_world_writable() {
  local dir found
  for dir in "$@"; do
    check test -d "$dir"
    assert_exit 0
    found=$(find "$dir" -perm /0022 -print 2>/dev/null || true)
    if [[ -n "$found" ]]; then
      _fail "expected no group- or world-writable paths under $dir, got: $(printf '%s\n' "$found" | head -n 5 | tr '\n' ' ')"
    fi
  done
}

# Installed config trees must not be group- or world-writable: any other local
# user in the group (or on the machine) could rewrite the agent config, plugins,
# or delegation lanes. The mode must not come from the caller's umask either, so
# the install is repeated under umask 000.
test_installed_tree_has_no_group_or_world_writable_paths() {
  new_sandbox
  run_install --config-only --force
  assert_exit 0
  assert_no_group_or_world_writable "$HOME/.config/opencode" "$HOME/.config/delegate-skills"

  local previous_umask
  previous_umask=$(umask)
  new_sandbox
  umask 000
  run_install --config-only --force
  umask "$previous_umask"
  assert_exit 0
  assert_no_group_or_world_writable "$HOME/.config/opencode" "$HOME/.config/delegate-skills"
}

# Existing permissive trees must be tightened too, not only newly created ones.
test_preexisting_writable_modes_are_tightened() {
  new_sandbox
  mkdir -p "$HOME/.config/opencode/nested" "$HOME/.config/delegate-skills"
  chmod 777 "$HOME/.config/opencode" "$HOME/.config/opencode/nested" \
    "$HOME/.config/delegate-skills"
  printf 'custom\n' > "$HOME/.config/opencode/nested/local.txt"
  printf 'safe\n' > "$HOME/.config/opencode/nested/safe.txt"
  chmod 666 "$HOME/.config/opencode/nested/local.txt"
  chmod 600 "$HOME/.config/opencode/nested/safe.txt"

  run_install --config-only --force
  assert_exit 0
  assert_no_group_or_world_writable "$HOME/.config/opencode" "$HOME/.config/delegate-skills"
  check find "$HOME/.config/opencode" "$HOME/.config/delegate-skills" -perm /0022 -print -quit
  assert_eq "" "$OUT"
  assert_eq "600" "$(stat -c '%a' "$HOME/.config/opencode/nested/safe.txt")"
}

# A group-only writable directory must be reported by the doctor and tightened
# by the installer. `chmod go-w` turns 0770 into 0750.
test_group_writable_directory_is_tightened_and_fails_doctor() {
  new_sandbox
  run_install --config-only --force
  assert_exit 0
  mkdir -p "$HOME/.config/opencode/nested"
  chmod 770 "$HOME/.config/opencode/nested"

  run_install --doctor
  assert_exit 1
  assert_contains "$OUT" "FAIL permissions"
  assert_contains "$OUT" "group- or world-writable paths:"

  run_install --config-only --force
  assert_exit 0
  assert_eq "750" "$(stat -c '%a' "$HOME/.config/opencode/nested")"
  check find "$HOME/.config/opencode" "$HOME/.config/delegate-skills" -perm /0022 -print -quit
  assert_eq "" "$OUT"
}

# Symlink mode bits are always 0777 on Linux and are not permission findings.
test_symlinks_are_excluded_from_permission_checks() {
  new_sandbox
  run_install --config-only --force
  assert_exit 0
  mkdir -p "$HOME/.config/opencode/node_modules/.bin"
  # The suite's umask may create these group-writable; pin them so this test
  # isolates symlink handling rather than directory permissions.
  chmod 755 "$HOME/.config/opencode/node_modules" \
    "$HOME/.config/opencode/node_modules/.bin"
  ln -s ../../opencode.jsonc "$HOME/.config/opencode/node_modules/.bin/tool"
  run_install --doctor
  assert_exit 0
  assert_contains "$OUT" "PASS permissions"
  check test -L "$HOME/.config/opencode/node_modules/.bin/tool"
  assert_exit 0

  new_sandbox
  mkdir -p "$HOME/.config/opencode/node_modules/.bin"
  ln -s ../../opencode.jsonc "$HOME/.config/opencode/node_modules/.bin/tool"
  run_install --config-only --force
  assert_exit 0
  run_install --doctor
  assert_exit 0
  assert_contains "$OUT" "PASS permissions"
  check test -L "$HOME/.config/opencode/node_modules/.bin/tool"
  assert_exit 0
}

# Ignored artifact paths must never make it into the index in the first place.
test_tracked_files_exclude_secret_artifacts() {
  check git -C "$ROOT" ls-files
  assert_exit 0
  if [[ -z "$OUT" ]]; then
    _fail "expected tracked files, got an empty list"
    return
  fi

  local hits
  hits=$(printf '%s\n' "$OUT" \
    | grep -E '(^|/)(node_modules|backups)/|(^|/)(service\.json|\.env)$|\.headroom-backup$' \
    || true)
  if [[ -n "$hits" ]]; then
    _fail "expected no secret/artifact paths tracked, got: $(printf '%s\n' "$hits" | tr '\n' ' ')"
  fi
}

# Tracked files must stay machine-independent: no baked-in absolute home paths.
# docs/ is excluded (it records real session artifacts), and any line carrying
# the scan pattern's own source is dropped so a test cannot match itself.
test_no_absolute_home_paths_in_tracked_files() {
  local pattern='/(home|Users|root)/[A-Za-z0-9._-]+'
  check git -C "$ROOT" ls-files
  assert_exit 0

  local matches
  matches=$(cd "$ROOT" && printf '%s\n' "$OUT" | grep -v '^docs/' | tr '\n' '\0' \
    | xargs -0 -r grep -IHnE -- "$pattern" 2>/dev/null || true)
  matches=$(printf '%s\n' "$matches" | grep -vF -- '(home|Users|root)' || true)
  if [[ -n "$matches" ]]; then
    _fail "expected no absolute home paths in tracked files, got files: $(printf '%s\n' "$matches" | cut -d: -f1 | sort -u | tr '\n' ' ')"
  fi
}

#!/usr/bin/env bash
# shellcheck shell=bash
# Local plugin dependencies and lockfile stamping (Task 6).

test_npm_runs_when_plugin_missing() {
  new_sandbox; run_install --config-only --force
  assert_exit 0
  assert_contains "$(cat "$TEST_LOG")" "npm install --omit=dev"
  assert_file_exists "$HOME/.config/opencode/node_modules/@opencode/plugin"
  assert_file_exists "$HOME/.config/opencode/.lockhash"
}
test_npm_is_not_rerun_when_lock_matches() {
  new_sandbox
  run_install --config-only --force
  run_install --config-only
  assert_eq 1 "$(grep -c 'npm install --omit=dev' "$TEST_LOG")"
}
test_npm_reruns_when_lockhash_differs() {
  new_sandbox
  run_install --config-only --force
  echo stale > "$HOME/.config/opencode/.lockhash"
  run_install --config-only --force
  assert_eq 2 "$(grep -c 'npm install --omit=dev' "$TEST_LOG")"
}
# npm may normalize the installed lock (the root name is derived from the
# directory). The installer must restore the repository copy so the next plain
# run sees no drift and does not abort.
test_npm_lock_rewrite_does_not_cause_drift() {
  new_sandbox
  mkdir -p "$SANDBOX/bin"
  cat > "$SANDBOX/bin/npm" <<'EOF'
#!/bin/sh
set -eu
printf 'npm %s\n' "$*" >> "${TEST_LOG:-/dev/null}"
case "${1:-}" in
  install)
    mkdir -p node_modules/@opencode/plugin
    printf '{"name":"clobbered","lockfileVersion":3}\n' > package-lock.json
    ;;
esac
exit 0
EOF
  chmod +x "$SANDBOX/bin/npm"

  PATH="$SANDBOX/bin:$PATH" run_install --config-only --force
  assert_exit 0
  assert_file_eq "$ROOT/config/package-lock.json" "$HOME/.config/opencode/package-lock.json"

  run_install --config-only
  assert_exit 0
  assert_contains "$OUT" "up to date"
  assert_file_eq "$ROOT/config/package-lock.json" "$HOME/.config/opencode/package-lock.json"
}

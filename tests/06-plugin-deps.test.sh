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

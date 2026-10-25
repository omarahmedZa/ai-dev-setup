#!/usr/bin/env bash
# shellcheck shell=bash
# External tools: detection, installation and opt-in headroom deploy (Task 8).

test_present_binaries_are_not_reinstalled() {
  new_sandbox; run_install --dry-run
  assert_exit 0
  assert_contains "$OUT" "found opencode"
  assert_contains "$OUT" "found rtk"
  assert_contains "$OUT" "found headroom"
  assert_contains "$OUT" "found graphify"
  assert_not_contains "$OUT" "curl -fsSL https://opencode.ai"
}

test_missing_binary_is_reported_with_command() {
  new_sandbox; sandbox_without rtk
  run_install --dry-run
  assert_exit 0
  assert_contains "$OUT" "missing rtk"
  assert_contains "$OUT" "raw.githubusercontent.com/rtk-ai/rtk"
}

test_config_only_skips_binary_installation() {
  new_sandbox; run_install --config-only --force
  assert_not_contains "$OUT" "missing opencode"
  assert_file_not_contains "$TEST_LOG" "uv tool install"
}

test_headroom_deploy_runs_then_config_is_reasserted() {
  new_sandbox; run_install --config-only --force --with-headroom
  assert_exit 0
  assert_file_contains "$TEST_LOG" "deploy --target opencode --port 8787"
  assert_file_eq "$ROOT/config/opencode.jsonc" "$HOME/.config/opencode/opencode.jsonc"
}

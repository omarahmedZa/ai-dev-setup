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

  # A real run must not invoke any installer when every tool is present.
  new_sandbox; run_install --force
  assert_exit 0
  assert_file_not_contains "$TEST_LOG" "uv tool install"
  assert_not_contains "$OUT" "missing "
  assert_not_contains "$OUT" "curl -fsSL"
}

test_missing_binary_is_reported_with_command() {
  new_sandbox; sandbox_without rtk
  run_install --dry-run
  assert_exit 0
  assert_contains "$OUT" "missing rtk"
  assert_contains "$OUT" "raw.githubusercontent.com/rtk-ai/rtk"
}

test_failed_installer_exits_nonzero() {
  new_sandbox; sandbox_without rtk
  printf '#!/bin/sh\nexit 7\n' > "$SANDBOX/stubs/curl"
  chmod +x "$SANDBOX/stubs/curl"
  run_install --force
  assert_exit 1
  assert_contains "$OUT" "missing rtk"
  assert_contains "$OUT" "failed to install rtk"
}

test_installer_without_binary_is_an_error() {
  new_sandbox; sandbox_without rtk
  printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/stubs/curl"
  chmod +x "$SANDBOX/stubs/curl"
  run_install --force
  assert_exit 1
  assert_contains "$OUT" "installer for rtk did not produce a working rtk"
}

test_config_only_skips_binary_installation() {
  new_sandbox; sandbox_without rtk
  run_install --config-only --force
  assert_not_contains "$OUT" "missing rtk"
  assert_not_contains "$OUT" "found opencode"
  assert_file_not_contains "$TEST_LOG" "uv tool install"
}

test_headroom_deploy_runs_then_config_is_reasserted() {
  new_sandbox; run_install --config-only --force --with-headroom
  assert_exit 0
  assert_file_contains "$TEST_LOG" "deploy --target opencode --port 8787"
  assert_file_eq "$ROOT/config/opencode.jsonc" "$HOME/.config/opencode/opencode.jsonc"
}

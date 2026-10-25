#!/usr/bin/env bash
# shellcheck shell=bash
# Doctor checks: read-only verification of an installed setup (Task 9).

test_doctor_passes_after_install() {
  new_sandbox
  run_install --config-only --force
  run_install --doctor
  assert_exit 0
  assert_not_contains "$OUT" "FAIL"
  assert_contains "$OUT" "PASS"
}
test_doctor_fails_on_broken_lane_config() {
  new_sandbox
  run_install --config-only --force
  echo '{"lanes":{"bad":{}}}' > "$HOME/.config/delegate-skills/config.json"
  run_install --doctor
  assert_exit 1
  assert_contains "$OUT" "FAIL delegate lanes"
}
test_doctor_fails_when_rtk_rewrite_is_wrong() {
  new_sandbox
  run_install --config-only --force
  printf '#!/bin/sh\nprintf "%%s\\n" "$*"\n' > "$SANDBOX/stubs/rtk"
  chmod +x "$SANDBOX/stubs/rtk"
  run_install --doctor
  assert_exit 1
  assert_contains "$OUT" "FAIL rtk rewrite"
}
test_doctor_never_calls_the_opencode_api() {
  new_sandbox
  run_install --config-only --force
  : > "$TEST_LOG"
  run_install --doctor
  assert_file_not_contains "$TEST_LOG" "api get"
}
test_doctor_reports_old_node_instead_of_dying() {
  new_sandbox
  run_install --config-only --force
  mkdir -p "$SANDBOX/oldnode"
  printf '#!/bin/sh\nif [ "${1:-}" = "-v" ]; then echo v16.0.0; fi\nexit 0\n' \
    > "$SANDBOX/oldnode/node"
  chmod +x "$SANDBOX/oldnode/node"
  PATH="$SANDBOX/oldnode:$PATH" run_install --doctor
  assert_exit 1
  assert_contains "$OUT" "FAIL commands"
  assert_contains "$OUT" "Node.js >= 18 required"
  assert_contains "$OUT" "doctor: "
}

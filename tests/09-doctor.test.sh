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
  for label in "PASS commands" "PASS config files" "PASS config jsonc" \
               "PASS plugin deps" "PASS permissions" "PASS delegate skills" \
               "PASS delegate lanes" "PASS rtk rewrite" "PASS opencode paths"; do
    assert_contains "$OUT" "$label"
  done
  assert_contains "$OUT" "doctor: 9 passed, 0 failed, 0 skipped"
}

test_doctor_fails_on_world_writable_config() {
  new_sandbox
  run_install --config-only --force
  chmod 777 "$HOME/.config/opencode"
  run_install --doctor
  assert_exit 1
  assert_contains "$OUT" "FAIL permissions"
  assert_contains "$OUT" "doctor: 8 passed, 1 failed, 0 skipped"
}
test_doctor_fails_on_group_writable_config() {
  new_sandbox
  run_install --config-only --force
  chmod 770 "$HOME/.config/opencode"
  run_install --doctor
  assert_exit 1
  assert_contains "$OUT" "FAIL permissions"
  assert_contains "$OUT" "doctor: 8 passed, 1 failed, 0 skipped"
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
  printf '#!/bin/sh\nif [ "${1:-}" = "-v" ] || [ "${1:-}" = "--version" ]; then echo v16.0.0; fi\nexit 0\n' \
    > "$SANDBOX/oldnode/node"
  chmod +x "$SANDBOX/oldnode/node"
  PATH="$SANDBOX/oldnode:$PATH" run_install --doctor
  assert_exit 1
  assert_contains "$OUT" "FAIL commands"
  assert_contains "$OUT" "Node.js >= 18 required"
  assert_contains "$OUT" "doctor: "
}

# Spec check 7 is output-based: rtk exits 3 when no global hook is installed,
# but a correct rewrite must still pass.
test_doctor_accepts_rtk_rewrite_that_exits_3() {
  new_sandbox
  run_install --config-only --force
  cat > "$SANDBOX/stubs/rtk" <<'EOF'
#!/bin/sh
case "${1:-}" in
  --version) printf '0.43.0\n'; exit 0 ;;
  rewrite) printf 'rtk git status\n'; exit 3 ;;
esac
exit 0
EOF
  chmod +x "$SANDBOX/stubs/rtk"
  run_install --doctor
  assert_exit 0
  assert_contains "$OUT" "PASS rtk rewrite"
}

# The spec only requires that every configured lane has an implementer; the
# doctor must not hardcode the seven lanes of this machine.
test_doctor_accepts_any_non_empty_lane_set() {
  new_sandbox
  run_install --config-only --force
  echo '{"lanes":{"solo":{"implementer":"opencode"}}}' \
    > "$HOME/.config/delegate-skills/config.json"
  run_install --doctor
  assert_exit 0
  assert_contains "$OUT" "PASS delegate lanes"
}

test_doctor_rejects_opencode_v1() {
  new_sandbox
  run_install --config-only --force
  cat > "$SANDBOX/stubs/opencode" <<'EOF'
#!/bin/sh
case "${1:-}" in
  --version) printf 'opencode v1.18.3\n' ;;
  debug) printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/opencode" ;;
esac
exit 0
EOF
  chmod +x "$SANDBOX/stubs/opencode"
  run_install --doctor
  assert_exit 1
  assert_contains "$OUT" "FAIL commands"
  assert_contains "$OUT" "OpenCode >= 2 required"
  assert_contains "$OUT" "v1.18.3"
}

# The real CLI prints "opencode v2.0.22"; the version parser must accept it.
test_doctor_accepts_real_v2_version_shape() {
  new_sandbox
  run_install --config-only --force
  cat > "$SANDBOX/stubs/opencode" <<'EOF'
#!/bin/sh
case "${1:-}" in
  --version) printf 'opencode v2.0.22\n' ;;
  debug) printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/opencode" ;;
esac
exit 0
EOF
  chmod +x "$SANDBOX/stubs/opencode"
  run_install --doctor
  assert_exit 0
  assert_contains "$OUT" "PASS commands"
}

test_doctor_fails_on_missing_config_file() {
  new_sandbox
  run_install --config-only --force
  rm -- "$HOME/.config/opencode/cli.json"
  run_install --doctor
  assert_exit 1
  assert_contains "$OUT" "FAIL config files"
}

test_doctor_fails_on_missing_plugin_directory() {
  new_sandbox
  run_install --config-only --force
  mv "$HOME/.config/opencode/node_modules/@opencode/plugin" \
     "$SANDBOX/plugin-moved"
  run_install --doctor
  assert_exit 1
  assert_contains "$OUT" "FAIL plugin deps"
}

test_doctor_fails_on_missing_skills() {
  new_sandbox
  run_install --config-only --force
  mv "$HOME/.agents/skills/delegate-setup/SKILL.md" "$SANDBOX/SKILL.md.moved"
  run_install --doctor
  assert_exit 1
  assert_contains "$OUT" "FAIL delegate skills"
}

#!/usr/bin/env bash
# shellcheck shell=bash
# Delegation skills installed through the upstream skills CLI (Task 7).

test_delegate_skills_install_from_upstream() {
  new_sandbox; run_install --config-only --force
  assert_exit 0
  assert_file_contains "$TEST_LOG" "skills add amElnagdy/delegate-skills -g -y"
  assert_file_exists "$HOME/.agents/skills/opencode-delegate/SKILL.md"
  assert_file_exists "$HOME/.agents/skills/delegate-setup/SKILL.md"
}

test_find_skills_installs() {
  new_sandbox; run_install --config-only --force
  assert_file_contains "$TEST_LOG" "vercel-labs/skills@find-skills"
  assert_file_exists "$HOME/.agents/skills/find-skills/SKILL.md"
}

test_skills_failure_is_reported() {
  new_sandbox
  printf '#!/bin/sh\nexit 1\n' > "$SANDBOX/failnpx"
  chmod +x "$SANDBOX/failnpx"
  mkdir -p "$SANDBOX/bin"; ln -s "$SANDBOX/failnpx" "$SANDBOX/bin/npx"
  PATH="$SANDBOX/bin:$PATH" run_install --config-only --force
  assert_exit 1
  assert_contains "$OUT" "skills install failed"
}

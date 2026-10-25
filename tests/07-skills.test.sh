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

# A fully provisioned rerun must not touch the network: all expected skill
# trees exist and --force was not passed.
test_skills_are_skipped_on_a_provisioned_rerun() {
  new_sandbox
  run_install --config-only --force
  assert_exit 0

  mkdir -p "$SANDBOX/bin"
  printf '#!/bin/sh\nexit 1\n' > "$SANDBOX/bin/npx"
  chmod +x "$SANDBOX/bin/npx"

  PATH="$SANDBOX/bin:$PATH" run_install --config-only
  assert_exit 0
  assert_contains "$OUT" "skills up to date"
}

# A dry run on a provisioned machine must report the same skip as a real run.
test_dry_run_reports_skills_up_to_date_when_provisioned() {
  new_sandbox
  run_install --config-only --force
  assert_exit 0

  run_install --config-only --dry-run
  assert_exit 0
  assert_contains "$OUT" "skills up to date"
  assert_not_contains "$OUT" "would run: npx"
}

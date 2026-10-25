# shellcheck shell=bash
# Drift protection and --force (Task 5).

test_drift_without_force_aborts_before_writing() {
  new_sandbox
  mkdir -p "$HOME/.config/opencode"
  echo '{"theme":"custom"}' > "$HOME/.config/opencode/cli.json"
  run_install --config-only
  assert_exit 1
  assert_contains "$OUT" "cli.json"
  assert_eq '{"theme":"custom"}' "$(cat "$HOME/.config/opencode/cli.json")"
  check test -n "$(find "$HOME/.config/opencode/backups" -name cli.json -print -quit)"
  assert_exit 0
}
test_force_overwrites_and_preserves_backup() {
  new_sandbox
  mkdir -p "$HOME/.config/opencode"
  echo '{"theme":"custom"}' > "$HOME/.config/opencode/cli.json"
  run_install --config-only --force
  assert_exit 0
  assert_file_eq "$ROOT/config/cli.json" "$HOME/.config/opencode/cli.json"
  assert_eq '{"theme":"custom"}' "$(find "$HOME/.config/opencode/backups" -name cli.json -exec cat {} \;)"
}
test_dry_run_reports_drift_without_touching_files() {
  new_sandbox
  mkdir -p "$HOME/.config/opencode"
  echo '{"theme":"custom"}' > "$HOME/.config/opencode/cli.json"
  run_install --config-only --dry-run
  assert_exit 0
  assert_contains "$OUT" "would overwrite"
  assert_eq '{"theme":"custom"}' "$(cat "$HOME/.config/opencode/cli.json")"
}
test_drift_abort_creates_no_missing_destinations() {
  new_sandbox
  mkdir -p "$HOME/.config/opencode"
  echo '{"theme":"custom"}' > "$HOME/.config/opencode/cli.json"
  run_install --config-only
  assert_exit 1
  assert_file_missing "$HOME/.config/opencode/AGENTS.md"
  assert_file_missing "$HOME/.config/opencode/opencode.jsonc"
  assert_file_missing "$HOME/.config/delegate-skills/config.json"
}
test_drift_abort_leaves_stale_files_untouched() {
  new_sandbox
  mkdir -p "$HOME/.config/opencode"
  echo '{"theme":"custom"}' > "$HOME/.config/opencode/cli.json"
  echo '{"stale":true}' > "$HOME/.config/opencode/opencode.json"
  run_install --config-only
  assert_exit 1
  assert_file_exists "$HOME/.config/opencode/opencode.json"
  assert_eq '{"stale":true}' "$(cat "$HOME/.config/opencode/opencode.json")"
}
test_dry_run_writes_nothing_and_takes_no_backup() {
  new_sandbox
  mkdir -p "$HOME/.config/opencode"
  echo '{"theme":"custom"}' > "$HOME/.config/opencode/cli.json"
  run_install --config-only --dry-run
  assert_exit 0
  assert_contains "$OUT" "would create"
  assert_file_missing "$HOME/.config/opencode/AGENTS.md"
  assert_file_missing "$HOME/.config/opencode/backups"
}
test_fresh_install_without_force_creates_files() {
  new_sandbox
  run_install --config-only
  assert_exit 0
  assert_file_exists "$HOME/.config/opencode/cli.json"
  assert_file_exists "$HOME/.config/delegate-skills/config.json"
}

# shellcheck shell=bash

test_config_only_installs_every_payload_file() {
  new_sandbox; run_install --config-only --force
  assert_exit 0
  for p in opencode.jsonc cli.json AGENTS.md plugins/rtk.ts plugins/graphify.js \
           skills/graphify/SKILL.md skills/orchestrating-spec-pipelines/SKILL.md \
           commands/delegate.md; do
    assert_file_exists "$HOME/.config/opencode/$p"
  done
  assert_file_exists "$HOME/.config/delegate-skills/config.json"
}
test_stale_config_files_are_removed_and_backed_up() {
  new_sandbox
  mkdir -p "$HOME/.config/opencode"
  echo '{"stale":true}' > "$HOME/.config/opencode/opencode.json"
  echo '{"old":true}'   > "$HOME/.config/opencode/opencode.jsonc.headroom-backup"
  run_install --config-only --force
  assert_exit 0
  assert_file_missing "$HOME/.config/opencode/opencode.json"
  assert_file_missing "$HOME/.config/opencode/opencode.jsonc.headroom-backup"
  check test -n "$(find "$HOME/.config/opencode/backups" -name 'opencode.json*' -print -quit 2>/dev/null)"
  assert_exit 0
}
test_second_run_is_idempotent() {
  new_sandbox
  run_install --config-only --force; assert_exit 0
  run_install --config-only; assert_exit 0
  assert_contains "$OUT" "up to date"
}
test_service_json_is_never_touched_or_printed() {
  new_sandbox
  mkdir -p "$HOME/.config/opencode"
  echo '{"password":"TOPSECRET"}' > "$HOME/.config/opencode/service.json"
  run_install --config-only --force
  assert_exit 0
  assert_file_exists "$HOME/.config/opencode/service.json"
  assert_file_contains "$HOME/.config/opencode/service.json" "TOPSECRET"
  assert_not_contains "$OUT" "TOPSECRET"
  check test -z "$(find "$HOME/.config/opencode/backups" -name service.json -print -quit 2>/dev/null)"
  assert_exit 0
}
test_next_steps_are_printed() {
  new_sandbox; run_install --config-only --force
  assert_exit 0
  assert_contains "$OUT" "opencode auth login"
}

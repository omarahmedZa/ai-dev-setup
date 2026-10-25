# shellcheck shell=bash

test_help_lists_every_flag() {
  new_sandbox; run_install --help
  assert_exit 0
  for f in --dry-run --force --config-only --with-headroom --doctor; do
    assert_contains "$OUT" "$f"
  done
}
test_unknown_flag_exits_2() {
  new_sandbox; run_install --bogus
  assert_exit 2
  assert_contains "$OUT" "unknown option"
}
test_missing_node_fails_with_nvm_hint() {
  new_sandbox
  mkdir -p "$SANDBOX/oldnode"
  printf '#!/bin/sh\necho v16.0.0\n' > "$SANDBOX/oldnode/node"
  chmod +x "$SANDBOX/oldnode/node"
  PATH="$SANDBOX/oldnode:$PATH" run_install --dry-run
  assert_exit 1
  assert_contains "$OUT" "nvm"
}
test_dry_run_writes_nothing() {
  new_sandbox; run_install --dry-run
  assert_exit 0
  assert_file_missing "$HOME/.config/opencode"
}
test_incomplete_checkout_fails_preflight() {
  new_sandbox
  mkdir -p "$SANDBOX/clone"
  cp "$ROOT/install.sh" "$SANDBOX/clone/"
  check bash "$SANDBOX/clone/install.sh" --dry-run
  assert_exit 1
  assert_contains "$OUT" "not a complete checkout"
}

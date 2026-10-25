#!/usr/bin/env bash
# Shared helpers for the ai-dev-setup test suite.

if [[ -z "${ROOT:-}" ]]; then
  lib_dir=${BASH_SOURCE[0]%/*}
  [[ "$lib_dir" == "${BASH_SOURCE[0]}" ]] && lib_dir=.
  ROOT=$(cd "$lib_dir/.." && pwd)
fi
export ROOT

# Stubs must be authoritative: drop the real user's private bin dirs from the
# base PATH so sandbox_without actually hides a tool, but keep the real node.
TEST_REAL_HOME=${HOME:-}
TEST_NODE_DIR=""
node_path=$(command -v node 2>/dev/null || true)
if [[ -n "$node_path" ]]; then
  TEST_NODE_DIR=${node_path%/*}
fi

TEST_BASE_PATH=""
IFS=: read -r -a path_dirs <<< "$PATH"
for dir in "${path_dirs[@]}"; do
  [[ -n "$dir" ]] || continue
  if [[ -n "$TEST_REAL_HOME" && "$dir" == "$TEST_REAL_HOME"/* && "$dir" != "$TEST_NODE_DIR" ]]; then
    continue
  fi
  TEST_BASE_PATH="${TEST_BASE_PATH:+$TEST_BASE_PATH:}$dir"
done
if [[ -n "$TEST_NODE_DIR" && ":$TEST_BASE_PATH:" != *":$TEST_NODE_DIR:"* ]]; then
  TEST_BASE_PATH="$TEST_NODE_DIR:$TEST_BASE_PATH"
fi

OUT=""
STATUS=0
TEST_FAILED=0
TEST_NUMBER=0
TEST_FAILURES=0

_fail() {
  printf '%s\n' "$1"
  TEST_FAILED=1
}

new_sandbox() {
  local base="${TMPDIR:-/tmp}/ai-dev-setup-tests"
  if ! mkdir -p "$base"; then
    printf 'error: cannot create test base directory: %s\n' "$base" >&2
    exit 1
  fi
  if ! SANDBOX=$(mktemp -d "$base/sandbox.XXXXXX"); then
    printf 'error: cannot create test sandbox under %s\n' "$base" >&2
    exit 1
  fi
  if [[ -z "$SANDBOX" ]]; then
    printf 'error: mktemp returned an empty sandbox path\n' >&2
    exit 1
  fi
  export SANDBOX

  export HOME="$SANDBOX/home"
  if ! mkdir -p "$HOME"; then
    printf 'error: cannot create fake HOME: %s\n' "$HOME" >&2
    exit 1
  fi
  unset XDG_CONFIG_HOME

  export TEST_LOG="$SANDBOX/test.log"
  if ! : > "$TEST_LOG"; then
    printf 'error: cannot create test log: %s\n' "$TEST_LOG" >&2
    exit 1
  fi

  if ! cp -R "$ROOT/tests/stubs" "$SANDBOX/stubs"; then
    printf 'error: cannot copy command stubs into sandbox: %s\n' "$SANDBOX/stubs" >&2
    exit 1
  fi
  export PATH="$SANDBOX/stubs:$TEST_BASE_PATH"
}

sandbox_without() {
  rm -f "$SANDBOX/stubs/$1"
}

check() {
  local status=0
  OUT=$("$@" 2>&1) || status=$?
  STATUS=$status
}

run_install() {
  local status=0
  OUT=$(cd "$ROOT" && ./install.sh "$@" 2>&1) || status=$?
  STATUS=$status
}

assert_eq() {
  if [[ "$1" != "$2" ]]; then
    _fail "expected '$1' got '$2'"
  fi
}

assert_exit() {
  if [[ "$STATUS" != "$1" ]]; then
    _fail "expected exit $1 got $STATUS"
  fi
}

assert_file_exists() {
  if [[ ! -e "$1" ]]; then
    _fail "expected file $1 got missing"
  fi
}

assert_file_missing() {
  if [[ -e "$1" ]]; then
    _fail "expected missing $1 got present"
  fi
}

assert_file_eq() {
  if ! cmp -s "$1" "$2"; then
    _fail "expected matching files $1 got different contents in $2"
  fi
}

assert_contains() {
  if [[ "$1" != *"$2"* ]]; then
    _fail "expected '$2' got '$1'"
  fi
}

assert_not_contains() {
  if [[ "$1" == *"$2"* ]]; then
    _fail "expected no '$2' got '$1'"
  fi
}

assert_file_contains() {
  if ! grep -qF -- "$2" "$1" 2>/dev/null; then
    _fail "expected '$2' in file $1 got no match"
  fi
}

assert_file_not_contains() {
  if grep -qF -- "$2" "$1" 2>/dev/null; then
    _fail "expected no '$2' in file $1 got match"
  fi
}

run_test() {
  local name="$1"
  TEST_NUMBER=$((TEST_NUMBER + 1))
  TEST_FAILED=0
  "$name"
  if (( TEST_FAILED == 0 )); then
    printf 'ok %d - %s\n' "$TEST_NUMBER" "$name"
  else
    printf 'not ok %d - %s\n' "$TEST_NUMBER" "$name"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
}

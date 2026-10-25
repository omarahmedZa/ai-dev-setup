#!/usr/bin/env bash
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT

# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"

if [[ -f "$ROOT/install.sh" ]]; then
  TEST_NUMBER=$((TEST_NUMBER + 1))
  if OUT=$(bash -n "$ROOT/install.sh" 2>&1); then
    printf 'ok %d - %s\n' "$TEST_NUMBER" "bash -n install.sh"
  else
    printf 'not ok %d - %s\n' "$TEST_NUMBER" "bash -n install.sh"
    printf '%s\n' "$OUT"
    TEST_FAILURES=$((TEST_FAILURES + 1))
  fi
fi

shopt -s nullglob
test_files=("$ROOT"/tests/*.test.sh)
shopt -u nullglob

if (( ${#test_files[@]} == 0 )); then
  printf 'no tests/*.test.sh files found\n' >&2
  exit 1
fi

for test_file in "${test_files[@]}"; do
  # shellcheck source=/dev/null
  if ! . "$test_file"; then
    printf 'not ok - could not source %s\n' "$test_file" >&2
    exit 1
  fi
done

while read -r _ _ test_name; do
  [[ $test_name == test_* ]] || continue
  run_test "$test_name"
done < <(declare -F)

if (( TEST_FAILURES > 0 )); then
  printf '%d of %d tests failed\n' "$TEST_FAILURES" "$TEST_NUMBER" >&2
  exit 1
fi

exit 0

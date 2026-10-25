#!/usr/bin/env bash
# shellcheck shell=bash
# README documents every flag and every manual step (Task 10).

test_readme_documents_usage_and_manual_steps() {
  for s in --dry-run --force --config-only --with-headroom --doctor \
           "opencode auth login" "service.json" "npx skills add" "graphify install"; do
    assert_contains "$(cat "$ROOT/README.md")" "$s"
  done
}

# The repo is private, so the quick start must establish GitHub credentials
# before it shows a clone command; an unauthenticated clone dead-ends.
test_readme_quick_start_authenticates_before_clone() {
  local readme quick auth_line clone_line
  readme=$(cat "$ROOT/README.md")
  assert_contains "$readme" "gh auth login"

  quick=$(awk '/^## Quick start$/{found=1;next} found && /^## /{exit} found' \
    "$ROOT/README.md")
  assert_contains "$quick" "gh auth login"
  assert_contains "$quick" "gh repo clone"

  auth_line=$(printf '%s\n' "$quick" | grep -nF 'gh auth login' | head -n 1 | cut -d: -f1)
  clone_line=$(printf '%s\n' "$quick" | grep -nE '^[[:space:]]*(gh repo clone|git clone)' \
    | head -n 1 | cut -d: -f1)
  if [[ -z "$auth_line" || -z "$clone_line" ]]; then
    _fail "expected a gh auth login line and a clone line in Quick start (auth=$auth_line clone=$clone_line)"
  elif (( auth_line >= clone_line )); then
    _fail "expected gh auth login (line $auth_line) before first clone (line $clone_line) in Quick start"
  fi

  # No clone instruction anywhere may precede the first auth instruction.
  auth_line=$(grep -nF 'gh auth login' "$ROOT/README.md" | head -n 1 | cut -d: -f1)
  clone_line=$(grep -nE '^[[:space:]]*(gh repo clone|git clone)' "$ROOT/README.md" \
    | head -n 1 | cut -d: -f1)
  if [[ -z "$auth_line" || -z "$clone_line" ]]; then
    _fail "expected a gh auth login line and a clone line in README (auth=$auth_line clone=$clone_line)"
  elif (( auth_line >= clone_line )); then
    _fail "expected the first gh auth login (line $auth_line) before the first clone (line $clone_line)"
  fi
}

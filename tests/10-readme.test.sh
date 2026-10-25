#!/usr/bin/env bash
# shellcheck shell=bash
# README documents every flag and every manual step (Task 10).

test_readme_documents_usage_and_manual_steps() {
  for s in --dry-run --force --config-only --with-headroom --doctor \
           "opencode auth login" "service.json" "npx skills add" "graphify install"; do
    assert_contains "$(cat "$ROOT/README.md")" "$s"
  done
}

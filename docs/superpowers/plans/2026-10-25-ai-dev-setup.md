# AI Dev Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a private repo whose single idempotent `install.sh` reproduces this machine's OpenCode V2 + delegation setup on a fresh Linux machine without secrets.

**Architecture:** A payload tree (`config/`, `plugins/`, `skills/`, `delegate/`) plus one bash installer that preflights, backs up, copies with drift protection, installs missing binaries and upstream skills, and exposes a `--doctor` check mode. Tests are plain bash functions run in a fake `$HOME` with command stubs; no external test framework.

**Tech Stack:** Bash 5, Node ≥ 18 (JSON validation, npm, npx), OpenCode V2, uv, rtk, headroom, graphify.

**Spec:** `docs/superpowers/specs/2026-10-25-ai-dev-setup-design.md`

## Global Constraints

- Node ≥ 18 required; missing Node stops with the nvm command and exit 1. Never install a runtime silently.
- No root/sudo. All writes under `$HOME`.
- Config dir is `${XDG_CONFIG_HOME:-$HOME/.config}/opencode` (call it `$CFG` in scripts).
- Never read, copy, print, or back up `service.json`.
- No `/home/stave` (or any absolute home path) in `config/`, `plugins/`, `skills/`, `delegate/`.
- `opencode.jsonc` must be comment-free valid JSON so it can be validated with `JSON.parse`.
- V2 config shapes only: `mcp.servers`, `providers`; no top-level `mcp`/`provider`.
- `install.sh` uses `set -euo pipefail`, quoted expansions, and exits 1 on operational failure, 2 on usage errors.
- No `rm -rf` outside the timestamped backup dir; never delete `service.json`, `node_modules`, or user data.
- `bash -n install.sh` and `shellcheck install.sh` (when installed) must pass.
- Every task ends with the full test suite green and a commit.

## Review Focus

1. A destination file differs and the user runs without `--force` → installer backs up, then aborts with exit 1 without modifying the destination (Task 5).
2. Re-running on an already-installed machine → no writes, no npm rerun, exit 0 (Tasks 4, 6).
3. A machine-specific path or V1 shape leaks into `opencode.jsonc` → config silently unusable elsewhere; static payload test plus doctor check catch it (Tasks 3, 9).
4. `npx` fails or network is unavailable during skills install → installer exits non-zero with a skills-specific message instead of claiming success (Task 7).
5. An existing `service.json` sits in the destination → it is untouched, absent from backups, and never printed (Task 4).

---

### Task 1: Test harness and sandbox

**Files:**
- Create: `tests/run.sh`, `tests/lib.sh`
- Create: `tests/stubs/opencode`, `tests/stubs/uv`, `tests/stubs/rtk`, `tests/stubs/headroom`, `tests/stubs/graphify`, `tests/stubs/npm`, `tests/stubs/npx`, `tests/stubs/gh`
- Create: `.gitignore`

**Interfaces:**
- Produces: `new_sandbox`, `sandbox_without <cmd>`, `check <cmd...>` (runs a command, sets `STATUS` and `OUT` to its combined output), `run_install [args...]` (runs `install.sh` from `$ROOT` via `check`), `assert_eq <expected> <actual>`, `assert_exit <code>` (asserts `$STATUS`), `assert_file_exists <path>`, `assert_file_missing <path>`, `assert_file_eq <expected-file> <actual-file>`, `assert_contains <haystack> <needle>`, `assert_not_contains <haystack> <needle>`, `assert_file_contains <file> <needle>`, `assert_file_not_contains <file> <needle>`, `$TEST_LOG` (stub invocation log), `$ROOT` (repo root), `$SANDBOX`.
- Produces: assertions never exit; on mismatch they print `expected ... got ...` and set `TEST_FAILED=1`. `run_test` resets that flag, calls the function, and reports `ok` only when it is still 0.
- Produces: `tests/run.sh` discovers `tests/*.test.sh`, sources each, runs every `test_*` function, prints `ok N - name` / `not ok N - name`, exits 1 on any failure. It also runs `bash -n` on `install.sh` when that file exists.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
node_modules/
backups/
service.json
.env
*.headroom-backup
```

- [ ] **Step 2: Write `tests/lib.sh` and `tests/run.sh` with a harness self-test**

`tests/lib.sh` uses only bash builtins plus `mktemp`, `cmp`, `grep`, `cp`. `new_sandbox` creates `$SANDBOX` under `${TMPDIR:-/tmp}/ai-dev-setup-tests`, sets and exports `HOME="$SANDBOX/home"`, exports `TEST_LOG="$SANDBOX/test.log"`, copies `$ROOT/tests/stubs` to `$SANDBOX/stubs` (tests may edit the copy, never the repo), and prepends `$SANDBOX/stubs` to `PATH`. `sandbox_without cmd` deletes `$SANDBOX/stubs/<cmd>`. `check` runs `"$@"`, captures combined output in `OUT` and the code in `STATUS`, and never aborts. `run_install` does `OUT=$(cd "$ROOT" && ./install.sh "$@" 2>&1); STATUS=$?` under `set +e`, so `install.sh` sees `$ROOT` as its own directory.

Create `tests/01-harness.test.sh`:

```bash
test_harness_assertions_work() {
  new_sandbox
  assert_eq "a" "a"
  assert_file_missing "$HOME/nope"
  touch "$HOME/y"; assert_file_exists "$HOME/y"
}
```

- [ ] **Step 3: Run the harness**

Run: `./tests/run.sh`
Expected: exactly `ok 1 - test_harness_assertions_work`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add .gitignore tests
git commit -m "test: add fake-home test harness and command stubs"
```

---

### Task 2: `install.sh` CLI contract and preflight

**Files:**
- Create: `install.sh`
- Test: `tests/02-cli.test.sh`

**Interfaces:**
- Produces: flags `--dry-run`, `--force`, `--config-only`, `--with-headroom`, `--doctor`, `--help`; globals `ROOT`, `CFG`, `DRY_RUN`, `FORCE`, `CONFIG_ONLY`, `WITH_HEADROOM`, `DOCTOR`; functions `usage`, `die`, `usage_error`, `need_cmd`, `check_node`, `parse_args`, `main`.
- Produces: `main` calls `doctor` when `DOCTOR=true`, and otherwise calls `install_all` (defined as a no-op placeholder in this task).

- [ ] **Step 1: Write the failing tests**

`tests/02-cli.test.sh`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/run.sh`
Expected: 5 failures, first message mentions missing `install.sh`.

- [ ] **Step 3: Implement the skeleton**

`install.sh` starts with `#!/usr/bin/env bash`, `set -euo pipefail`, sets `ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"`, `CFG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"`, defaults all flags to false. `usage` prints the flag table from the spec. `die` writes to stderr and exits 1. `usage_error` exits 2. `check_payload` requires `$ROOT/config`, `$ROOT/plugins`, `$ROOT/skills`, `$ROOT/delegate` and dies with `not a complete checkout: <missing>` otherwise. `check_node` parses `node -v`, strips `v`, requires major ≥ 18, else `die` with the literal hint `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash && nvm install --lts`. `need_cmd` takes the command and the hint to print. `main` calls `parse_args "$@"`, `need_cmd bash`, `need_cmd curl`, `check_node`, `check_payload`, then dispatches. `install_all` prints `nothing to do yet` and returns 0.

- [ ] **Step 4: Run to verify pass**

Run: `./tests/run.sh`
Expected: all 6 tests pass. Also run `bash -n install.sh` and `shellcheck install.sh` (if available): no output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/02-cli.test.sh
git commit -m "feat: add installer CLI contract and preflight checks"
```

---

### Task 3: Config payload and normalization

**Files:**
- Create: `config/opencode.jsonc`, `config/cli.json`, `config/AGENTS.md`, `config/package.json`
- Create: `config/package-lock.json` (generated)
- Create: `plugins/rtk.ts`, `plugins/graphify.js`
- Create: `skills/graphify/` (copied), `skills/orchestrating-spec-pipelines/` (copied)
- Create: `delegate/config.json` (copied)
- Test: `tests/03-payload.test.sh`

**Interfaces:**
- Produces: the exact payload tree the installer copies. `config/opencode.jsonc` is comment-free JSON with `mcp.servers.headroom`, `mcp.servers.serena`, `providers.headroom`, `plugins`, `model`.
- Produces: `config/package.json` depending only on `@opencode/plugin`.

- [ ] **Step 1: Write the failing tests**

`tests/03-payload.test.sh`:

```bash
test_config_is_valid_json() {
  check node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' \
    "$ROOT/config/opencode.jsonc"
  assert_exit 0
}
test_config_uses_v2_shapes() {
  check node -e '
    const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    if(!d.mcp?.servers?.headroom) throw new Error("mcp.servers.headroom");
    if(!d.mcp?.servers?.serena) throw new Error("mcp.servers.serena");
    if(!d.providers?.headroom) throw new Error("providers.headroom");
    if(d.mcp?.headroom) throw new Error("v1 mcp");
    if(d.provider) throw new Error("v1 provider");
  ' "$ROOT/config/opencode.jsonc"; assert_exit 0
}
test_payload_has_no_absolute_home_paths() {
  check bash -c '! grep -R "/home/stave" "$@"' _ \
    "$ROOT/config" "$ROOT/plugins" "$ROOT/skills" "$ROOT/delegate"
  assert_exit 0
}
test_plugins_import_v2_package_only() {
  check grep -q '@opencode/plugin' "$ROOT/plugins/rtk.ts"; assert_exit 0
  check grep -q '@opencode/plugin' "$ROOT/plugins/graphify.js"; assert_exit 0
  check grep -q '@opencode-ai/plugin' "$ROOT/config/package.json"; assert_exit 1
}
test_delegate_lanes_are_valid() {
  check node -e '
    const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    const lanes=Object.entries(d.lanes||{});
    if(lanes.length!==7) throw new Error("expected 7 lanes");
    for(const [id,l] of lanes) if(!l.implementer) throw new Error(id+" missing implementer");
  ' "$ROOT/delegate/config.json"; assert_exit 0
}
test_vendored_skills_have_frontmatter() {
  for s in graphify orchestrating-spec-pipelines; do
    check grep -q '^name:' "$ROOT/skills/$s/SKILL.md"; assert_exit 0
  done
}
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/run.sh`
Expected: the six new tests fail because payload files are missing.

- [ ] **Step 3: Copy the verbatim payload**

```bash
mkdir -p config plugins delegate skills
cp ~/.config/opencode/cli.json config/cli.json
cp ~/.config/opencode/AGENTS.md config/AGENTS.md
cp ~/.config/opencode/plugins/rtk.ts plugins/rtk.ts
cp ~/.opencode/.opencode/plugins/graphify.js plugins/graphify.js
cp -a ~/.config/opencode/skills/graphify skills/
cp -a ~/.config/opencode/skills/orchestrating-spec-pipelines skills/
cp ~/.config/delegate-skills/config.json delegate/config.json
```

- [ ] **Step 4: Write `config/opencode.jsonc`**

Exact content (no comments — doctor runs `JSON.parse` on it):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "opencode-go/deepseek-v4.1-flash#high",
  "plugins": [
    "superpowers@git+https://github.com/obra/superpowers.git"
  ],
  "mcp": {
    "servers": {
      "headroom": {
        "type": "local",
        "command": ["headroom", "mcp", "serve"]
      },
      "serena": {
        "type": "local",
        "command": [
          "uvx", "--from", "git+https://github.com/oraios/serena",
          "serena", "start-mcp-server",
          "--project-from-cwd", "--context", "agent",
          "--open-web-dashboard", "False"
        ]
      }
    }
  },
  "providers": {
    "headroom": {
      "name": "Headroom Proxy",
      "package": "aisdk:@ai-sdk/openai-compatible",
      "settings": {
        "baseURL": "http://127.0.0.1:8787/v1"
      },
      "models": {
        "claude-sonnet-4-6": {
          "name": "Claude Sonnet 4.6",
          "limit": { "context": 200000, "output": 16384 }
        },
        "claude-opus-4-6": {
          "name": "Claude Opus 4.6",
          "limit": { "context": 200000, "output": 16384 }
        },
        "claude-haiku-4-5-20251001": {
          "name": "Claude Haiku 4.5",
          "limit": { "context": 200000, "output": 8192 }
        },
        "gpt-4o": {
          "name": "GPT-4o",
          "limit": { "context": 128000, "output": 16384 }
        },
        "gpt-4.1": {
          "name": "GPT-4.1",
          "limit": { "context": 1048576, "output": 32768 }
        }
      }
    }
  }
}
```

- [ ] **Step 5: Write `config/package.json` and generate the lock**

```json
{
  "dependencies": {
    "@opencode/plugin": "^2.0.22"
  }
}
```

Run: `(cd config && npm install --package-lock-only --omit=dev)`
Expected: `config/package-lock.json` created, no `node_modules` in `config/`.

- [ ] **Step 6: Run tests and commit**

Run: `./tests/run.sh`
Expected: all tests pass.

```bash
git add config plugins skills delegate tests/03-payload.test.sh
git commit -m "feat: add normalized OpenCode config payload"
```

---

### Task 4: Config installation, backups, and stale removal

**Files:**
- Modify: `install.sh`
- Test: `tests/04-install-config.test.sh`

**Interfaces:**
- Consumes: `$ROOT/config`, `$ROOT/plugins`, `$ROOT/skills`, `$ROOT/delegate`.
- Produces: `install_all`, `install_file <src> <dest>`, `remove_stale <path>`, `print_next_steps`, `$BACKUP_DIR`.

- [ ] **Step 1: Write the failing tests**

`tests/04-install-config.test.sh`:

```bash
test_config_only_installs_every_payload_file() {
  new_sandbox; run_install --config-only --force
  assert_exit 0
  for p in opencode.jsonc cli.json AGENTS.md plugins/rtk.ts plugins/graphify.js \
           skills/graphify/SKILL.md skills/orchestrating-spec-pipelines/SKILL.md; do
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
  check test -n "$(find "$HOME/.config/opencode/backups" -name 'opencode.json*' -print -quit)"
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
  check test -z "$(find "$HOME/.config/opencode/backups" -name service.json -print -quit)"
  assert_exit 0
}
test_next_steps_are_printed() {
  new_sandbox; run_install --config-only --force
  assert_exit 0
  assert_contains "$OUT" "opencode auth login"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/run.sh`
Expected: the five new tests fail (`nothing to do yet`).

- [ ] **Step 3: Implement the copy engine**

`install_all` sets `BACKUP_DIR="$CFG/backups/$(date -u +%Y%m%dT%H%M%SZ)"`. It declares a mapping array of `src|dest` pairs covering `config/opencode.jsonc`, `config/cli.json`, `config/AGENTS.md`, every file under `plugins/` and `skills/` (recursive, preserving relative paths), and `delegate/config.json` → `$HOME/.config/delegate-skills/config.json`. `install_file` creates the destination directory, compares with `cmp -s`, and: identical → increment `SKIPPED`; differs → `backup_file`, then copy when `FORCE=true`, else record drift. `backup_file` copies to `$BACKUP_DIR` preserving the relative path and prints the backup path. `remove_stale` applies only to `$CFG/opencode.json` and `$CFG/opencode.jsonc.headroom-backup`: back up then `rm` when present. `service.json` must never appear in any mapping, glob, or `find`.

When no drift occurred print `up to date (N files unchanged)`; when drift occurred without `--force`, print each path then `die`. After a successful install call `print_next_steps`, which prints exactly: `opencode auth login`, the headroom account note, and the GitHub-auth note for HTTPS clones. `--dry-run` prints planned copies/removals and returns before any write. `--config-only` governs only Task 8's binary step, so it must still run the config steps here.

- [ ] **Step 4: Run tests**

Run: `./tests/run.sh`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/04-install-config.test.sh
git commit -m "feat: install config payload with backups and stale cleanup"
```

---

### Task 5: Drift protection and `--force`

**Files:**
- Modify: `install.sh`
- Test: `tests/05-drift.test.sh`

**Interfaces:**
- Consumes: `install_file`, `backup_file`, `$BACKUP_DIR`.
- Produces: two-phase behavior — all backups happen first; without `--force` a non-empty drift list aborts before any destination is written.

- [ ] **Step 1: Write the failing tests**

`tests/05-drift.test.sh`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/run.sh`
Expected: drift/force tests fail (current code copies immediately or aborts after writing).

- [ ] **Step 3: Split into backup and apply phases**

`install_all` runs `plan_files` (fills `CHANGED[]`, `SKIPPED`, per-file `BACKUP_DIR` copies for changed files) then: `DRY_RUN` → print `would overwrite <dest>` / `would create <dest>` and return 0; `CHANGED` non-empty and `FORCE=false` → print `refusing to overwrite: <dest>` lines and exit 1; otherwise apply all copies. Keep stale-removal in the apply phase so a drift abort leaves stale files alone too.

- [ ] **Step 4: Run tests**

Run: `./tests/run.sh`
Expected: all tests pass, including Task 4's idempotency test.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/05-drift.test.sh
git commit -m "feat: abort on config drift unless --force"
```

---

### Task 6: Local plugin dependencies

**Files:**
- Modify: `install.sh`
- Test: `tests/06-plugin-deps.test.sh`

**Interfaces:**
- Produces: `ensure_plugin_deps`, `$LOCKHASH_FILE="$CFG/.lockhash"`.
- Consumes: `$ROOT/config/package.json`, `$ROOT/config/package-lock.json`.

- [ ] **Step 1: Write the failing tests**

`tests/06-plugin-deps.test.sh`:

```bash
test_npm_runs_when_plugin_missing() {
  new_sandbox; run_install --config-only --force
  assert_exit 0
  assert_contains "$(cat "$TEST_LOG")" "npm install --omit=dev"
  assert_file_exists "$HOME/.config/opencode/node_modules/@opencode/plugin"
  assert_file_exists "$HOME/.config/opencode/.lockhash"
}
test_npm_is_not_rerun_when_lock_matches() {
  new_sandbox
  run_install --config-only --force
  run_install --config-only
  assert_eq 1 "$(grep -c 'npm install --omit=dev' "$TEST_LOG")"
}
test_npm_reruns_when_lockhash_differs() {
  new_sandbox
  run_install --config-only --force
  echo stale > "$HOME/.config/opencode/.lockhash"
  run_install --config-only --force
  assert_eq 2 "$(grep -c 'npm install --omit=dev' "$TEST_LOG")"
}
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/run.sh`
Expected: three failures (no npm invocation).

- [ ] **Step 3: Implement `ensure_plugin_deps`**

Copy `config/package.json` and `config/package-lock.json` into `$CFG` (through `install_file`, so drift rules apply). Compute `sha256sum "$CFG/package-lock.json"`. If `$CFG/node_modules/@opencode/plugin` exists and `$LOCKHASH_FILE` contains that hash, print `plugin deps up to date` and return. Otherwise `(cd "$CFG" && npm install --omit=dev)` then write the hash to `$LOCKHASH_FILE`. Under `--dry-run`, print the command instead of running it. `npm` failure calls `die "npm install failed"`.

- [ ] **Step 4: Run tests**

Run: `./tests/run.sh`
Expected: all tests pass. Confirm `tests/stubs/npm` logs `npm install --omit=dev` and creates `node_modules/@opencode/plugin`.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/06-plugin-deps.test.sh
git commit -m "feat: install local plugin dependencies with lock stamping"
```

---

### Task 7: Delegation skills via npx

**Files:**
- Modify: `install.sh`
- Test: `tests/07-skills.test.sh`

**Interfaces:**
- Produces: `install_skills`, `$DELEGATE_REPO="amElnagdy/delegate-skills"`, `$FIND_SKILLS="vercel-labs/skills@find-skills"`.

- [ ] **Step 1: Write the failing tests**

`tests/07-skills.test.sh`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/run.sh`
Expected: three failures (no npx call).

- [ ] **Step 3: Implement `install_skills`**

`need_cmd npx "Install Node.js ≥ 18 (nvm) and retry"`. Run `npx --yes skills add "$DELEGATE_REPO" -g -y`, then `npx --yes skills add "$FIND_SKILLS" -g -y`. A non-zero result calls `die "skills install failed"`. After success, count directories under `$HOME/.agents/skills` and print `<N> skills present`. Under `--dry-run`, print both commands and do not enforce `npx`.

- [ ] **Step 4: Run tests**

Run: `./tests/run.sh`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/07-skills.test.sh
git commit -m "feat: install delegate skills from upstream"
```

---

### Task 8: Missing binaries and opt-in headroom

**Files:**
- Modify: `install.sh`
- Test: `tests/08-binaries.test.sh`

**Interfaces:**
- Produces: `ensure_bin <cmd> <install-command>`, `install_binaries`, `deploy_headroom`.
- Consumes: `CONFIG_ONLY`, `WITH_HEADROOM`, `DRY_RUN`.

- [ ] **Step 1: Write the failing tests**

`tests/08-binaries.test.sh`:

```bash
test_present_binaries_are_not_reinstalled() {
  new_sandbox; run_install --dry-run
  assert_exit 0
  assert_contains "$OUT" "found opencode"
  assert_contains "$OUT" "found rtk"
  assert_contains "$OUT" "found headroom"
  assert_contains "$OUT" "found graphify"
  assert_not_contains "$OUT" "curl -fsSL https://opencode.ai"
}
test_missing_binary_is_reported_with_command() {
  new_sandbox; sandbox_without rtk
  run_install --dry-run
  assert_exit 0
  assert_contains "$OUT" "missing rtk"
  assert_contains "$OUT" "raw.githubusercontent.com/rtk-ai/rtk"
}
test_config_only_skips_binary_installation() {
  new_sandbox; run_install --config-only --force
  assert_not_contains "$OUT" "missing opencode"
  assert_file_not_contains "$TEST_LOG" "uv tool install"
}
test_headroom_deploy_runs_then_config_is_reasserted() {
  new_sandbox; run_install --config-only --force --with-headroom
  assert_exit 0
  assert_file_contains "$TEST_LOG" "deploy --target opencode --port 8787"
  assert_file_eq "$ROOT/config/opencode.jsonc" "$HOME/.config/opencode/opencode.jsonc"
}
```

The headroom stub must write `clobbered` into `$HOME/.config/opencode/opencode.jsonc` when invoked with `deploy`, so the last assertion proves the re-assert works.

- [ ] **Step 2: Run to verify failure**

Run: `./tests/run.sh`
Expected: four failures.

- [ ] **Step 3: Implement**

`install_binaries` (skipped under `--config-only`) calls `ensure_bin` for: `opencode` → `curl -fsSL https://opencode.ai/v2/install | bash`; `uv` → official standalone installer; `rtk` → `curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh`; `headroom` → `uv tool install headroom-ai`; `graphify` → `uv tool install graphifyy`. `ensure_bin` prints `found <cmd> <version>` when present, or `missing <cmd>: <install-command>` and runs it unless `DRY_RUN`. It prepends `$HOME/.local/bin` and `$HOME/.opencode/bin` to `PATH` before checks. It runs before the config phase.

`deploy_headroom` runs after the config phase and after `ensure_plugin_deps`: if `WITH_HEADROOM=true`, run `headroom deploy --target opencode --port 8787` (failure prints a warning and continues), then re-copy `config/opencode.jsonc` with force semantics so the repo version wins. Without the flag, do nothing.

- [ ] **Step 4: Run tests**

Run: `./tests/run.sh`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/08-binaries.test.sh
git commit -m "feat: install missing binaries and optional headroom deploy"
```

---

### Task 9: `--doctor`

**Files:**
- Modify: `install.sh`
- Test: `tests/09-doctor.test.sh`

**Interfaces:**
- Produces: `doctor`, `check <description> <command...>` (increments `FAIL_COUNT`), `SKIP_COUNT`.
- Consumes: `$CFG`, `$HOME/.agents/skills`, `$HOME/.config/delegate-skills/config.json`.

- [ ] **Step 1: Write the failing tests**

`tests/09-doctor.test.sh`:

```bash
test_doctor_passes_after_install() {
  new_sandbox
  run_install --config-only --force
  run_install --doctor
  assert_exit 0
  assert_not_contains "$OUT" "FAIL"
  assert_contains "$OUT" "PASS"
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
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/run.sh`
Expected: four failures.

- [ ] **Step 3: Implement `doctor`**

Runs the nine spec checks in order, printing `PASS <desc>` / `FAIL <desc>` (and the failure detail), without starting any OpenCode service:

1. commands present: `git`, `node` (major ≥ 18), `opencode`, `uv`, `rtk`, `headroom`, `graphify`.
2. `$CFG/opencode.jsonc`, `cli.json`, `AGENTS.md` exist.
3. `node -e 'JSON.parse(...)'` succeeds and asserts `mcp.servers.headroom`, `mcp.servers.serena`, `providers.headroom`.
4. `$CFG/node_modules/@opencode/plugin` exists.
5. `$HOME/.agents/skills/opencode-delegate/SKILL.md` and `delegate-setup/SKILL.md` exist.
6. lane JSON parses, has 7 lanes, each with `implementer` (label `FAIL delegate lanes`).
7. `rtk rewrite "git status"` outputs `rtk git status` (label `FAIL rtk rewrite`).
8. with `--with-headroom` only: something listens on 8787 (`ss -ltn`); if `ss` is unavailable print `SKIP port 8787`.
9. `opencode debug paths config` equals `$CFG`.

Print `doctor: N passed, M failed, K skipped`; exit 1 when `FAIL_COUNT > 0`.

- [ ] **Step 4: Run tests**

Run: `./tests/run.sh`
Expected: all tests pass. Also run `./install.sh --doctor` in the real environment after Task 10's install.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/09-doctor.test.sh
git commit -m "feat: add doctor checks"
```

---

### Task 10: README, real-machine install, and private GitHub push

**Files:**
- Create: `README.md`
- Test: `tests/10-readme.test.sh`

**Interfaces:**
- Produces: documented usage for every flag and every manual step.
- Produces: private repo `omarahmedZa/ai-dev-setup` with `main` pushed.

- [ ] **Step 1: Write the failing test**

`tests/10-readme.test.sh`:

```bash
test_readme_documents_usage_and_manual_steps() {
  for s in --dry-run --force --config-only --with-headroom --doctor \
           "opencode auth login" "service.json" "npx skills add" "graphify install"; do
    assert_contains "$(cat "$ROOT/README.md")" "$s"
  done
}
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/run.sh`
Expected: one failure (missing `README.md`).

- [ ] **Step 3: Write `README.md`**

Sections: what it installs; quick start (`git clone`, `./install.sh`); flag table; what is never installed (`service.json`, secrets); manual steps (`opencode auth login`, headroom account, `gh auth login`); doctor; update flow (`git pull && ./install.sh --force && ./install.sh --doctor`); refreshing the vendored graphify skill (`graphify install --platform opencode`, then copy back); fallback if `npx skills` changes (clone `amElnagdy/delegate-skills`, copy `skills/*` to `~/.agents/skills/`).

- [ ] **Step 4: Run the full suite**

Run: `./tests/run.sh` and `shellcheck install.sh tests/*.sh`
Expected: all green, no shellcheck findings.

- [ ] **Step 5: Real-machine run**

Run: `./install.sh --dry-run` first, then `./install.sh --force`, then `./install.sh --doctor`.
Expected: dry-run writes nothing; real run backs up changed files under `~/.config/opencode/backups/`; doctor exits 0. Verify with `opencode api get /api/config`: exactly one merged document with `mcp.servers` and `providers`, no V1 keys.

- [ ] **Step 6: Create and push the private repo**

```bash
git add README.md tests/10-readme.test.sh
git commit -m "docs: add setup README"
gh repo create omarahmedZa/ai-dev-setup --private --source=. --remote=origin --push
gh repo view omarahmedZa/ai-dev-setup --json visibility -q .visibility
```

Expected: `PRIVATE`. Then `git status --short` is empty and `git log --oneline` shows one commit per task.

---

## Self-Review

**Spec coverage:** scope/decisions → Tasks 1–10; inventory dispositions → Tasks 3–4 (payload, stale removal, graphify plugin relocation), 6 (package deps), 7 (skills), 8 (binaries); config normalization → Task 3 exact JSON plus static tests and Task 9 doctor; installer contract and flags → Tasks 2, 4, 5, 6, 7, 8, 9; idempotency/safety → Tasks 4, 5, 6 plus Review Focus tests; manual steps → Task 4; doctor → Task 9; testing plan → harness plus per-task tests and Task 10 real run; update flow → Task 10 README; risks → constraints, fallbacks in README, and Task 8's headroom re-assert; acceptance criteria → Task 10. No spec section is unimplemented.

**Step scan:** every step names a file, a command, or an assertion with exact values. Payload JSON and `package.json` are exact copy the spec fixes; installer and doctor bodies are described by behavior, not transcribed.

**Type consistency:** harness names used in later tasks match Task 1 (`new_sandbox`, `sandbox_without`, `check`, `run_install`, `assert_*`, `OUT`, `STATUS`, `TEST_FAILED`, `TEST_LOG`, `SANDBOX`); installer names used in later tasks match Task 2 (`ROOT`, `CFG`, `DRY_RUN`, `FORCE`, `CONFIG_ONLY`, `WITH_HEADROOM`, `DOCTOR`, `die`, `check_payload`); `ensure_plugin_deps`, `install_skills`, `ensure_bin`, `install_binaries`, `deploy_headroom`, `doctor` are each defined by the task that later tasks consume.

**Review Focus:** (1) Task 5 drift abort; (2) Task 4 second-run and Task 6 npm-skip; (3) Task 3 v2-shape/no-absolute-path and Task 9 doctor parse; (4) Task 7 npx failure; (5) Task 4 `service.json` test. Preflight completeness is pinned by Task 2's `test_incomplete_checkout_fails_preflight`.

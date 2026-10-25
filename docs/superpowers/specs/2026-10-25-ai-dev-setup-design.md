# AI Dev Setup — Design

Date: 2026-10-25
Status: approved (design)
Repo: `omarahmedZa/ai-dev-setup` (private), local path `~/Documents/ai-dev-setup`

## Purpose

Reproduce this machine's OpenCode + delegation setup on a fresh Linux machine with
one command, without committing secrets, and without hand-rebuilding the config.

Success means: on a clean machine with `git`, `curl`, and Node ≥ 18,

```sh
git clone git@github.com:omarahmedZa/ai-dev-setup.git
cd ai-dev-setup
./install.sh
```

produces a working OpenCode V2 install whose config, local plugins, custom skills,
delegate lanes, and delegation skills all match this machine — and `./install.sh
--doctor` reports every check as passing.

## Non-goals

- Not a general dotfiles manager. Shell, editor, and OS config are out of scope.
- Not a secrets store. No provider keys, service passwords, or subscription state.
- Not a vendoring mirror of `amElnagdy/delegate-skills`; that is installed upstream.
- Not a package manager for implementer CLIs (Claude Code, Codex, Cursor, ...). Only
  OpenCode is required; the delegate skills discover other CLIs at runtime.
- `~/AGENTS.md` (home-level RTK instructions used by non-OpenCode agents) is out of
  scope. Only `~/.config/opencode/AGENTS.md` is managed.

## Decisions

| Decision | Choice | Reason |
| --- | --- | --- |
| Scope | Full environment (binaries + config + skills + lanes) | User wants one-command setup, not a config snippet |
| Repo visibility | Private | Contains personal models, lanes, and workflow policy |
| Secrets | Excluded, gitignored | `service.json` holds a service password; `~/.headroom` holds subscription state |
| Installer | Single idempotent `install.sh` | No extra engine (chezmoi/stow) to learn or debug |
| Delivery | Copy into `~/.config/opencode` | `node_modules` and plugin resolution require a real directory |
| Delegate skills | Upstream install via `npx skills add` | Keeps lock-file tracking and updates |
| Custom skills | Vendored in repo | `graphify` and `orchestrating-spec-pipelines` are part of this setup |

## Current state (inventory)

What this machine actually has today, and what happens to each item:

| Current path | Content | Disposition |
| --- | --- | --- |
| `~/.config/opencode/opencode.json` | model + V1-shaped `mcp` | Merged into `config/opencode.jsonc`, then removed |
| `~/.config/opencode/opencode.jsonc` | model + superpowers plugin + V1-shaped `provider` | Merged into `config/opencode.jsonc` |
| `~/.config/opencode/cli.json` | theme `vesper`, diff/session prefs | Copied verbatim |
| `~/.config/opencode/AGENTS.md` | RTK rules + delegation policy | Copied verbatim |
| `~/.config/opencode/plugins/rtk.ts` | V2 plugin (`Plugin.define`) | Copied verbatim |
| `~/.config/opencode/skills/graphify/` | 108K skill + references | Vendored |
| `~/.config/opencode/skills/orchestrating-spec-pipelines/` | 24K skill | Vendored |
| `~/.config/opencode/package.json` | V1 + V2 plugin deps | Trimmed to `@opencode/plugin` only, committed |
| `~/.config/opencode/package-lock.json` | lock | Committed |
| `~/.config/opencode/node_modules/` | installed deps | Not committed; `npm install` on target |
| `~/.config/opencode/service.json` | **service password** | Never copied; machine-generated |
| `~/.config/opencode/opencode.jsonc.headroom-backup` | stale backup | Ignored |
| `~/.opencode/.opencode/plugins/graphify.js` | plugin in a location OpenCode does not load | Moved to `plugins/graphify.js` in the repo and installed into `~/.config/opencode/plugins/` |
| `~/.config/delegate-skills/config.json` | 7 lanes, all `opencode` implementer | Copied verbatim |
| `~/.agents/skills/*` (21 dirs) | upstream delegate skills + find-skills | Installed upstream by `npx skills add amElnagdy/delegate-skills -g -y` |
| `~/.local/bin/rtk` 0.43.0 | Rust binary from `rtk-ai/rtk` | Installed by official installer if absent |
| `uv tool` headroom-ai 0.32.1 | `headroom` CLI | Installed if absent (`uv tool install headroom-ai`) |
| `uv tool` graphifyy 0.9.26 | `graphify` CLI | Installed if absent (`uv tool install graphifyy`) |
| OpenCode V2.1.4 server / v2.0.22 CLI | `~/.opencode/bin/opencode` | Installed if absent (`https://opencode.ai/v2/install`) |

## Repo layout

```text
ai-dev-setup/
├── install.sh
├── README.md
├── .gitignore
├── docs/superpowers/specs/2026-10-25-ai-dev-setup-design.md
├── config/
│   ├── opencode.jsonc
│   ├── cli.json
│   ├── AGENTS.md
│   ├── package.json
│   └── package-lock.json
├── plugins/
│   ├── rtk.ts
│   └── graphify.js
├── skills/
│   ├── graphify/
│   │   ├── SKILL.md
│   │   ├── .graphify_version
│   │   └── references/*.md
│   └── orchestrating-spec-pipelines/
│       ├── SKILL.md
│       ├── ralph-loop-prompt.md
│       ├── role-simulation.md
│       └── state-file-schema.md
└── delegate/
    └── config.json
```

`.gitignore`:

```gitignore
node_modules/
backups/
service.json
.env
*.headroom-backup
```

## Config normalization

The target `config/opencode.jsonc` is a single V2-native document. V2 currently
tolerates the V1 `mcp`/`provider` shapes (it migrates them), but the repo should not
depend on that. Concretely:

- `mcp` → `mcp.servers`
- `provider` → `providers`, with `npm` → `package: "aisdk:@ai-sdk/openai-compatible"`
  and `options` → `settings` (matching what the running server reports today)
- `headroom` MCP command becomes `["headroom", "mcp", "serve"]` — no absolute
  `/home/stave/.local/bin/headroom` path, so it works for any user
- `model` keeps `opencode-go/deepseek-v4.1-flash#high`; the running server does
  retain the `high` variant, verified via `opencode api get /api/config`
- `plugins` keeps `superpowers@git+https://github.com/obra/superpowers.git`
- `serena` MCP stays `uvx --from git+https://github.com/oraios/serena ...`; `uv`
  fetches it on demand, so no Serena install step is needed

The asynchronous `opencode.json` is removed during install (moved to the backup
directory) so the two files cannot re-merge into conflicting settings on the target.

`graphify.js` is installed to `~/.config/opencode/plugins/`, which is a real plugin
source. Its current location under `~/.opencode/.opencode/plugins/` is not loaded.

`config/package.json`:

```json
{
  "dependencies": {
    "@opencode/plugin": "^2.0.22"
  }
}
```

The V1 `@opencode-ai/plugin` dependency is dropped because no local plugin imports it.

## Installer contract

`./install.sh [--dry-run] [--force] [--config-only] [--with-headroom] [--doctor] [--help]`

| Flag | Behavior |
| --- | --- |
| `--dry-run` | Print every action, write nothing |
| `--force` | Overwrite changed files even if they differ from the repo (backup still taken) |
| `--config-only` | Skip binary installation; do config, plugins, npm install, skills, lanes |
| `--with-headroom` | After config install, run `headroom deploy --target opencode --port 8787`, then re-assert the repo config |
| `--doctor` | Run checks only; exit non-zero on failure |
| `--help` | Usage |

### Steps

1. **Preflight.** Detect OS (Linux primary, macOS best-effort) and arch. Require
   `bash`, `git`, `curl`. Require Node ≥ 18; if missing, exit with the exact nvm
   command to run (do not silently install a runtime). Verify the script is running
   from a clean clone (`config/`, `plugins/`, `skills/`, `delegate/` present).
2. **Binaries** (skipped with `--config-only`). Install only if the command is
   missing:
   - OpenCode V2: `curl -fsSL https://opencode.ai/v2/install | bash`
   - `uv`: official standalone installer
   - `rtk`: `curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh`
   - `headroom`: `uv tool install headroom-ai`
   - `graphify`: `uv tool install graphifyy`
   `~/.local/bin` and `~/.opencode/bin` are added to `PATH` for the remainder of the
   script. Nothing is installed as root.
3. **Backup.** For every destination file whose content would change, copy the
   existing version to `~/.config/opencode/backups/<UTC timestamp>/` preserving
   relative paths. Then, if any file differs and `--force` was not passed, list the
   affected paths and exit non-zero without modifying any destination. Comparison is
   exact byte comparison; there is no whitespace exemption.
4. **Config install.** Copy `config/opencode.jsonc`, `config/cli.json`,
   `config/AGENTS.md`, `plugins/*`, `skills/*` into `~/.config/opencode/`; copy
   `delegate/config.json` to `~/.config/delegate-skills/config.json`. Remove a stale
   `~/.config/opencode/opencode.json` and `opencode.jsonc.headroom-backup` after
   backing them up.
5. **Local plugin deps.** In `~/.config/opencode`, copy `config/package.json` and
   `config/package-lock.json`, then run `npm install --omit=dev` when
   `node_modules/@opencode/plugin` is missing or the `sha256` of
   `package-lock.json` differs from the value stamped in
   `~/.config/opencode/.lockhash`. Write the stamp after a successful install.
6. **Delegation skills.** Run `npx --yes skills add amElnagdy/delegate-skills -g -y`
   (20 skills), then `npx --yes skills add vercel-labs/skills@find-skills -g -y`
   (1 skill). Report which skill IDs are now present under `~/.agents/skills`.
7. **Headroom (opt-in).** `headroom deploy --target opencode --port 8787`, then
   re-copy `config/opencode.jsonc` so any provider settings it wrote are replaced by
   the repo version. If the deploy fails, warn and continue; the repo config still
   works for non-headroom models.
8. **Manual steps.** Print, do not execute: `opencode auth login` for each provider,
   headroom account setup if the proxy backend needs it, and GitHub auth if the
   private clone was made over HTTPS.

### Idempotency and safety

- Re-running with no changes writes nothing and exits 0.
- No `rm -rf` outside the timestamped backup directory.
- All writes are to `$HOME`-relative paths; `$HOME` is honored (so a fake-home test
  is possible).
- `set -euo pipefail`, quoted paths, and a `trap` that reports the failed step.
- No secret is ever read, printed, or copied. `service.json` is explicitly skipped.

## Doctor checks

`./install.sh --doctor` verifies and prints one line per check:

1. Required commands exist and meet minimums: `git`, `node` ≥ 18, `opencode` (V2),
   `uv`, `rtk`, `headroom`, `graphify`.
2. `~/.config/opencode/opencode.jsonc`, `cli.json`, `AGENTS.md` exist.
3. `opencode.jsonc` parses as JSONC and contains `mcp.servers.headroom`,
   `mcp.servers.serena`, and `providers.headroom`.
4. `~/.config/opencode/node_modules/@opencode/plugin` exists.
5. `~/.agents/skills/opencode-delegate/SKILL.md` and `delegate-setup/SKILL.md` exist.
6. `~/.config/delegate-skills/config.json` parses and every lane has `implementer`.
7. `rtk rewrite "git status"` emits `rtk git status`.
8. With `--with-headroom`, port 8787 is listening.
9. `opencode debug paths config` resolves to `$HOME/.config/opencode`.

`opencode api get /api/info` is used only when a service is already running, so the
doctor never starts a background server as a side effect.

## Testing plan

1. `bash -n install.sh` and `shellcheck install.sh` when available.
2. `./install.sh --dry-run` on this machine: output lists intended writes, `git
   status` in the repo remains clean, `~/.config/opencode` mtimes unchanged.
3. Fake-home test: run
   `HOME=/tmp/ai-dev-setup-test ./install.sh --config-only` from a clean clone;
   assert files land under `/tmp/ai-dev-setup-test/.config/opencode`, a stale
   `opencode.json` there is removed, and a second run is a no-op.
4. Real run on this machine, then `./install.sh --doctor` and a manual
   `opencode api get /api/config` confirming one merged document with V2 shapes.
5. Failure-path test: make a destination file differ, run without `--force`, confirm
   the script stops before writing and names the file.

## Update flow

```sh
cd ~/Documents/ai-dev-setup
git pull
./install.sh --force
./install.sh --doctor
```

Drift captured on a machine is copied back manually into `config/`, `plugins/`,
`skills/`, or `delegate/` and committed. Live-edit symlinking is deliberately not used.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Upstream installer URLs change | Pin nothing; doctor prints installed versions. README lists the four upstream sources. |
| `npx skills add` changes skill layout | Doctor checks two known skill IDs; README documents the manual fallback (clone `amElnagdy/delegate-skills`, copy `skills/*` to `~/.agents/skills/`). |
| `headroom deploy` rewrites opencode config | Runs after the copy and the repo config is re-asserted; opt-in only. |
| Secrets leak into git | `.gitignore` plus a README rule; `service.json` is never read. `--dry-run` output contains paths only. |
| Node missing on fresh machine | Hard stop with the nvm command; no silent system runtime install. |
| Vendored `graphify` skill ages | `graphify install --platform opencode` refreshes it; documented in README. |

## Acceptance criteria

- A clean machine with `git`, `curl`, Node ≥ 18 runs `./install.sh` to completion and
  ends with OpenCode V2 configured as described, 20 delegate skills plus `find-skills`
  present, and 7 lanes configured.
- `--dry-run` and a second `./install.sh` make no changes.
- `--doctor` passes all applicable checks.
- Repo contains no secret, no `node_modules`, no absolute `/home/stave` path.
- The private GitHub repo exists and the initial commit is pushed.

# ai-dev-setup

Reproduce a working OpenCode V2 + delegation environment on a fresh Linux
machine with one command, without committing secrets and without hand-rebuilding
the config. macOS is best-effort and not exercised by the test suite.

The repository is the source of truth for the config, local plugins, vendored
skills, and delegate lanes. `install.sh` copies that payload into place, installs
any missing external tools, and installs the upstream delegation skills.

## What it installs

Payload copied into `~/.config/opencode/`:

| Source | Destination |
| --- | --- |
| `config/opencode.jsonc` | `~/.config/opencode/opencode.jsonc` |
| `config/cli.json` | `~/.config/opencode/cli.json` |
| `config/AGENTS.md` | `~/.config/opencode/AGENTS.md` |
| `config/package.json`, `config/package-lock.json` | `~/.config/opencode/` |
| `plugins/*` (for example `rtk.ts`, `graphify.js`) | `~/.config/opencode/plugins/` |
| `skills/*` (vendored `graphify`, `orchestrating-spec-pipelines`) | `~/.config/opencode/skills/` |
| `delegate/config.json` | `~/.config/delegate-skills/config.json` |

Other steps:

- **Binaries**, installed only when the command is missing, never as root:
  OpenCode V2 (`https://opencode.ai/v2/install`), `uv` (official standalone
  installer), `rtk` (`rtk-ai/rtk` installer), `headroom`
  (`uv tool install headroom-ai`), and `graphify` (`uv tool install graphifyy`).
  `~/.local/bin` and `~/.opencode/bin` are added to `PATH` for the rest of the
  run. `--config-only` skips this phase entirely.
- **Local plugin dependencies**: `npm install --omit=dev` inside
  `~/.config/opencode`, gated on a missing `node_modules/@opencode/plugin` or a
  changed `package-lock.json` hash (stamped in `~/.config/opencode/.lockhash`).
- **Delegation skills** via `npx --yes skills add`: `amElnagdy/delegate-skills`
  (20 skills) and `vercel-labs/skills@find-skills`, installed globally under
  `~/.agents/skills/`. When all three expected skill trees already exist and
  `--force` is not set, this step is skipped and prints `skills up to date`.
- **Stale cleanup**: an old `~/.config/opencode/opencode.json` (the V1 file that
  could re-merge conflicting settings) and `opencode.jsonc.headroom-backup` are
  backed up and removed.
- **Delegate lanes** from `delegate/config.json`, each with an `opencode`
  implementer and a model per lane.

## Requirements

- `bash` 4.4 or newer and `curl` on `PATH`.
- Node.js ≥ 18 (for `npx` and the V2 plugin runtime). If Node is missing or too
  old, the installer stops with the exact `nvm` command to run; it does not
  install a runtime silently.
- `git` and network access to clone this repository and reach the upstream
  installers. On a fresh machine `--config-only` still needs network access for
  `npx skills add`; once all three skill trees are present, a plain rerun
  installs nothing from the network.
- GitHub credentials for this **private** repository, established *before*
  cloning: run `gh auth login` (choose GitHub.com → HTTPS) or register an SSH
  key and use the SSH URL. `gh` (https://cli.github.com/) also provides
  `gh repo clone` for the primary quick-start path.

## Quick start

The repository is private, so authenticate to GitHub **before** cloning.
`gh auth login` establishes HTTPS credentials that `gh repo clone` and later
`git push` calls can use:

```sh
gh auth login                        # GitHub.com -> HTTPS; authenticate once
gh repo clone omarahmedZa/ai-dev-setup
cd ai-dev-setup
./install.sh --dry-run   # optional: print the plan, write nothing
./install.sh
./install.sh --doctor
```

If `gh` is not installed, or you already have an SSH key registered with GitHub,
clone over SSH instead:

```sh
git clone git@github.com:omarahmedZa/ai-dev-setup.git
cd ai-dev-setup
./install.sh
```

`--dry-run` first is recommended on a machine that already has an OpenCode
config: it reports creates, overwrites, stale removals, and the npm/skills
actions without touching disk.

## Flags

| Flag | Behavior |
| --- | --- |
| `--dry-run` | Print every action, write nothing. |
| `--force` | Overwrite destinations that differ from the repository. A backup is still taken first. |
| `--config-only` | Skip binary installation; still do config, plugins, npm install, skills, and delegation lanes. |
| `--with-headroom` | After the config install, run `headroom deploy --target opencode --port 8787`, then re-assert the repository `opencode.jsonc` so the repo version always wins. A deploy failure only warns. |
| `--doctor` | Run checks only, print `PASS`/`FAIL` lines, and exit non-zero if any check fails. |
| `--help`, `-h` | Print usage and exit. |

### Drift and backups

Existing destinations are compared byte-for-byte. If any differ and `--force`
was not passed, the installer backs each one up, prints
`refusing to overwrite: <path>` for every affected file, and exits non-zero
**without creating, modifying, or removing any destination**. Re-run with
`--force` to accept the repository version.

Backups live under `~/.config/opencode/backups/<UTC timestamp>/`, preserving each
file's path relative to the config directory (so the delegate config lands in
`backups/<timestamp>/delegate-skills/config.json`).

With no payload changes, the copy phase writes nothing and reports
`up to date (N files unchanged)`; npm install is skipped when `.lockhash` still
matches. Once all three skill trees exist under `~/.agents/skills/`, the
delegation-skills step is skipped too (`skills up to date`), so a fully
provisioned rerun performs no network action. Pass `--force` to refresh the
upstream skills.

## What is never installed

This repository is not a secrets store and never reads, prints, or copies
secrets.

- `service.json` (machine-generated, holds a service password) is never copied.
- `.env` files, provider API keys, and subscription/session state
  (for example `~/.headroom`) are not part of the payload.
- `node_modules/`, `backups/`, and `*.headroom-backup` are gitignored and not
  shipped.
- Only `~/.config/opencode/AGENTS.md` is managed; the home-level `~/AGENTS.md`
  used by non-OpenCode agents is out of scope.

Keep it that way: never add a secret to `config/`, `plugins/`, `skills/`, or
`delegate/`. `--dry-run` output contains paths and planned actions only.

## Manual steps (printed, never executed)

The installer prints these at the end of a real run:

1. `opencode auth login` — authenticate each provider you use.
2. Sign in to your headroom account if the proxy backend requires it (only
   relevant with `--with-headroom`).
3. `gh auth login` — authenticate GitHub if you did not already do so before
   cloning (the primary quick start does); needed for HTTPS pushes.

## Doctor

```sh
./install.sh --doctor
```

The doctor is read-only: it never starts an OpenCode service and never calls the
OpenCode API. It prints one `PASS`/`FAIL` line per check and a
`doctor: N passed, M failed, K skipped` summary; the exit status is non-zero if
anything failed.

Checks:

1. Commands present and their versions printed: `git`, `node`, `opencode`, `uv`,
   `rtk`, `headroom`, `graphify`. Requires Node ≥ 18 and OpenCode V2 (major ≥ 2).
2. `opencode.jsonc`, `cli.json`, and `AGENTS.md` exist under
   `~/.config/opencode/`.
3. `opencode.jsonc` parses as JSON and contains `mcp.servers.headroom`,
   `mcp.servers.serena`, and `providers.headroom`.
4. `~/.config/opencode/node_modules/@opencode/plugin` exists.
5. `~/.agents/skills/opencode-delegate/SKILL.md` and
   `~/.agents/skills/delegate-setup/SKILL.md` exist.
6. `~/.config/delegate-skills/config.json` parses, defines at least one lane,
   and every lane names an implementer.
7. `rtk rewrite "git status"` emits `rtk git status` (the exit status is ignored,
   because rtk exits 3 when no global hook is installed).
8. Port 8787 is listening — only with `--with-headroom` (skipped when `ss` is
   unavailable).
9. `opencode debug paths config` resolves to the OpenCode config directory
   (`~/.config/opencode` by default; `$XDG_CONFIG_HOME` is honored).

## Update flow

```sh
cd ai-dev-setup
git pull
./install.sh --force
./install.sh --doctor
```

`--force` is expected on updates because the repository payload changed. There
is no live-edit symlinking: changes made on a machine are copied back into
`config/`, `plugins/`, `skills/`, or `delegate/` manually and committed.

## Refreshing the vendored graphify skill

`skills/graphify/` is vendored so a fresh machine works without an extra network
step. To refresh it from the installed `graphify` CLI:

```sh
graphify install --platform opencode     # writes the current skill into ~/.config/opencode/skills/graphify/
cp -R ~/.config/opencode/skills/graphify/. skills/graphify/
```

Review the diff and commit. The copy includes `.graphify_version`, so the
version marker tracks the CLI automatically; also check `git status` for files
the new release removed, since `cp` does not delete them.

## If `npx skills add` changes

The installer depends on the upstream skills CLI. If `npx skills add` fails or
the layout changes, install the delegation skills manually:

```sh
git clone https://github.com/amElnagdy/delegate-skills.git
mkdir -p ~/.agents/skills
cp -R delegate-skills/skills/* ~/.agents/skills/
```

Then re-run `./install.sh --doctor`; it verifies
`~/.agents/skills/opencode-delegate/SKILL.md` and
`~/.agents/skills/delegate-setup/SKILL.md`. `find-skills` comes from
`vercel-labs/skills`; if it is missing, add that skill directory the same way.

## Development

```sh
./tests/run.sh                  # full test suite (fake HOME under the temp dir)
shellcheck install.sh tests/*.sh
```

The tests fake `HOME` so they never touch a real `~/.config/opencode`.
The implementation plan and design live in
`docs/superpowers/plans/` and `docs/superpowers/specs/`.

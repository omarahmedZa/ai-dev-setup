<!-- headroom:rtk-instructions -->
# RTK (Rust Token Killer) - Token-Optimized Commands

When running shell commands, **always prefix with `rtk`**. This reduces context
usage by 60-90% with zero behavior change. If rtk has no filter for a command,
it passes through unchanged — so it is always safe to use.

## Key Commands
```bash
# Git (59-80% savings)
rtk git status          rtk git diff            rtk git log

# Files & Search (60-75% savings)
rtk ls <path>           rtk read <file>         rtk grep <pattern>
rtk find <pattern>      rtk diff <file>

# Test (90-99% savings) — shows failures only
rtk pytest tests/       rtk cargo test          rtk test <cmd>

# Build & Lint (80-90% savings) — shows errors only
rtk tsc                 rtk lint                rtk cargo build
rtk prettier --check    rtk mypy                rtk ruff check

# Analysis (70-90% savings)
rtk err <cmd>           rtk log <file>          rtk json <file>
rtk summary <cmd>       rtk deps                rtk env

# GitHub (26-87% savings)
rtk gh pr view <n>      rtk gh run list         rtk gh issue list

# Infrastructure (85% savings)
rtk docker ps           rtk kubectl get         rtk docker logs <c>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->

## Delegation policy (delegate lanes)

Delegate proactively — do not wait for me to say "delegate" — when a task is bounded and
reviewable. Lane mapping:

- clear bug with a symptom/repro → lane `bug-fixes`
- writing or updating tests → lane `tests`
- well-scoped feature/refactor, multi-file → lane `implementation`
- hard logic, concurrency, migrations → lane `complex`
- research/exploration spike → lane `research-prototyping`
  (Engineering or Economics topic → override `--model opencode-go/mimo-v2.6-pro`)

Do it inline instead when: the change is trivial (one small edit), the task is ambiguous or
needs design judgment, it's review-only, or it depends on unstated conversation context.

### Brief-first workflow (always, before any dispatch)

1. **Optimize my prompt into a delegation brief** using the block skeleton:
   `<task>`, `<verification_loop>`, `<action_safety>`, `<structured_output_contract>`.
   Add `<completeness_contract>` + `<missing_context_gating>` for debugging work, or
   `<research_mode>` for research work. Include the repo's REAL gate commands, discovered
   from AGENTS.md / Makefile / package.json — never assume them.
2. **Discover what you can yourself.** For everything else, ask me in ONE round only for
   facts you cannot discover: repro steps, intended behavior, what must not change, and
   any constraint a judgment call rests on. Do not invent those facts.
3. **Show me the finished brief** plus the lane and model you intend to use, and wait for my
   approval. Never dispatch before I approve the brief.
4. **After approval**, load the matching `*-delegate` skill and dispatch with `--lane <name>`
   in a fresh session (never `--resume-last` / `--session`). Never let the implementer commit;
   review the diff and land it yourself, then report what landed.

If a premise in an approved brief turns out wrong mid-run, stop the run and re-dispatch a
corrected brief rather than discounting the output afterward.

Lane map: `~/.config/delegate-skills/config.json`
